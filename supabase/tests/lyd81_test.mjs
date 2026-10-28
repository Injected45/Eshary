import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const ADMIN = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const A_RATE = '33333333-3333-3333-3333-333333333333';
const A_NORATE = '44444444-4444-4444-4444-444444444444';

// ---- the placeholder of the earlier builds is emptied by the migration -------
{
  console.log('— an entry saved before 0081 with the hidden rate 1 loses it');
  const db = await freshDb({ upTo: 80 });
  await db.exec(`
    insert into auth.users (id, email) values ('${ADMIN}', 'a@x.ly');
    insert into account_licenses (user_id, status, license_type) values ('${ADMIN}', 'active', 'lifetime')
      on conflict (user_id) do update set status = 'active';`);
  const c = (await db.query(`insert into companies (owner_id, name, start_ref) values ($1, 'ب', 'R1') returning id`, [ADMIN])).rows[0].id;
  const x = (await db.query(`insert into exchanges (company_id, name, balance) values ($1, 'ص', 0) returning id`, [c])).rows[0].id;
  await as(db, ADMIN, (tx) => tx.query(`select record_currency_buy($1,$2,null,null,500,1,500,'')`, [c, x]));
  await as(db, ADMIN, (tx) => tx.query(`select record_currency_buy($1,$2,null,null,100,7.25,725,'')`, [c, x]));
  await as(db, ADMIN, (tx) => tx.query(`select record_transfer($1,$2,'م',null,null,50,'R1')`, [c, x]));
  const fs = await import('node:fs');
  const sql = fs.readFileSync(new URL('../migrations/0081_lyd_exchange_rate.sql', import.meta.url), 'utf8');
  await db.exec('set search_path = public, extensions;\n' + sql);
  const buys = (await db.query(`select usd_amount::float u, rate::float r, lyd_amount::float l from currency_buys order by usd_amount`)).rows;
  ok(buys[0].u === 100 && buys[0].r === 7.25 && buys[0].l === 725, 'a real rate is kept', JSON.stringify(buys[0]));
  ok(buys[1].u === 500 && buys[1].r === null && buys[1].l === null, 'the placeholder 1 is emptied', JSON.stringify(buys[1]));
  const t = (await db.query(`select rate, lyd_amount from transfers`)).rows[0];
  ok(t.rate === null && t.lyd_amount === null, 'an old exit has no rate');
  ok((await db.query(`select balance::float b from exchanges`)).rows[0].b === 550, 'no balance moved by the migration');
  await db.exec('set search_path = public, extensions;\n' + sql);
  ok((await db.query(`select count(*)::int n from currency_buys where rate is null`)).rows[0].n === 1, 'running it again changes nothing');
}

// ---- the save functions --------------------------------------------------------
// the database as 0081 left it (0083 later split rate_edit, see rate83_test.mjs)
const db = await freshDb({ upTo: 81 });
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf'))),
    ('${OTHER}', 'o@x.ly', 'x'), ('${A_RATE}', null, null), ('${A_NORATE}', null, null);
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';
`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'بهاروز', 'Rh0100') returning id`, [ADMIN]))[0].id;
const x1 = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'صرافة', 100000) returning id`, [c1]))[0].id;
const emp = async (name, phone, perms) => (await q(
  `insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
   values ($1, $2, $3, 'x', $4::text[]) returning id`, [ADMIN, name, phone, perms]))[0];
const withRate = await emp('بصلاحية السعر', '0911111111', ['transfers_create', 'buys_create', 'rate_edit']);
const noRate = await emp('بلا صلاحية السعر', '0922222222', ['transfers_create', 'buys_create']);
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1'),($3,$4,'d2')`,
  [withRate.id, A_RATE, noRate.id, A_NORATE]);

const exit = (uid, amount, rate) => as(db, uid, (tx) => tx.query(
  rate === undefined
    ? `select * from record_transfer($1,$2,'مستفيد',null,null,$3,'R')`
    : `select * from record_transfer($1,$2,'مستفيد',null,null,$3,'R',$4)`,
  rate === undefined ? [c1, x1, amount] : [c1, x1, amount, rate])).then((r) => r.rows[0]);
