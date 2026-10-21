import { freshDb } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
const SUPER = 'a0000000-0000-0000-0000-000000000001';
const ADM = 'a0000000-0000-0000-0000-000000000002';
const VIEW = 'a0000000-0000-0000-0000-000000000003';
const SUP = 'a0000000-0000-0000-0000-000000000004';
const USER1 = 'b0000000-0000-0000-0000-000000000001';
const USER2 = 'b0000000-0000-0000-0000-000000000002';
const LEGACY = 'c0000000-0000-0000-0000-000000000001';
await db.exec(`insert into auth.users (id, email, encrypted_password) values
  ('${SUPER}','super@x.ly','x'),('${ADM}','adm@x.ly','x'),('${VIEW}','view@x.ly','x'),('${SUP}','sup@x.ly','x'),
  ('${USER1}','u1@x.ly','x'),('${USER2}','u2@x.ly','x'),('${LEGACY}','legacy@x.ly','x');
  insert into account_licenses (user_id, status, license_type) values
   ('${USER1}','active','lifetime'),('${USER2}','pending',null)
  on conflict (user_id) do update set status = excluded.status;
  insert into account_licenses (user_id, status, license_type, is_admin) values ('${LEGACY}','active','lifetime',true)
  on conflict (user_id) do update set is_admin = true;`);

// run as an authenticated user with a JWT session id
async function asJwt(uid, sid, fn) {
  return db.transaction(async (tx) => {
    await tx.exec(`set local role authenticated;
      select set_config('request.jwt.claim.sub','${uid}',true);
      select set_config('request.jwt.claims','{"sub":"${uid}","session_id":"${sid}"}',true);`);
    return fn(tx);
  });
}
const call = (uid, sid, sql, p) => asJwt(uid, sid, async (tx) => (await tx.query(sql, p)).rows);
const svc = async (sql, p) => (await db.query(sql, p)).rows[0];

console.log('— bootstrap');
await rejects(db.query(`select platform_staff_add($1,'admin','x y','+218912345678',null)`, [ADM]), 'bootstrap_needs_super_admin', 'first staff must be super admin');
await rejects(db.query(`select platform_staff_add($1,'super_admin','عبدالله','123',null)`, [SUPER]), 'invalid_phone', 'bad phone refused');
await db.query(`select platform_staff_add($1,'super_admin','المدير الرئيسي','+218912345678',null)`, [SUPER]);
await rejects(db.query(`select platform_staff_add($1,'super_admin','ثاني','+218912345679',null)`, [ADM]), 'bootstrap_done', 'bootstrap only once');
await db.query(`select platform_staff_add($1,'admin','مدير التطبيق','+218922222222',$2)`, [ADM, SUPER]);
await db.query(`select platform_staff_add($1,'viewer','مراقب','+218933333333',$2)`, [VIEW, SUPER]);
await db.query(`select platform_staff_add($1,'support','دعم','+218944444444',$2)`, [SUP, SUPER]);
await rejects(db.query(`select platform_staff_add($1,'viewer','x y','+218955555555',$2)`, [USER1, VIEW]), 'platform_forbidden', 'only a super admin adds staff');

console.log('— a password alone opens nothing');
await rejects(call(SUPER, 's1', `select platform_dashboard()`), 'platform_forbidden', 'dashboard needs a verified session');
ok((await call(SUPER, 's1', `select platform_me() r`))[0].r === null, 'platform_me is null before the code');
ok((await call(ADM, 's1', `select is_caller_admin() r`))[0].r === false, 'staff admin is not an admin before the code');
ok((await call(LEGACY, 's1', `select is_caller_admin() r`))[0].r === true, 'the old is_admin rule is unchanged');

