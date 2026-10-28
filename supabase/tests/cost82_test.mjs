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

// the database as 0082 left it (0083 later split rate_edit, see rate83_test.mjs)
const db = await freshDb({ upTo: 82 });
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
const acct = async (name, balance) => (await q(
  `insert into exchanges (company_id, name, balance) values ($1, $2, $3) returning id`, [c1, name, balance]))[0].id;
const A = await acct('بهاروز', 10000);
const B = await acct('الصحراء', 0);
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','rate_edit']) returning id`, [ADMIN]))[0];
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp.id, A_EMP]);

const n = (v) => (v === null || v === undefined ? null : Number(v));
const cost = async (ex) => n((await q(`select cost_rate from account_costs where exchange_id = $1`, [ex]))[0]?.cost_rate);
const bal = async (ex) => n((await q(`select balance from exchanges where id = $1`, [ex]))[0].balance);
const buy = (uid, ex, usd, rate, lyd = null) => as(db, uid, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,null,null,$3,$4,$5,'')`, [c1, ex, usd, rate, lyd])).then((r) => r.rows[0]);
const sell = (uid, ex, usd, rate) => as(db, uid, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,'R',$4)`, [c1, ex, usd, rate])).then((r) => r.rows[0]);
const setCost = (uid, ex, rate) => as(db, uid, (tx) => tx.query(`select set_account_cost($1,$2) r`, [ex, rate])).then((r) => r.rows[0].r);
const positions = (uid) => as(db, uid, (tx) => tx.query(`select * from treasury_positions()`)).then((r) => r.rows);
const cancel = (id) => as(db, ADMIN, (tx) => tx.query(`select admin_cancel_operation('buy', $1, 'خطأ', 'pass-1234')`, [id]));

console.log('— before an opening cost: an entry on a non-empty account is not costed');
const b0 = await buy(ADMIN, A, 100, 7.0);
ok(b0.cost_after === null && (await cost(A)) === null, 'no cost invented for dollars of unknown cost');
await q(`update exchanges set balance = 10000 where id = $1`, [A]); // back to the example

console.log('— the opening cost of the dollars the account holds now');
const o = await setCost(ADMIN, A, 7.10);
ok(n(o.balance) === 10000 && n(o.cost_rate) === 7.1, 'opening: $10,000 at 7.10', JSON.stringify(o));
let ev = await q(`select kind, balance_before::float b, cost_after::float c from account_cost_events where exchange_id = $1 order by created_at`, [A]);
ok(ev.length === 1 && ev[0].kind === 'opening' && ev[0].b === 10000 && ev[0].c === 7.1, 'kept in the record', JSON.stringify(ev));

console.log('— the example: buy $5,000 at 7.40');
const b1 = await buy(ADMIN, A, 5000, 7.40);
ok(n(b1.cost_before) === 7.1 && n(b1.cost_after) === 7.2, '(10,000×7.10 + 5,000×7.40) ÷ 15,000 = 7.2000', JSON.stringify([b1.cost_before, b1.cost_after]));
ok((await cost(A)) === 7.2 && (await bal(A)) === 15000, 'cost 7.2, balance 15,000');

console.log('— sell $3,000 at 7.35: the cost does not move');
const s1 = await sell(ADMIN, A, 3000, 7.35);
ok(n(s1.cost_rate) === 7.2, 'the exit keeps the cost at that moment (7.20)', String(s1.cost_rate));
ok((await cost(A)) === 7.2 && (await bal(A)) === 12000, 'still 7.20 on $12,000');

console.log('— a commission and a balance edited by hand: at cost');
await as(db, ADMIN, (tx) => tx.query(`select record_account_expense($1, 50, null, 'عمولة تحويل')`, [A]));
ok((await bal(A)) === 11950, 'the commission left the account', String(await bal(A)));
await q(`update exchanges set balance = balance + 50 where id = $1`, [A]); // edited by hand
ok((await cost(A)) === 7.2, 'unchanged');

console.log('— an uneven average is kept to 6 decimals');
const before = await bal(A);
const b2 = await buy(ADMIN, A, 333.33, 7.4567);
const expect = Math.round(((before * 7.2 + 333.33 * 7.4567) / (before + 333.33)) * 1e6) / 1e6;
ok(Math.abs(n(b2.cost_after) - expect) < 1e-9, `= ${expect}`, String(b2.cost_after));