const entry = (uid, usd, rate, lyd = null) => as(db, uid, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,null,null,$3,$4,$5,'')`, [c1, x1, usd, rate, lyd])).then((r) => r.rows[0]);
const rates = (uid) => as(db, uid, (tx) => tx.query(`select current_exchange_rates() r`)).then((r) => r.rows[0].r);
const n = (v) => (v === null ? null : Number(v));

console.log('— the permission key is accepted');
const keys = (await q(`select _employee_permission_keys() k`))[0].k;
ok(keys.length === 11 && keys.includes('rate_edit') && keys.includes('clients_add') && keys.includes('party_letters'), 'eleven keys, none lost', JSON.stringify(keys));

console.log('— before any rate: nothing to show');
let r = await rates(ADMIN);
ok(r.sell === null && r.buy === null && r.can_edit === true, 'admin: no rates yet, may edit', JSON.stringify(r));
r = await rates(A_NORATE);
ok(r.can_edit === false, 'employee without the permission may not edit');
ok((await rates(A_RATE)).can_edit === true, 'employee with the permission may edit');
await rejects(exit(A_NORATE, 10, 7), 'rate_not_set', 'an employee without permission cannot save before the admin set a rate');

console.log('— the administrator: an exit at the sell rate');
const t1 = await exit(ADMIN, 1000, 7.25);
ok(n(t1.rate) === 7.25 && n(t1.lyd_amount) === 7250, '1000 × 7.25 = 7250.00', JSON.stringify([t1.rate, t1.lyd_amount]));
const t2 = await exit(ADMIN, 333.33, 7.1234);
ok(n(t2.lyd_amount) === 2374.44, 'rounded to the dirham: 333.33 × 7.1234 = 2374.442922 → 2374.44', String(t2.lyd_amount));
const t3 = await exit(ADMIN, 0.07, 7.5);
ok(n(t3.lyd_amount) === 0.53, 'half rounds up: 0.07 × 7.5 = 0.525 → 0.53', String(t3.lyd_amount));
const t4 = await exit(ADMIN, 100, 7.12345);
ok(n(t4.rate) === 7.1235, 'a rate is kept to 4 decimals', String(t4.rate));
ok(n(t4.lyd_amount) === 712.35, 'and the dinars use the stored rate', String(t4.lyd_amount));
ok((await q(`select balance::text b from exchanges`))[0].b === '98566.60', 'the dollar balance moves as before');
ok(n((await rates(ADMIN)).sell) === 7.1235, 'the last sell rate is remembered');
await rejects(exit(ADMIN, 10, 0), 'rate_invalid', 'a rate of 0 is refused');
await rejects(exit(ADMIN, 10, -7), 'rate_invalid', 'a negative rate is refused');

console.log('— the administrator: an entry at the buy rate, the app\'s dinars are ignored');
const b1 = await entry(ADMIN, 500, 7.05, 999999);
ok(n(b1.rate) === 7.05 && n(b1.lyd_amount) === 3525, '500 × 7.05 = 3525.00 (not what the phone sent)', JSON.stringify([b1.rate, b1.lyd_amount]));
r = await rates(ADMIN);
ok(n(r.buy) === 7.05 && n(r.sell) === 7.1235, 'buy and sell are kept apart', JSON.stringify(r));

console.log('— an employee WITHOUT the permission gets the administrator\'s last rate');
const e1 = await exit(A_NORATE, 200, 9.99);
ok(n(e1.rate) === 7.1235 && n(e1.lyd_amount) === 1424.70, 'whatever the phone sent, 200 × 7.1235', JSON.stringify([e1.rate, e1.lyd_amount]));
const e2 = await entry(A_NORATE, 100, 1.5);
ok(n(e2.rate) === 7.05 && n(e2.lyd_amount) === 705, 'entry at the last buy rate', JSON.stringify([e2.rate, e2.lyd_amount]));
const e3 = await exit(A_NORATE, 10);
ok(n(e3.rate) === 7.1235, 'an older build that sends no rate still gets it');
ok(n((await rates(ADMIN)).sell) === 7.1235, 'an employee never changes the administrator\'s last rate');

console.log('— an employee WITH the permission types the rate');
const e4 = await exit(A_RATE, 100, 7.3);
ok(n(e4.rate) === 7.3 && n(e4.lyd_amount) === 730, 'their own rate', JSON.stringify([e4.rate, e4.lyd_amount]));
ok(n((await rates(ADMIN)).sell) === 7.1235, 'and the administrator\'s last rate does not change');

console.log('— an older build of the app');
const o1 = await exit(ADMIN, 50);
ok(o1.rate === null && o1.lyd_amount === null, 'an exit without a rate is still saved, empty');
const o2 = await entry(ADMIN, 60, 1, 60);
ok(o2.rate === null && o2.lyd_amount === null, 'the placeholder rate 1 of an entry is stored empty');
ok(n((await rates(ADMIN)).buy) === 7.05, 'and is not remembered as the last buy rate');

console.log('— nobody can write a wrong pair directly');
let err = '';
try { await q(`update transfers set rate = 7, lyd_amount = null where id = $1`, [t1.id]); } catch (e) { err = e.message; }
ok(err.includes('transfers_rate_pair'), 'a rate without dinars is refused', err);
const direct = await as(db, ADMIN, (tx) => tx.query(`select * from last_exchange_rates`)).catch((e) => ({ rows: null, e }));
ok(direct.rows === null || direct.rows.length === 0, 'the last rates are not readable directly');
await rejects(as(db, ADMIN, (tx) => tx.query(`select _operation_rate('sell', 7)`)), 'permission denied', 'the helper cannot be called by the app');

console.log('— cancelling keeps the values, the balance goes back in dollars');
await as(db, ADMIN, (tx) => tx.query(`select admin_cancel_operation('transfer', $1, 'خطأ', 'pass-1234')`, [t1.id]));
const c = (await q(`select cancelled_at, rate::float, lyd_amount::float from transfers where id = $1`, [t1.id]))[0];
ok(c.cancelled_at && c.rate === 7.25 && c.lyd_amount === 7250, 'a cancelled exit keeps its rate and dinars', JSON.stringify(c));

console.log('— the same figures as the phone shows (test/lyd_rate_test.dart)');
const p1 = await exit(ADMIN, 0.125, 8);
ok(p1.amount === '0.13' || n(p1.amount) === 0.13, 'the dollars are stored to the cent', String(p1.amount));
ok(n(p1.lyd_amount) === 1.04, 'and the dinars use that cent: 0.13 × 8 = 1.04', String(p1.lyd_amount));
const p2 = await exit(ADMIN, 999.99, 7.12345);
ok(n(p2.rate) === 7.1235 && n(p2.lyd_amount) === 7123.43, '999.99 × 7.1235 = 7123.428765 → 7123.43', JSON.stringify([p2.rate, p2.lyd_amount]));

console.log('— another administrator sees nothing of this');
r = await rates(OTHER);
ok(r.sell === null && r.buy === null, 'their own (empty) rates');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
