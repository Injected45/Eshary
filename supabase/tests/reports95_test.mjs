// 0095: the reports. Every figure is checked against another source: the
// profit against profit_report, the dinars against lyd_summary, the dollars
// against the books, the debts against customer_balances, plus the oldest-
// debts-first ageing.
import { freshDb, as } from './harness.mjs';
import fs from 'node:fs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}
const ADMIN = '11111111-1111-1111-1111-111111111111';
const A_EMP = '33333333-3333-3333-3333-333333333333';
const PW = 'pass-1234';
const near = (a, b, eps = 0.011) => Math.abs(Number(a) - Number(b)) <= eps;

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('${PW}', extensions.gen_salt('bf'))), ('${A_EMP}', null, null);
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';`);
const SQL95 = fs.readFileSync(new URL('../migrations/0095_reports.sql', import.meta.url), 'utf8');
await db.exec('set search_path = public, extensions;\n' + SQL95);
ok(true, '0095 runs again');

const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const adm = (sql, p = []) => as(db, ADMIN, (tx) => tx.query(sql, p)).then((r) => r.rows);
const one = async (sql, p = []) => (await adm(sql, p))[0];
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'سالم', '0911111111', 'x', array['transfers_create','buys_create']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);
const K = (await q(`insert into clients (owner_id, name) values ($1, 'كريم') returning id`, [ADMIN]))[0].id;
const M = (await q(`insert into clients (owner_id, name) values ($1, 'منير') returning id`, [ADMIN]))[0].id;
await adm(`select set_customer_credit_limit($1, 100000)`, [K]);
await adm(`select set_customer_credit_limit($1, 10)`, [M]);

const report = async (from, to) => (await one(`select report_period($1, $2) r`, [from, to])).r;
const book = (r, b) => r.books.find((x) => x.book === b);

// --------------------------------------------------- before any operation
const A = (await adm(`select * from admin_open_account($1,'أ',0,null,null,null)`, [c1]))[0].id;
await adm(`select admin_set_opening($1,'cash',1000,9.5)`, [A]);
await adm(`select admin_set_opening($1,'bank',2000,10)`, [A]);
await adm(`select lyd_open(5000, 20000)`);
let r = await report(new Date(Date.now() - 3600000).toISOString(), new Date(Date.now() + 60000).toISOString());
ok(book(r, 'cash').usd_end === 1000 && book(r, 'bank').usd_end === 2000, 'the openings are the balances at the end', JSON.stringify(r.books));
ok(book(r, 'cash').usd_start === 0 && book(r, 'bank').usd_start === 0, 'nothing before them');
ok(r.lyd.open && near(r.lyd.cash_end, 5000) && near(r.lyd.bank_end, 20000), 'the dinars of the opening', JSON.stringify(r.lyd));
ok(book(r, 'cash').sale_n === 0 && r.by_day.length === 0, 'no operations yet');

// ----------------------------------------------------------- operations
const sell = (usd, rate, b, o = {}) => as(db, o.uid ?? ADMIN, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,'',$4,$5,null,$6,$7,false,$5)`,
  [c1, A, usd, rate, b, o.customer ?? null, o.paid ?? null])).then((x) => x.rows[0]);
const buy = (usd, rate, b, o = {}) => as(db, o.uid ?? ADMIN, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,null,null,$3,$4,null,'',$5,null,null,$5)`,
  [c1, A, usd, rate, b])).then((x) => x.rows[0]);