console.log('— cancelling an entry takes its value out at its own price');
const cBefore = await cost(A);
const balBefore = await bal(A);
await cancel(b2.id);
const back = Math.round(((balBefore * cBefore - 333.33 * 7.4567) / (balBefore - 333.33)) * 1e6) / 1e6;
ok(Math.abs((await cost(A)) - back) < 1e-6, `back to ${back}`, String(await cost(A)));
ok(Math.abs((await cost(A)) - 7.2) < 0.00001, 'which is the 7.20 it was before that entry');
ev = await q(`select kind from account_cost_events where exchange_id = $1 order by created_at`, [A]);
ok(ev.map((e) => e.kind).join() === 'opening,buy,buy,buy_cancel', 'every change in the record', ev.map((e) => e.kind).join());

console.log('— the accounts are separate');
ok((await cost(B)) === null, 'the other account has no cost yet');
const bB = await buy(ADMIN, B, 1000, 6.95);
ok(n(bB.cost_after) === 6.95 && (await cost(B)) === 6.95, 'an empty account starts at the first buy rate');
ok(Math.abs((await cost(A)) - 7.2) < 0.00001, 'and the first account did not move');

console.log('— an employee entry averages the same way');
const bE = await buy(A_EMP, B, 1000, 7.05);
ok(n(bE.cost_after) === 7.0, '(1000×6.95 + 1000×7.05) ÷ 2000 = 7.00', String(bE.cost_after));

console.log('— an entry from an older build (no rate): in at cost');
const bOld = await buy(ADMIN, B, 500, 1, 500);
ok(bOld.rate === null && n(bOld.cost_after) === 7.0 && (await cost(B)) === 7.0, 'cost unchanged');

console.log('— an account emptied and bought again starts again');
await sell(ADMIN, B, await bal(B), 7.2);
ok((await bal(B)) === 0, 'emptied');
const bR = await buy(ADMIN, B, 200, 7.3);
ok(n(bR.cost_after) === 7.3, 'starts at 7.30');

console.log('— a correction is allowed and recorded');
const cr = await setCost(ADMIN, B, 7.25);
ok(n(cr.cost_rate) === 7.25, 'set to 7.25');
ev = await q(`select kind from account_cost_events where exchange_id = $1 order by created_at desc limit 1`, [B]);
ok(ev[0].kind === 'correction', 'recorded as a correction');

console.log('— the treasury, for the administrator only');
const pos = await positions(ADMIN);
const pA = pos.find((p) => p.exchange_id === A);
ok(pos.length === 2 && pA.account_name === 'بهاروز' && pA.company_name === 'الرحالة', 'both accounts with names');
ok(n(pA.book_value) === Math.round(n(pA.balance) * n(pA.cost_rate) * 100) / 100, 'book value = balance × cost', JSON.stringify(pA));
await rejects(positions(A_EMP), 'not_authorized', 'an employee cannot see the costs');
await rejects(setCost(A_EMP, A, 7), 'not_authorized', 'an employee cannot set a cost');
ok((await positions(OTHER)).length === 0, 'another administrator sees none of these');
await rejects(setCost(OTHER, A, 7), 'not_authorized', 'and cannot set them');
await rejects(setCost(ADMIN, A, 0), 'rate_invalid', 'a cost of 0 is refused');
const direct = await as(db, ADMIN, (tx) => tx.query(`select * from account_costs`)).catch(() => ({ rows: null }));
ok(direct.rows === null || direct.rows.length === 0, 'the table is not readable directly');
await rejects(as(db, ADMIN, (tx) => tx.query(`select * from _apply_buy_cost($1,$2,0,1,1,null)`, [ADMIN, A])), 'permission denied', 'the helper cannot be called by the app');

console.log('— running the file twice is harmless');
const fs = await import('node:fs');
const sql = fs.readFileSync(new URL('../migrations/0082_account_cost.sql', import.meta.url), 'utf8');
const costA = await cost(A);
await db.exec('set search_path = public, extensions;\n' + sql);
ok((await cost(A)) === costA, 'costs kept');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
