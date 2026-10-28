import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
const files = (n) => JSON.stringify({
  'arm64-v8a': { url: `https://x/app-releases/${n}/Eshary-64.apk`, sha256: 'a'.repeat(64), size: 1 },
  'armeabi-v7a': { url: `https://x/app-releases/${n}/Eshary-32.apk`, sha256: 'b'.repeat(64), size: 1 },
});
const add = (build, name, mandatory = true, active = true) => q(
  `insert into app_releases (build_number, version_name, mandatory, notes, files, is_active)
   values ($1,$2,$3,'ملاحظات',$4::jsonb,$5) returning id`, [build, name, mandatory, files(build), active]).then((r) => r[0].id);
const latest = async () => (await q(`select latest_app_release() r`))[0].r;

// anyone (also before sign-in) can ask; nobody can read the table
const anon = async (fn) => db.transaction(async (tx) => { await tx.exec(`set local role anon`); return fn(tx); });

console.log('— nothing published');
ok(await latest() === null, 'null when there is no release');

console.log('— the newest active release is offered');
const id1 = await add(2, '1.0.1');
const id2 = await add(3, '1.0.2');
let r = await latest();
ok(r.buildNumber === 3 && r.versionName === '1.0.2', 'build 3', JSON.stringify(r));
ok(r.mandatory === true && r.minBuildNumber === 3, 'mandatory, min build 3');
ok(r.files['arm64-v8a'].sha256.length === 64 && r.files['armeabi-v7a'].url.endsWith('32.apk'), 'both files with their checksum');
ok(r.notes === 'ملاحظات', 'notes');

console.log('— a later OPTIONAL release never un-forces an older mandatory one');
const id3 = await add(4, '1.0.3', false);
r = await latest();
ok(r.buildNumber === 4 && r.mandatory === false, 'newest is build 4, optional');
ok(r.minBuildNumber === 3, 'but the minimum is still 3 (an app on build 2 is forced)', JSON.stringify(r));

console.log('— withdrawing a bad release');
await db.query(`update app_releases set is_active = false where id = $1`, [id3]);
r = await latest();
ok(r.buildNumber === 3, 'back to build 3');
await db.query(`update app_releases set is_active = false where id = $1`, [id2]);
r = await latest();
ok(r.buildNumber === 2 && r.minBuildNumber === 2, 'back to build 2');
await db.query(`update app_releases set is_active = false where id = $1`, [id1]);
ok(await latest() === null, 'all withdrawn: the app is not asked to update');
await db.query(`update app_releases set is_active = true`);

console.log('— who may read and write');
const viaAnon = await anon(async (tx) => (await tx.query(`select latest_app_release() r`)).rows[0].r);
ok(viaAnon.buildNumber === 4, 'an anonymous caller (before sign-in) can read the latest release');
await rejects(anon((tx) => tx.query(`select * from app_releases`)), 'permission denied', 'no direct read of the table');
await rejects(anon((tx) => tx.query(`insert into app_releases (build_number, version_name, files) values (9,'x','{"arm64-v8a":{}}')`)), 'permission denied', 'no direct write');
const U = '11111111-1111-1111-1111-111111111111';
await db.exec(`insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values ('${U}','u@x.ly','x','{}')`);
await rejects(as(db, U, (tx) => tx.query(`select * from app_releases`)), 'permission denied', 'a signed-in user cannot read the table either');
ok((await as(db, U, (tx) => tx.query(`select latest_app_release() r`))).rows[0].r.buildNumber === 4, 'but can ask for the latest');

console.log('— the table refuses bad rows');
await rejects(q(`insert into app_releases (build_number, version_name, files) values (0,'x','{"arm64-v8a":{}}')`), 'check', 'build number must be positive');
await rejects(q(`insert into app_releases (build_number, version_name, files) values (10,'','{"arm64-v8a":{}}')`), 'check', 'a version name is needed');
await rejects(q(`insert into app_releases (build_number, version_name, files) values (10,'x','[]')`), 'check', 'files is an object');
await rejects(q(`insert into app_releases (build_number, version_name, files) values (10,'x','{"x86":{}}')`), 'check', 'at least an arm file');
await rejects(q(`insert into app_releases (build_number, version_name, files) values (4,'dup','{"arm64-v8a":{}}')`), 'unique', 'one row per build');

console.log('— the platform: list, withdraw, restore (with the audit)');
const S = '22222222-2222-2222-2222-222222222222';
const V = '33333333-3333-3333-3333-333333333333';
await db.exec(`insert into auth.users (id, email, encrypted_password) values ('${S}','s@x.ly','x'),('${V}','v@x.ly','x')`);
await db.query(`select platform_staff_add($1,'super_admin','المدير','+218912345678',null)`, [S]);
await db.query(`select platform_staff_add($1,'viewer','مراقب','+218922222222',$2)`, [V, S]);
async function login(uid, sid) {
  await db.exec(`update wa_challenges set created_at = created_at - interval '2 minutes'`);
  await db.query(`select platform_login_start($1,'1.1.1.1')`, [uid]);
  const row = (await q(`select id from wa_challenges where purpose='platform_login' and consumed_at is null and revoked_at is null order by created_at desc limit 1`))[0];
  await db.query(`update wa_challenges set code_mac = _code_mac('123456',$1) where id=$1`, [row.id]);
  await db.query(`select platform_login_verify($1,'123456',$2,'1.1.1.1')`, [uid, sid]);
}
await login(S, 's1');
await login(V, 's2');
const jwt = (uid, sid, fn) => db.transaction(async (tx) => {
  await tx.exec(`set local role authenticated; select set_config('request.jwt.claim.sub','${uid}',true);
    select set_config('request.jwt.claims','{"sub":"${uid}","session_id":"${sid}"}',true);`);
  return fn(tx);
});
const list = (await jwt(S, 's1', (tx) => tx.query(`select * from platform_releases_list()`))).rows;
ok(list.length === 3 && list[0].build_number === 4, 'the platform lists the releases, newest first');
await jwt(S, 's1', (tx) => tx.query(`select platform_release_set_active($1, false)`, [id3]));
ok((await latest()).buildNumber === 3, 'withdrawing from the platform takes effect at once');
ok((await q(`select count(*)::int n from audit_log where kind = 'app_release_toggled'`))[0].n === 1, 'audited');
await rejects(jwt(V, 's2', (tx) => tx.query(`select platform_release_set_active($1, true)`, [id3])), 'platform_forbidden', 'a viewer cannot withdraw');
ok((await jwt(V, 's2', (tx) => tx.query(`select * from platform_releases_list()`))).rows.length === 3, 'a viewer can look');
await jwt(S, 's1', (tx) => tx.query(`select platform_release_set_active($1, true)`, [id3]));
ok((await latest()).buildNumber === 4, 'restored');
await rejects(jwt(S, 's1', (tx) => tx.query(`select platform_release_set_active('99999999-9999-9999-9999-999999999999', true)`)), 'release_not_found', 'unknown release');

console.log('— running the file twice is harmless');
const fs = await import('node:fs');
await db.exec(fs.readFileSync(new URL('../migrations/0079_app_releases.sql', import.meta.url), 'utf8'));
ok((await latest()).buildNumber === 4, 'data kept');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