const pause = () => new Promise((res) => setTimeout(res, 30));   // the test clock is coarse
await pause();
const t0 = (await q(`select clock_timestamp() t`))[0].t.toISOString();
await pause();
await sell(100, 9.8, 'cash');                       // profit 100 × (9.8 − 9.5) = 30
await sell(200, 10.4, 'bank');                      // profit 200 × 0.4 = 80
await buy(300, 9.6, 'cash');                        // cash cost (1000−100)×9.5 + 300×9.6 …
await sell(50, 9.8, 'cash', { uid: A_EMP });        // the employee, at the administrator's 9.8
await sell(20, 9.8, 'cash', { customer: K, paid: 0 });   // 196 on credit
const sx = await sell(10, 9.8, 'cash');
ok((await one(`select admin_cancel_operation('transfer',$1,'خطأ',$2) r`, [sx.id, PW])).r.ok, 'one sale cancelled');
await adm(`select customer_add_entry($1,'collect',96,'cash')`, [K]);   // K owes 100
const t1 = new Date(Date.now() + 60000).toISOString();
r = await report(t0, t1);

const pr = await adm(`select * from profit_report($1, $2)`, [t0, t1]);
const prSum = (b, f) => pr.filter((x) => x.book === b).reduce((s, x) => s + Number(x[f]), 0);
for (const b of ['cash', 'bank']) {
  ok(near(book(r, b).profit, prSum(b, 'profit_lyd')), `${b}: the profit = profit_report (${book(r, b).profit})`);
  ok(near(book(r, b).priced_usd, prSum(b, 'sold_usd')), `${b}: the sold dollars = profit_report`);
  ok(near(book(r, b).buy_usd, prSum(b, 'bought_usd')), `${b}: the bought dollars = profit_report`);
}
ok(book(r, 'cash').sale_n === 3 && near(book(r, 'cash').sale_usd, 170), 'cash: 3 sales (the cancelled one out), 170 $', JSON.stringify(book(r, 'cash')));
ok(book(r, 'bank').sale_n === 1 && near(book(r, 'bank').profit, 80), 'bank: one sale, 80 profit');
const ab = Object.fromEntries((await q(`select book, balance from account_books where exchange_id = $1`, [A])).map((x) => [x.book, Number(x.balance)]));
ok(near(book(r, 'cash').usd_end, ab.cash) && near(book(r, 'bank').usd_end, ab.bank), 'the dollars at the end = the books now', JSON.stringify(ab));
ok(near(book(r, 'cash').usd_start, 1000) && near(book(r, 'bank').usd_start, 2000), 'the dollars at the start = the openings',
  JSON.stringify(r.books.map((x) => [x.book, x.usd_start, x.usd_end])));
ok(near(book(r, 'cash').usd_end - book(r, 'cash').usd_start, book(r, 'cash').buy_usd - book(r, 'cash').sale_usd),
  'cash: end − start = bought − sold', JSON.stringify(book(r, 'cash')));
const ls = (await one(`select lyd_summary('2000-01-01','2100-01-01') s`)).s;
ok(near(r.lyd.cash_end, ls.cash) && near(r.lyd.bank_end, ls.bank), 'the dinars at the end = the dinar treasury', `${r.lyd.cash_end}/${ls.cash} ${r.lyd.bank_end}/${ls.bank}`);
ok(near(r.lyd.cash_start, 5000) && near(r.lyd.bank_start, 20000), 'the dinars at the start = the opening');
ok(near(r.credit.given, 196) && near(r.credit.collected, 96), 'credit given 196, collected 96', JSON.stringify(r.credit));
ok(near(r.credit_end.owed_to_us, 100), 'customers owe 100 at the end');
ok(r.cancels.n === 1 && near(r.cancels.sale_usd, 10), 'one cancellation of 10 $');
ok(r.by_day.length === 1 && r.by_day[0].sale_n === 4 && r.by_day[0].buy_n === 1, 'one day: 4 sales, 1 purchase', JSON.stringify(r.by_day));
const eA = r.by_employee.find((x) => x.employee_id === null);
const eS = r.by_employee.find((x) => x.employee_id === emp);
ok(eA && eA.name === 'المدير' && eA.sale_n === 3 && eA.buy_n === 1 && eA.cancelled_n === 1 && near(eA.credit_given, 196),
  'the administrator: 3 sales, 1 purchase, 1 cancelled, 196 on credit', JSON.stringify(eA));
