import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const ADMIN = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const A_EMP = '33333333-3333-3333-3333-333333333333';
const n = (v) => (v === null || v === undefined ? null : Number(v));

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf'))),
    ('${OTHER}', 'o@x.ly', 'x'), ('${A_EMP}', null, null);
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';
`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const A = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'بهاروز', 10000) returning id`, [c1]))[0].id;
const B = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'الصحراء', 1000) returning id`, [c1]))[0].id;
const empId = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','rate_edit_sell','rate_edit_buy']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [empId, A_EMP]);

const buy = (uid, ex, usd, rate) => as(db, uid, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,null,null,$3,$4,null,'')`, [c1, ex, usd, rate])).then((r) => r.rows[0]);
const sell = (uid, ex, usd, rate) => as(db, uid, (tx) => tx.query(
  rate === undefined
    ? `select * from record_transfer($1,$2,'م',null,null,$3,'R')`
    : `select * from record_transfer($1,$2,'م',null,null,$3,'R',$4)`,
  rate === undefined ? [c1, ex, usd] : [c1, ex, usd, rate])).then((r) => r.rows[0]);
const costOf = async (id) => n((await q(`select cost_after from operation_costs where operation_id = $1`, [id]))[0]?.cost_after);
const report = (uid, from = '2000-01-01T00:00:00Z', to = '2100-01-01T00:00:00Z') =>
  as(db, uid, (tx) => tx.query(`select * from profit_report($1,$2)`, [from, to])).then((r) => r.rows);
const positions = (uid) => as(db, uid, (tx) => tx.query(`select * from treasury_positions()`)).then((r) => r.rows);
const history = (uid, ex) => as(db, uid, (tx) => tx.query(`select * from account_cost_history($1)`, [ex])).then((r) => r.rows);

console.log('— an exit before the account has a cost is counted apart');
await sell(ADMIN, A, 100, 7.3);
let rows = await report(ADMIN);
let rA = rows.find((r) => r.exchange_id === A);
ok(rA.exits_unpriced === 1 && n(rA.unpriced_usd) === 100 && n(rA.sold_usd) === 0, 'not priced, not guessed', JSON.stringify(rA));

console.log('— the worked example: $10,000 at 7.10, buy $5,000 at 7.40, sell $3,000 at 7.35');
await as(db, ADMIN, (tx) => tx.query(`select set_account_cost($1, 7.10)`, [A]));
await q(`update exchanges set balance = 10000 where id = $1`, [A]); // the opening
await as(db, ADMIN, (tx) => tx.query(`select set_account_cost($1, 7.10)`, [A]));
await buy(ADMIN, A, 5000, 7.40);
const s1 = await sell(ADMIN, A, 3000, 7.35);
ok((await costOf(s1.id)) === 7.2, 'sold at cost 7.20');
rows = await report(ADMIN);
rA = rows.find((r) => r.exchange_id === A);
ok(n(rA.sold_usd) === 3000 && n(rA.sales_lyd) === 22050 && n(rA.cost_lyd) === 21600, 'sales 22,050 − cost 21,600', JSON.stringify(rA));
ok(n(rA.profit_lyd) === 450, 'profit 450 = 3,000 × (7.35 − 7.20)', String(rA.profit_lyd));
ok(n(rA.bought_usd) === 5000 && n(rA.bought_lyd) === 37000 && rA.entries_priced === 1, 'bought $5,000 for 37,000');

console.log('— a sale below cost is a loss');
const s2 = await sell(ADMIN, A, 1000, 7.0);
rows = await report(ADMIN);
rA = rows.find((r) => r.exchange_id === A);
ok(n(rA.profit_lyd) === 450 - 200, '−200 = 1,000 × (7.00 − 7.20): total 250', String(rA.profit_lyd));