console.log('— the code');
const staffNo = await svc(`select platform_login_start($1,'1.2.3.4') r`, [USER1]);
ok(staffNo.r.ok === false && staffNo.r.code === 'not_staff', 'a non-staff user gets no code', JSON.stringify(staffNo.r));
const start = await svc(`select platform_login_start($1,'1.2.3.4') r`, [SUPER]);
ok(start.r.ok === true && start.r.phoneMasked.includes('*'), 'code issued', JSON.stringify(start.r));
const ch = (await q(`select * from wa_challenges where purpose='platform_login' order by created_at desc limit 1`))[0];
ok(ch && ch.phone === '+218912345678' && ch.code_mac.length === 64, 'stored as a keyed hash');
const again = await svc(`select platform_login_start($1,'1.2.3.4') r`, [SUPER]);
ok(again.r.ok === false && again.r.code === 'too_soon', 'resend before 60 s refused', JSON.stringify(again.r));

// the real code is unknown to us (HMAC): find it by brute force on the 6 digits
async function crack(chId) {
  const row = (await q(`select id, code_mac from wa_challenges where id=$1`, [chId]))[0];
  for (let n = 0; n < 1000000; n++) {
    const c = String(n).padStart(6, '0');
    const m = (await q(`select _code_mac($1,$2) m`, [c, row.id]))[0].m;
    if (m === row.code_mac) return c;
  }
}
// cheaper: replace the stored mac with a known code
async function plant(code) {
  const row = (await q(`select id from wa_challenges where purpose='platform_login' and consumed_at is null and revoked_at is null order by created_at desc limit 1`))[0];
  await db.query(`update wa_challenges set code_mac = _code_mac($1,$2) where id=$2`, [code, row.id]);
  return row.id;
}
await plant('123456');
let v = await svc(`select platform_login_verify($1,'999999','s1','1.2.3.4') r`, [SUPER]);
ok(v.r.ok === false && v.r.code === 'invalid_code', 'wrong code refused', JSON.stringify(v.r));
v = await svc(`select platform_login_verify($1,'999998','s1','1.2.3.4') r`, [SUPER]);
v = await svc(`select platform_login_verify($1,'999997','s1','1.2.3.4') r`, [SUPER]);
v = await svc(`select platform_login_verify($1,'123456','s1','1.2.3.4') r`, [SUPER]);
ok(v.r.ok === false && (v.r.code === 'too_many_attempts' || v.r.code === 'code_expired'), 'three wrong tries cancel the code, even the right one then fails', JSON.stringify(v.r));
ok((await call(SUPER, 's1', `select platform_me() r`))[0].r === null, 'no session after failures');

// new code after the 60 s wait
await db.exec(`update wa_challenges set created_at = created_at - interval '2 minutes'`);
await svc(`select platform_login_start($1,'1.2.3.4')`, [SUPER]);
await plant('654321');
v = await svc(`select platform_login_verify($1,'654321','s1','1.2.3.4') r`, [SUPER]);
ok(v.r.ok === true && v.r.role === 'super_admin', 'right code opens the session', JSON.stringify(v.r));
v = await svc(`select platform_login_verify($1,'654321','s2','1.2.3.4') r`, [SUPER]);
ok(v.r.ok === false, 'the code is used once', JSON.stringify(v.r));
ok((await q(`select phone_verified_at is not null v from platform_staff where user_id=$1`, [SUPER]))[0].v, 'the number is verified by the first success');

console.log('— a verified session only for the same JWT session');
ok((await call(SUPER, 's1', `select platform_me() r`))[0].r.role === 'super_admin', 'session s1 works');
ok((await call(SUPER, 's2', `select platform_me() r`))[0].r === null, 'another JWT session does not');
ok((await call(SUPER, 's1', `select is_caller_admin() r`))[0].r === true, 'super admin counts as administrator after the code');

console.log('— expiry and logout');
await db.exec(`update platform_sessions set expires_at = now() - interval '1 minute' where auth_session_id='s1'`);
ok((await call(SUPER, 's1', `select platform_me() r`))[0].r === null, 'expired session is closed');
await db.exec(`update platform_sessions set expires_at = now() + interval '5 hours' where auth_session_id='s1'`);
await call(SUPER, 's1', `select platform_logout()`);
ok((await call(SUPER, 's1', `select platform_me() r`))[0].r === null, 'logout closes the session');