ok(eS && eS.name === 'سالم' && eS.sale_n === 1 && near(eS.sale_usd, 50), 'the employee: 1 sale of 50 $', JSON.stringify(eS));
ok(near(r.by_employee.reduce((s, x) => s + Number(x.profit), 0), book(r, 'cash').profit + book(r, 'bank').profit),
  'the employees\' profit adds up to the total');
ok(r.by_account.length === 2 && r.by_account.every((x) => x.account === 'أ'), 'one account, two books', JSON.stringify(r.by_account.map((x) => x.book)));
// the next period sees this one as its previous
const later = await report(t1, new Date(Date.parse(t1) + (Date.parse(t1) - Date.parse(t0))).toISOString());
ok(later.previous.sale_n === 4 && near(later.previous.profit, book(r, 'cash').profit + book(r, 'bank').profit),
  'the previous period of the next one is this one', JSON.stringify(later.previous));

await rejects(as(db, A_EMP, (tx) => tx.query(`select report_period(now() - interval '1 day', now())`)), 'not_authorized', 'not for an employee');
await rejects(adm(`select report_period(now(), now() - interval '1 day')`), 'period_invalid', 'a period ends after it starts');
await rejects(adm(`select report_period(now() - interval '2 years', now())`), 'period_too_long', 'at most 400 days');

// ------------------------------------------------- the ageing of the debts
console.log('— debt ageing');
// K: a debt 40 days old (300), one today (196 earlier), collected 96 → owes 100
await q(`insert into customer_lyd_entries (owner_id, client_id, kind, amount, book, created_at)
         values ($1, $2, 'opening', 300, 'cash', now() - interval '40 days')`, [ADMIN, K]);
await adm(`select customer_add_entry($1,'collect',300,'cash')`, [K]);   // pays the oldest first
// M: 50 owed for 100 days, over his limit of 10
await q(`insert into customer_lyd_entries (owner_id, client_id, kind, amount, book, created_at)
         values ($1, $2, 'opening', 50, 'bank', now() - interval '100 days')`, [ADMIN, M]);
// a seller we owe
const S = (await q(`insert into clients (owner_id, name) values ($1, 'بائع') returning id`, [ADMIN]))[0].id;
await adm(`select customer_add_entry($1,'opening',-70,null,'قديم',null,'cash')`, [S]);
const ag = (await one(`select report_debt_aging() r`)).r;
const k = ag.debtors.find((x) => x.client_id === K);
const m = ag.debtors.find((x) => x.client_id === M);
const bal = (await one(`select customer_balances() r`)).r;
ok(k && near(k.owed, bal.find((x) => x.client_id === K).balance), 'K: owed = customer_balances', JSON.stringify(k));
ok(k && near(k.owed, 100) && near(k.d7, 100) && near(k.d30 + k.d90 + k.older, 0), 'K: the old debt was paid first, 100 of this week remain', JSON.stringify(k));
ok(m && near(m.older, 50) && m.over_limit === true, 'M: 50 older than 90 days, over his limit', JSON.stringify(m));
ok(ag.debtors[0].client_id === M, 'the oldest debts come first');
ok(ag.creditors.length === 1 && near(ag.creditors[0].owed, 70), 'we owe the seller 70', JSON.stringify(ag.creditors));
await rejects(as(db, A_EMP, (tx) => tx.query(`select report_debt_aging()`)), 'not_authorized', 'ageing: not for an employee');

// WRITE_FIXTURES=1: what the database really sends, for the app's tests
// (test/fixtures), so the screens read exactly these keys
if (process.env.WRITE_FIXTURES) {
  const dir = new URL('../../test/fixtures/', import.meta.url);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(new URL('report_period.json', dir), JSON.stringify(r, null, 1));
  fs.writeFileSync(new URL('debt_aging.json', dir), JSON.stringify(ag, null, 1));
  console.log('fixtures written');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
