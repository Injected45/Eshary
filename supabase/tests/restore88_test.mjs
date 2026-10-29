import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const A = '11111111-1111-1111-1111-111111111111';
const PLATFORM = '22222222-2222-2222-2222-222222222222';
const B = '44444444-4444-4444-4444-444444444444';
const n = (v) => (v === null || v === undefined ? null : Number(v));

const db = await freshDb({ upTo: 92 }); // a sale paid in cash from the account's dollars: 0093 sells from the cash book only
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values
    ('${A}', 'a@x.ly', extensions.crypt('pass-a', extensions.gen_salt('bf')), '{"full_name":"الرحالة"}'),
    ('${PLATFORM}', 'p@x.ly', 'x', '{}'),
    ('${B}', 'b@x.ly', extensions.crypt('pass-b', extensions.gen_salt('bf')), '{}');
  insert into account_licenses (user_id, status, license_type) values
    ('${A}', 'active', 'lifetime'), ('${B}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';
  insert into account_licenses (user_id, status, license_type, is_admin) values
    ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);

const company = async (uid, ref) => (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'شركة', $2) returning id`, [uid, ref]))[0].id;
const open = (uid, c, bal, cost) => as(db, uid, (tx) => tx.query(`select * from admin_open_account($1,'حساب',$2,null,null,$3)`, [c, bal, cost])).then((r) => r.rows[0]);
const sell = (uid, c, ex, usd) => as(db, uid, (tx) => tx.query(`select * from record_transfer($1,$2,'م',null,null,$3,'',7.3,'cash')`, [c, ex, usd])).then((r) => r.rows[0]);
const buy = (uid, c, ex, usd) => as(db, uid, (tx) => tx.query(`select * from record_currency_buy($1,$2,null,null,$3,7.1,null,'','cash')`, [c, ex, usd])).then((r) => r.rows[0]);
const bal = async (id) => n((await q(`select balance from exchanges where id = $1`, [id]))[0]?.balance);
const count = async (tbl, uid) => (await q(`select count(*)::int k from ${tbl} where owner_id = $1`, [uid]))[0].k;

const cA = await company(A, 'Rh0100');
const exA = await open(A, cA, 1000, 7.0);
await sell(A, cA, exA.id, 100);
await buy(A, cA, exA.id, 50);
await as(db, A, (tx) => tx.query(`select lyd_open(500, 0)`));
const cB = await company(B, 'B100');
const exB = await open(B, cB, 2000, 7.2);
await sell(B, cB, exB.id, 300);

const backupId = (await q(`select _save_backup('manual') id`))[0].id;

console.log('— A wipes by mistake; B keeps working');
const w = (await as(db, A, (tx) => tx.query(`select owner_wipe_operations('pass-a') r`))).rows[0].r;
ok(w.ok === true, 'A wiped');
ok((await bal(exA.id)) === 0 && (await count('transfers', A)) === 0, 'A has nothing left');
await sell(B, cB, exB.id, 200);   // after the backup: must survive
ok((await bal(exB.id)) === 1500, 'B at 1,500');

console.log('— who is in the backup');
const owners = (await as(db, PLATFORM, (tx) => tx.query(`select admin_backup_owners($1) r`, [backupId]))).rows[0].r;
const oa = owners.find((o) => o.owner_id === A);
ok(owners.length === 2 && oa && oa.name === 'الرحالة' && oa.transfers === 1 && oa.currency_buys === 1, 'both subscribers, with their operations', JSON.stringify(owners));
await rejects(as(db, A, (tx) => tx.query(`select admin_backup_owners($1)`, [backupId])), 'admin only', 'a subscriber cannot list a backup');
await rejects(as(db, A, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [backupId, A])), 'admin only', 'nor restore himself');

console.log('— the platform restores A only');
const r = (await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2) r`, [backupId, A]))).rows[0].r;
ok(r.transfers === 1 && r.currency_buys === 1 && r.exchanges === 1 && r.companies === 1, 'A\'s rows came back', JSON.stringify(r));
ok((await bal(exA.id)) === 950, 'A\'s balance is back: 1,000 − 100 + 50', String(await bal(exA.id)));
ok((await count('account_costs', A)) === 1 && (await count('lyd_treasury', A)) === 1 && (await count('balance_adjustments', A)) === 1, 'A\'s cost, dinar treasury and opening line are back');
ok((await bal(exB.id)) === 1500 && (await count('transfers', B)) === 2, 'B is untouched: the exit made after the backup is still there');
ok((await q(`select count(*)::int k from backups where kind = 'pre_restore'`))[0].k === 1, 'a safety snapshot was taken first');

console.log('— running it again gives the same, nothing doubled');
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [backupId, A]));
ok((await count('transfers', A)) === 1 && (await bal(exA.id)) === 950, 'still one exit, 950');
ok((await count('transfers', B)) === 2, 'B still has his two');

console.log('— A works on after the restore');
const t = await sell(A, cA, exA.id, 10);
ok(t.reference === 'Rh0101', 'the numbering follows the restored operations', t.reference);
await rejects(as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, ['00000000-0000-0000-0000-000000000000', A])), 'backup_not_found', 'an unknown backup');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