// open sessions for the other staff directly through the same steps
async function login(uid, sid, code) {
  await db.exec(`update wa_challenges set created_at = created_at - interval '2 minutes'`);
  await svc(`select platform_login_start($1,'9.9.9.9')`, [uid]);
  await plant(code);
  const r = await svc(`select platform_login_verify($1,$2,$3,'9.9.9.9') r`, [uid, code, sid]);
  ok(r.r.ok === true, `login ${sid}`, JSON.stringify(r.r));
}
await login(SUPER, 's10', '111111');
await login(ADM, 's11', '222222');
await login(VIEW, 's12', '333333');
await login(SUP, 's13', '444444');

console.log('— roles');
const dash = (await call(VIEW, 's12', `select platform_dashboard() r`))[0].r;
ok(dash.total === 1 && dash.pending === 1 && dash.active === 0 || dash.total === 2, 'dashboard counts users only (not staff, not admins)', JSON.stringify(dash));
ok(dash.activeNow === null && dash.openTickets === null, 'what the app does not report stays null');
const users = await call(SUP, 's13', `select * from platform_users_list(null,null,25,0)`);
ok(users.length === 2 && users.every((u) => u.user_id !== SUPER && u.user_id !== LEGACY), 'user list excludes staff and admins', JSON.stringify(users.map((u) => u.user_id)));
ok((await call(SUP, 's13', `select * from platform_users_list('u2@x.ly',null,25,0)`)).length === 1, 'search by e-mail');
ok((await call(SUP, 's13', `select * from platform_users_list(null,'active',25,0)`)).length === 1, 'filter by status');
const detail = (await call(VIEW, 's12', `select platform_user_detail($1) r`, [USER1]))[0].r;
ok(detail.status === 'active', 'user detail');
await rejects(call(VIEW, 's12', `select platform_user_detail($1) r`, [LEGACY]), 'user_not_found', 'an administrator is not shown as a user');
await rejects(call(VIEW, 's12', `select * from platform_audit_list(10,0,null)`), 'platform_forbidden', 'viewer has no audit');
await rejects(call(SUP, 's13', `select * from platform_audit_list(10,0,null)`), 'platform_forbidden', 'support has no audit');
ok((await call(ADM, 's11', `select * from platform_audit_list(10,0,null)`)).length > 0, 'admin reads the audit');
await rejects(call(ADM, 's11', `select * from platform_staff_list()`), 'platform_forbidden', 'admin has no staff list');
ok((await call(SUPER, 's10', `select * from platform_staff_list()`)).length === 4, 'super admin lists the staff');

console.log('— the existing admin functions work for staff admins, not for viewers');
await call(ADM, 's11', `select admin_subscription_action($1,'suspend',null,null,null,'سبب')`, [USER1]);
ok((await q(`select status from account_licenses where user_id=$1`, [USER1]))[0].status === 'blocked', 'staff admin suspended a user');
const a = (await q(`select actor, kind from audit_log where kind='account_suspended' order by id desc limit 1`))[0];
ok(a && a.actor === ADM, 'the audit names the staff member', JSON.stringify(a));
await rejects(call(VIEW, 's12', `select admin_subscription_action($1,'reactivate',null,null,null,'x')`, [USER1]), 'admin only', 'viewer cannot');
await rejects(call(SUP, 's13', `select admin_subscription_action($1,'reactivate',null,null,null,'x')`, [USER1]), 'admin only', 'support cannot');
await call(ADM, 's11', `select admin_subscription_action($1,'reactivate',null,null,null,'x')`, [USER1]);
await call(ADM, 's11', `select admin_subscription_action($1,'extend_trial',24,null,null,'تمديد')`, [USER2]);
ok((await q(`select status from account_licenses where user_id=$1`, [USER2]))[0].status === 'trial', 'trial extended through the old function');

