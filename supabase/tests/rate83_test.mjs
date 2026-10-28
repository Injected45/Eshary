import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const ADMIN = '11111111-1111-1111-1111-111111111111';
const A_SELL = '33333333-3333-3333-3333-333333333333';
const A_BUY = '44444444-4444-4444-4444-444444444444';
const A_BOTH = '55555555-5555-5555-5555-555555555555';
const A_NONE = '66666666-6666-6666-6666-666666666666';
const n = (v) => (v === null || v === undefined ? null : Number(v));

async function setup(db) {
  const q = async (sql, p) => (await db.query(sql, p)).rows;
  await db.exec(`
    insert into auth.users (id, email) values ('${ADMIN}', 'a@x.ly'),
      ('${A_SELL}', null), ('${A_BUY}', null), ('${A_BOTH}', null), ('${A_NONE}', null);
    insert into account_licenses (user_id, status, license_type) values ('${ADMIN}', 'active', 'lifetime')
      on conflict (user_id) do update set status = 'active';`);
  const c = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
  const x = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'بهاروز', 100000) returning id`, [c]))[0].id;
  const emp = async (name, phone, perms, anon) => {
    const id = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
      values ($1, $2, $3, 'x', $4::text[]) returning id`, [ADMIN, name, phone, perms]))[0].id;
    await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1, $2, $3)`, [id, anon, phone]);
    return id;
  };
  return { c, x, emp, q };
}

{
  console.log('— an employee who had "rate_edit" (0081) gets both new permissions');
  const db = await freshDb({ upTo: 82 });
  const { emp, q } = await setup(db);
  const old = await emp('قديم', '0910000000', ['transfers_create', 'rate_edit', 'buys_create'], A_SELL);
  const plain = await emp('بلا', '0920000000', ['transfers_create'], A_BUY);
  const fs = await import('node:fs');
  const sql = fs.readFileSync(new URL('../migrations/0083_rate_edit_per_kind.sql', import.meta.url), 'utf8');
  await db.exec('set search_path = public, extensions;\n' + sql);
  const p1 = (await q(`select permissions p from sub_users where id = $1`, [old]))[0].p;
  ok(!p1.includes('rate_edit') && p1.includes('rate_edit_sell') && p1.includes('rate_edit_buy') && p1.includes('transfers_create') && p1.includes('buys_create'),
    'rate_edit → rate_edit_sell + rate_edit_buy, the rest kept', JSON.stringify(p1));
  ok(JSON.stringify((await q(`select permissions p from sub_users where id = $1`, [plain]))[0].p) === '["transfers_create"]', 'nobody else is touched');
  await db.exec('set search_path = public, extensions;\n' + sql);
  const p2 = (await q(`select permissions p from sub_users where id = $1`, [old]))[0].p;
  ok(JSON.stringify(p2) === JSON.stringify(p1), 'running it again changes nothing', JSON.stringify(p2));
}

{
  console.log('— 0083 refuses to run before 0081');
  const db = await freshDb({ upTo: 80 });
  const fs = await import('node:fs');
  const sql = fs.readFileSync(new URL('../migrations/0083_rate_edit_per_kind.sql', import.meta.url), 'utf8');
  let msg = 'ran';
  try { await db.exec('set search_path = public, extensions;\n' + sql); } catch (e) { msg = e.message; }
  ok(msg.includes('0081'), 'refused', msg);
}

// the database as 0083 left it (0084 accepts the old key again, mapped: see cost84_test.mjs)
const db = await freshDb({ upTo: 83 });
const { c, x, emp, q } = await setup(db);
await emp('خروج فقط', '0911111111', ['transfers_create', 'buys_create', 'rate_edit_sell'], A_SELL);
await emp('دخول فقط', '0922222222', ['transfers_create', 'buys_create', 'rate_edit_buy'], A_BUY);
await emp('الاثنان', '0933333333', ['transfers_create', 'buys_create', 'rate_edit_sell', 'rate_edit_buy'], A_BOTH);
await emp('بلا', '0944444444', ['transfers_create', 'buys_create'], A_NONE);

const rates = (uid) => as(db, uid, (tx) => tx.query(`select current_exchange_rates() r`)).then((r) => r.rows[0].r);
const exit = (uid, usd, rate) => as(db, uid, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,'R',$4)`, [c, x, usd, rate])).then((r) => r.rows[0]);
const entry = (uid, usd, rate) => as(db, uid, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,null,null,$3,$4,null,'')`, [c, x, usd, rate])).then((r) => r.rows[0]);

console.log('— the keys the administrator may grant');
const keys = (await q(`select _employee_permission_keys() k`))[0].k;
ok(keys.includes('rate_edit_sell') && keys.includes('rate_edit_buy') && !keys.includes('rate_edit') && keys.includes('clients_add') && keys.length === 12,
  'twelve keys, rate_edit split in two', JSON.stringify(keys));
await as(db, ADMIN, (tx) => tx.query(
  `select admin_set_employee_permissions(id, array['transfers_create','rate_edit_sell']) from sub_users where employee_name = 'بلا'`));
ok((await q(`select permissions p from sub_users where employee_name = 'بلا'`))[0].p.includes('rate_edit_sell'), 'the administrator grants one');
await rejects(as(db, ADMIN, (tx) => tx.query(
  `select admin_set_employee_permissions(id, array['rate_edit']) from sub_users where employee_name = 'بلا'`)), 'invalid_permission', 'the old single key is no longer accepted');
await as(db, ADMIN, (tx) => tx.query(
  `select admin_set_employee_permissions(id, array['transfers_create','buys_create']) from sub_users where employee_name = 'بلا'`));

console.log('— the administrator sets the last rates');
await exit(ADMIN, 100, 7.25);
await entry(ADMIN, 100, 7.05);

console.log('— what each screen offers');
let r = await rates(ADMIN);
ok(r.can_edit_sell && r.can_edit_buy && r.can_edit, 'the administrator types both', JSON.stringify(r));
r = await rates(A_SELL);
ok(r.can_edit_sell === true && r.can_edit_buy === false && r.can_edit === false, 'exit only', JSON.stringify(r));
r = await rates(A_BUY);
ok(r.can_edit_sell === false && r.can_edit_buy === true && r.can_edit === false, 'entry only', JSON.stringify(r));
r = await rates(A_BOTH);
ok(r.can_edit_sell && r.can_edit_buy && r.can_edit, 'both', JSON.stringify(r));
r = await rates(A_NONE);
ok(!r.can_edit_sell && !r.can_edit_buy && !r.can_edit, 'none', JSON.stringify(r));

console.log('— the database applies the permission of the operation\'s own kind');
ok(n((await exit(A_SELL, 100, 7.4)).rate) === 7.4, 'exit only: types the sell rate');
ok(n((await entry(A_SELL, 100, 7.4)).rate) === 7.05, 'exit only: an entry is at the last buy rate');
ok(n((await exit(A_BUY, 100, 7.4)).rate) === 7.25, 'entry only: an exit is at the last sell rate');
ok(n((await entry(A_BUY, 100, 7.1)).rate) === 7.1, 'entry only: types the buy rate');
ok(n((await exit(A_BOTH, 100, 7.3)).rate) === 7.3 && n((await entry(A_BOTH, 100, 7.0)).rate) === 7.0, 'both: types both');
const none1 = await exit(A_NONE, 100, 9.9);
const none2 = await entry(A_NONE, 100, 1.5);
ok(n(none1.rate) === 7.25 && n(none2.rate) === 7.05, 'none: the administrator\'s last rates', JSON.stringify([none1.rate, none2.rate]));
ok(n(none1.lyd_amount) === 725 && n(none2.lyd_amount) === 705, 'and the dinars follow them');

console.log('— an employee never moves the administrator\'s last rates');
r = await rates(ADMIN);
ok(n(r.sell) === 7.25 && n(r.buy) === 7.05, 'still 7.25 / 7.05', JSON.stringify(r));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
