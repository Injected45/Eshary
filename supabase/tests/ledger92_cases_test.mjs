// The three valuation cases the review of 0092 found: after each, the
// ledger's dollars (1300) of the account must equal balance × cost.
import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
const near = (a, b, eps = 0.011) => Math.abs(Number(a) - Number(b)) <= eps;

const ADMIN = '11111111-1111-1111-1111-111111111111';
const db = await freshDb({ upTo: 92 }); // one cost per account: 0093 keeps one per book
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf')));
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'ش', 'R100') returning id`, [ADMIN]))[0].id;
const adm = (sql, p = []) => as(db, ADMIN, (tx) => tx.query(sql, p)).then((r) => r.rows);
const open = async (name, bal, cost) => (await adm(`select * from admin_open_account($1,$2,$3,null,null,$4)`, [c1, name, bal, cost]))[0].id;
const sell = (ex, usd, rate) => adm(`select * from record_transfer($1,$2,'م',null,null,$3,'',$4,'cash')`, [c1, ex, usd, rate]).then((r) => r[0]);
const buy = (ex, usd, rate) => adm(`select * from record_currency_buy($1,$2,null,null,$3,$4,null,'','cash')`, [c1, ex, usd, rate]).then((r) => r[0]);
const cancel = (kind, id) => adm(`select admin_cancel_operation($1,$2,'خطأ','pass-1234')`, [kind, id]);

async function check(ex, label) {
  const j = await q(`select account, sum(amount) s from _journal($1) where exchange_id = $2 group by account`, [ADMIN, ex]);
  const g = (a) => Number(j.find((x) => x.account === a)?.s ?? 0);
  const p = (await q(`select e.balance, c.cost_rate from exchanges e left join account_costs c on c.exchange_id = e.id where e.id = $1`, [ex]))[0];
  const book = Number(p.balance) * Number(p.cost_rate ?? 0);
  ok(near(g('1300'), book, 0.02), `${label}: ledger 1300 ${g('1300').toFixed(2)} = book ${book.toFixed(2)}`);
  ok(near(g('1390'), 0), `${label}: nothing left unvalued (${g('1390')})`);
  const all = await q(`select coalesce(sum(amount),0) s from _journal($1)`, [ADMIN]);
  ok(near(all[0].s, 0, 0.0001), `${label}: the journal balances`);
}

console.log('— 1) dollars without a cost, then the opening cost, then a cancel');
const U = await open('U', 0, null);
await adm(`select admin_adjust_balance($1, 500, 'رصيد قديم', 'pass-1234')`, [U]);
const ub = await buy(U, 100, 7.2);                       // no cost yet: unvalued 720
await adm(`select set_account_cost($1, 7)`, [U]);         // 600 × 7
await check(U, 'after the opening cost');
await cancel('buy', ub.id);                              // 100 out at 7
await check(U, 'after cancelling the old purchase');

console.log('— 2) a sale cancelled after the cost was corrected');
const A = await open('A', 1000, 7);
const s = await sell(A, 100, 7.5);
await adm(`select set_account_cost($1, 7.1)`, [A]);
await cancel('transfer', s.id);
await check(A, 'sale cancelled after a correction');

console.log('— 3) a commission cancelled after the cost moved');
const E = await open('E', 1000, 7);
await adm(`select record_account_expense($1, 50, null, 'عمولة')`, [E]);
await buy(E, 1000, 8);
const x = (await q(`select id from account_expenses where exchange_id = $1`, [E]))[0].id;
await adm(`select admin_cancel_expense($1, 'خطأ', 'pass-1234')`, [x]).catch(async (e) => {
  // the cancel's arguments differ by version: try the other form
  await adm(`select admin_cancel_expense($1, 'خطأ')`, [x]);
});
await check(E, 'commission cancelled after a purchase moved the cost');

console.log('— the trial balance never shows a missing side');
const tb = (await adm(`select ledger_trial_balance(now()) r`))[0].r;
ok(tb.every((r) => r.debit !== null && r.credit !== null && r.balance !== null), 'every account has both sides', JSON.stringify(tb.filter((r) => r.debit === null || r.credit === null)));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