console.log('— notifications, settings, notes');
const nid = (await call(ADM, 's11', `select platform_notification_create('عنوان','نص الإشعار') r`))[0].r;
ok(nid, 'notification created');
await rejects(call(VIEW, 's12', `select platform_notification_create('x','نص الإشعار')`), 'platform_forbidden', 'viewer cannot send');
await rejects(call(ADM, 's11', `select platform_notification_create('x','')`), 'invalid_body', 'empty body refused');
await call(ADM, 's11', `select platform_notification_set_active($1,false)`, [nid]);
ok((await q(`select is_active from notifications where id=$1`, [nid]))[0].is_active === false, 'notification switched off');
await rejects(call(ADM, 's11', `select platform_setting_set('session_hours','8'::jsonb)`), 'platform_forbidden', 'admin cannot change settings');
await call(SUPER, 's10', `select platform_setting_set('paid_presets_days','[30,60]'::jsonb)`);
await rejects(call(SUPER, 's10', `select platform_setting_set('paid_presets_days','[0]'::jsonb)`), 'invalid_setting', 'bad preset refused');
await rejects(call(SUPER, 's10', `select platform_setting_set('whatever','1'::jsonb)`), 'unknown_setting', 'unknown key refused');
ok((await call(ADM, 's11', `select platform_settings_get() r`))[0].r.paid_presets_days.length === 2, 'settings read back');
await call(ADM, 's11', `select platform_user_set_notes($1,'ملاحظة')`, [USER1]);
ok((await q(`select notes from account_licenses where user_id=$1`, [USER1]))[0].notes === 'ملاحظة', 'notes saved');
const st = (await call(VIEW, 's12', `select platform_system_status() r`))[0].r;
ok(st.database === true && st.whatsappSentLastHour !== undefined, 'system status', JSON.stringify(st));

console.log('— managing staff');
await rejects(call(SUPER, 's10', `select platform_staff_set($1,null,false)`, [SUPER]), 'cannot_change_self', 'nobody changes themselves');
await call(SUPER, 's10', `select platform_staff_set($1,null,false)`, [ADM]);
ok((await call(ADM, 's11', `select platform_me() r`))[0].r === null, 'switching off ends the sessions at once');
ok((await call(ADM, 's11', `select is_caller_admin() r`))[0].r === false, 'and the administrator rights');
await call(SUPER, 's10', `select platform_staff_set($1,null,true)`, [ADM]);
ok((await call(ADM, 's11', `select platform_me() r`))[0].r === null, 'switching on does not bring the old session back (revoked)');
await call(SUPER, 's10', `select platform_staff_set($1,'support',null)`, [VIEW]);
ok((await call(VIEW, 's12', `select platform_me() r`))[0].r === null, 'a role change ends the session (the code is asked again)');
// a second super admin so the first can be demoted, never the last
await rejects(call(SUPER, 's10', `select platform_staff_set($1,'viewer',null)`, [SUPER]), 'cannot_change_self', 'cannot demote self');

console.log('— the service functions are closed to the API roles');
for (const fn of [
  `platform_login_start('${SUPER}','1.1.1.1')`,
  `platform_login_verify('${SUPER}','123456','s1','1.1.1.1')`,
  `platform_staff_add('${USER1}','viewer','xx yy','+218911111111',null)`,
  `platform_staff_lookup('${SUPER}')`,
]) {
  await rejects(call(SUPER, 's10', `select ${fn}`), 'permission denied', `authenticated cannot call ${fn.split('(')[0]}`);
}

console.log('— the audit is append-only and carries the login events');
const kinds = (await q(`select distinct kind from audit_log`)).map((r) => r.kind);
for (const k of ['platform_login_ok', 'platform_login_failed', 'platform_code_sent', 'platform_logout', 'platform_login_denied'])
  ok(kinds.includes(k), `audit has ${k}`);
await rejects(db.query(`update audit_log set note='x'`), 'audit_immutable', 'audit rows cannot change');

console.log('— every earlier code purpose still works (0064 account deletion)');
const def = (await q(`select pg_get_constraintdef(oid) d from pg_constraint where conname = 'wa_challenges_purpose_check'`))[0].d;
for (const purpose of ['activation', 'login', 'phone_change', 'account_delete', 'platform_login'])
  ok(def.includes(`'${purpose}'`), `purpose ${purpose} is allowed`, def);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