console.log('— a cancelled exit leaves the profit');
await as(db, ADMIN, (tx) => tx.query(`select admin_cancel_operation('transfer', $1, 'خطأ', 'pass-1234')`, [s2.id]));
rows = await report(ADMIN);
rA = rows.find((r) => r.exchange_id === A);
ok(n(rA.profit_lyd) === 450 && n(rA.sold_usd) === 3000, 'back to 450');

console.log('— an employee\'s exits count too, at their own rate');
await sell(A_EMP, A, 1000, 7.4);
rows = await report(ADMIN);
rA = rows.find((r) => r.exchange_id === A);
ok(n(rA.profit_lyd) === 450 + 200, '+200 = 1,000 × (7.40 − 7.20)', String(rA.profit_lyd));

console.log('— an uneven cost is rounded per exit, to the dirham');
await buy(ADMIN, A, 333.33, 7.4567);
const cost = n((await positions(ADMIN)).find((p) => p.exchange_id === A).cost_rate);
const s3 = await sell(ADMIN, A, 777.77, 7.5);
const expectCost = Math.round(777.77 * cost * 100) / 100;
rows = await report(ADMIN);
rA = rows.find((r) => r.exchange_id === A);
ok(Math.abs(n(rA.cost_lyd) - (21600 + 7200 + expectCost)) < 0.001, `cost of goods = rounded per exit (${expectCost})`, String(rA.cost_lyd));
ok((await costOf(s3.id)) === cost, 'the exit kept the cost at that moment');

console.log('— the period is respected');
rows = await report(ADMIN, '2000-01-01T00:00:00Z', '2000-01-02T00:00:00Z');
ok(rows.length === 0, 'nothing in an empty period');
await rejects(report(ADMIN, '2100-01-01T00:00:00Z', '2000-01-01T00:00:00Z'), 'period_invalid', 'a reversed period is refused');

console.log('— an account with only entries still shows');
await buy(ADMIN, B, 500, 7.0);
rows = await report(ADMIN);
const rB = rows.find((r) => r.exchange_id === B);
ok(rB && n(rB.bought_usd) === 500 && n(rB.sold_usd) === 0, 'listed with its purchase', JSON.stringify(rB));

console.log('— the treasury revalues at the last sell rate');
const pos = await positions(ADMIN);
const pA = pos.find((p) => p.exchange_id === A);
ok(n(pA.market_rate) === 7.5, 'the market rate is the administrator\'s last sell rate', String(pA.market_rate));
ok(n(pA.unrealized) === Math.round(n(pA.balance) * (7.5 - n(pA.cost_rate)) * 100) / 100, 'unrealized = balance × (market − cost)', JSON.stringify(pA));
const pB = pos.find((p) => p.exchange_id === B);
ok(pB.cost_rate === null && pB.unrealized === null, 'an account without a cost has none (balance 1,000 bought into: not costed)', JSON.stringify(pB));

console.log('— the cost history');
const h = await history(ADMIN, A);
ok(h.length >= 4 && h[0].kind === 'buy' && h.some((e) => e.kind === 'opening'), 'newest first, with the opening', h.map((e) => e.kind).join());

console.log('— for the administrator only');
await rejects(report(A_EMP), 'not_authorized', 'an employee cannot see the profit');
await rejects(positions(A_EMP), 'not_authorized', 'nor the treasury');
await rejects(history(A_EMP, A), 'not_authorized', 'nor the history');
ok((await report(OTHER)).length === 0, 'another administrator sees none of it');
ok((await history(OTHER, A)).length === 0, 'nor this account\'s history');

console.log('— running the file twice is harmless; it refuses before 0082');
const fs = await import('node:fs');
const sql = fs.readFileSync(new URL('../migrations/0085_profit_and_loss.sql', import.meta.url), 'utf8');
await db.exec('set search_path = public, extensions;\n' + sql);
ok((await report(ADMIN)).length === 2, 'still works');
const old = await freshDb({ upTo: 83 });
let msg = 'ran';
try { await old.exec('set search_path = public, extensions;\n' + sql); } catch (e) { msg = e.message; }
ok(msg.includes('0084'), 'refused before 0084', msg);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
