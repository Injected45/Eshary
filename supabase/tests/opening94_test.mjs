// 0094: the opening balances per book, the cancellations' shared password
// lock, a purchase retried after the rate changed, request ids on the dinar
// movements / book moves / commissions, the reference from its index, and
// the ledger's invariants after all of it.
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
const n = (v) => (v === null || v === undefined ? null : Number(v));
const near = (a, b, eps = 0.011) => Math.abs(Number(a) - Number(b)) <= eps;
const uuid = () => crypto.randomUUID();

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('${PW}', extensions.gen_salt('bf'))), ('${A_EMP}', null, null);
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const adm = (sql, p = []) => as(db, ADMIN, (tx) => tx.query(sql, p)).then((r) => r.rows);
const one = async (sql, p = []) => (await adm(sql, p))[0];
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','rate_edit_buy']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);
const books = async (ex) => {
  const o = {};
  for (const x of await q(`select book, balance, cost_rate from account_books where exchange_id = $1`, [ex])) {
    o[x.book] = { bal: n(x.balance), cost: n(x.cost_rate) };
  }
  return o;
};
const sell = (ex, usd, rate, o = {}) => as(db, o.uid ?? ADMIN, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,'',$4,$5,$6,null,null,false,$7)`,
  [c1, ex, usd, rate, o.book ?? 'cash', o.rid ?? null, o.book ?? 'cash'])).then((r) => r.rows[0]);
const buy = (ex, usd, rate, o = {}) => as(db, o.uid ?? ADMIN, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,null,null,$3,$4,null,'',$5,$6,null,$5)`,
  [c1, ex, usd, rate, o.book ?? 'cash', o.rid ?? null])).then((r) => r.rows[0]);

async function checkLedger(label) {
  const J = await q(`select * from _journal($1)`, [ADMIN]);
  const by = {}, at = {};
  for (const l of J) {
    const k = `${l.source}|${l.source_id}|${+new Date(l.at)}|${l.book}`;
    by[k] = (by[k] ?? 0) + Number(l.amount);
    if (l.account === '1300') at[`${l.exchange_id}|${l.book}`] = (at[`${l.exchange_id}|${l.book}`] ?? 0) + Number(l.amount);
  }
  const off = Object.entries(by).filter(([, v]) => Math.abs(v) > 0.0001);
  ok(off.length === 0, `${label}: every entry balanced in its book`, JSON.stringify(off.slice(0, 3)));
  for (const r of await q(`select * from account_books where owner_id = $1 and cost_rate is not null`, [ADMIN])) {
    ok(near(at[`${r.exchange_id}|${r.book}`] ?? 0, Number(r.balance) * Number(r.cost_rate), 0.05),
      `${label}: 1300 ${r.book} = ${r.balance} × ${r.cost_rate}`, `got ${at[`${r.exchange_id}|${r.book}`]}`);
  }
  const tb = (await one(`select ledger_trial_balance(now(), null, 1) r`)).r;
  const dr = tb.reduce((s, l) => s + Number(l.debit), 0), cr = tb.reduce((s, l) => s + Number(l.credit), 0);
  ok(near(dr, cr), `${label}: trial balance ${dr.toFixed(2)} = ${cr.toFixed(2)}`);
  const caps = tb.find((l) => l.account === '3100');
  return { J, capital: caps ? Number(caps.credit) - Number(caps.debit) : 0 };
}

// ---------------------------------------------------------------- 0094 runs
const SQL94 = fs.readFileSync(new URL('../migrations/0094_load_review_and_openings.sql', import.meta.url), 'utf8');
await db.exec('set search_path = public, extensions;\n' + SQL94);
ok(true, '0094 runs again');
{
  let msg = 'ran';
  try { await db.exec('set search_path = public, extensions;\n' + fs.readFileSync(new URL('../migrations/0093_cash_bank_books.sql', import.meta.url), 'utf8')); }
  catch (e) { msg = e.message; await db.exec('rollback'); }
  ok(msg.includes('لا تشغّله'), '0093 refuses to run after 0094', msg);
}

// ---------------------------------------------------------- 1) the openings
console.log('— opening balances');
const A = (await adm(`select * from admin_open_account($1,'أ',0,null,null,null)`, [c1]))[0].id;
await rejects(as(db, A_EMP, (tx) => tx.query(`select admin_set_opening($1,'cash',100,7)`, [A])), 'not_authorized', 'not by an employee');
await rejects(adm(`select admin_set_opening($1,'box',100,7)`, [A]), 'book_invalid', 'a book is cash or bank');
await rejects(adm(`select admin_set_opening($1,'cash',0,7)`, [A]), 'adjust_amount_invalid', 'more than zero');
await rejects(adm(`select admin_set_opening($1,'cash',100,0.9)`, [A]), 'rate_out_of_range', 'a sensible cost');
const capital0 = (await checkLedger('empty')).capital;
const o1 = (await one(`select admin_set_opening($1,'cash',1000,9.5) r`, [A])).r;
ok(o1.ok && n(o1.account_balance) === 1000, 'cash opening: 1,000 $ at 9.5', JSON.stringify(o1));
const o2 = (await one(`select admin_set_opening($1,'bank',500,10.2) r`, [A])).r;
ok(o2.ok && n(o2.account_balance) === 1500, 'bank opening: 500 $ at 10.2');
let bA = await books(A);
ok(bA.cash.bal === 1000 && bA.cash.cost === 9.5 && bA.bank.bal === 500 && bA.bank.cost === 10.2, 'each book holds its dollars at its cost', JSON.stringify(bA));
ok(n((await q(`select balance from exchanges where id = $1`, [A]))[0].balance) === 1500, 'the account = both books');
await rejects(adm(`select admin_set_opening($1,'cash',10,9.5)`, [A]), 'opening_already_set', 'once per book');
const adj = await q(`select kind, book, delta, reason from balance_adjustments where exchange_id = $1 order by created_at`, [A]);
ok(adj.length === 2 && adj.every((r) => r.kind === 'opening' && r.reason === 'رصيد أول المدة'), 'two opening lines in the statement', JSON.stringify(adj));
const L1 = await checkLedger('after the openings');
ok(near(L1.capital - capital0, 1000 * 9.5 + 500 * 10.2), `capital grew by 9,500 + 5,100 (${(L1.capital - capital0).toFixed(2)})`);

// a book that moved cannot be opened; a new account's unused book can
const B = (await adm(`select * from admin_open_account($1,'ب',300,null,null,7,'bank')`, [c1]))[0].id;
await rejects(adm(`select admin_set_opening($1,'bank',10,7)`, [B]), 'opening_already_set', 'the book of the account opening is taken');
await one(`select admin_set_opening($1,'cash',200,7.1) r`, [B]);
ok((await books(B)).cash.bal === 200, 'its other book takes an opening');
const C = (await adm(`select * from admin_open_account($1,'ج',0,null,null,null)`, [c1]))[0].id;
await one(`select admin_set_opening($1,'cash',100,7) r`, [C]);
await sell(C, 100, 7.5);   // the cash book sold out: balance 0, but it moved
await rejects(adm(`select admin_set_opening($1,'cash',50,7)`, [C]), 'opening_already_set', 'a book emptied by a sale is not "new"');
// an account from before 0093 holding dollars: split first
const D = (await adm(`select * from admin_open_account($1,'د',0,null,null,null)`, [c1]))[0].id;
await q(`alter table exchanges disable trigger user`);
await q(`update exchanges set books_split_at = null, balance = 80 where id = $1`, [D]);
await q(`update account_books set balance = 80 where exchange_id = $1 and book = 'bank'`, [D]);
await q(`alter table exchanges enable trigger user`);
await rejects(adm(`select admin_set_opening($1,'cash',50,7)`, [D]), 'books_not_split', 'old dollars are split first');
await checkLedger('after every opening');

// ------------------------------------------------- 2) the password lock
console.log('— cancellations: the shared password lock');
const s1 = await sell(A, 10, 9.8);
for (let i = 0; i < 5; i++) {
  const r = (await one(`select admin_cancel_operation('transfer',$1,'خطأ','wrong') r`, [s1.id])).r;
  ok(r.error === 'wrong_password', `wrong password ${i + 1}`);
}
ok((await one(`select admin_cancel_operation('transfer',$1,'خطأ',$2) r`, [s1.id, PW])).r.error === 'locked', 'locked after five, even with the right one');
ok((await one(`select admin_cancel_expense($1,'خطأ',$2) r`, [uuid(), PW])).r.error === 'locked', 'the commission cancel shares the lock');
await q(`delete from cancel_auth_failures`);
const c = (await one(`select admin_cancel_operation('transfer',$1,'خطأ',$2) r`, [s1.id, PW])).r;
ok(c.ok, 'the right password cancels', JSON.stringify(c));
ok((await books(A)).cash.bal === 1000, 'the dollars are back in the cash book');
// a paid sale cancelled while the dinar treasury is open
await adm(`select lyd_open(10000, 10000)`);
const s2 = await sell(A, 20, 9.9);
ok((await one(`select admin_cancel_operation('transfer',$1,'خطأ',$2) r`, [s2.id, PW])).r.ok, 'a paid sale cancels with the treasury open');

// ---------------------------------------- 4) a purchase retried after a rate change
console.log('— a purchase retried after the rate changed');
await buy(A, 1, 7.0);                                   // the administrator's buy_cash = 7
const rid = uuid();
const e1 = await buy(A, 10, 7.3, { uid: A_EMP, rid });
await buy(A, 1, 6.0);                                   // the administrator moves it to 6
const e2 = await buy(A, 10, 7.3, { uid: A_EMP, rid });  // 7.3 is now > 15 % away
ok(e2.id === e1.id, 'the retry returns the saved purchase instead of rate_unusual');
await rejects(buy(A, 10, 7.3, { uid: A_EMP, rid: uuid() }), 'rate_unusual', 'a NEW purchase at that rate is still refused');

// --------------------------------------------------------- 6) request ids
console.log('— request ids');
const r1 = uuid();
await adm(`select lyd_add_movement('in','cash',100,null,null,$1)`, [r1]);
const again = (await one(`select lyd_add_movement('in','cash',100,null,null,$1) r`, [r1])).r;
ok(again.repeat === true && n((await q(`select count(*) from lyd_movements where request_id = $1`, [r1]))[0].count) === 1, 'a dinar deposit sent twice is saved once');
await adm(`select lyd_add_movement('in','cash',100)`);   // an older build: no id
const r2 = uuid();
await adm(`select move_between_books($1,'bank',50,10.0,null,$2)`, [A, r2]);
await adm(`select move_between_books($1,'bank',50,10.0,null,$2)`, [A, r2]);
ok(n((await q(`select count(*) from book_transfers where request_id = $1`, [r2]))[0].count) === 1, 'a book move sent twice is saved once');
const r3 = uuid();
const x1 = (await adm(`select * from record_account_expense($1,5,null,'عمولة','cash',$2)`, [A, r3]))[0];
const x2 = (await adm(`select * from record_account_expense($1,5,null,'عمولة','cash',$2)`, [A, r3]))[0];
ok(x1.id === x2.id, 'a commission sent twice is taken once');
await adm(`select * from record_account_expense($1,5,null,'عمولة','cash')`, [A]);   // older build

// ------------------------------------------------------ 5) the references
console.log('— references from the index');
const refs = [];
for (let i = 0; i < 3; i++) refs.push((await sell(A, 1, 9.9)).reference);
ok(refs.every((r, i) => i === 0 || Number(r.slice(2)) === Number(refs[i - 1].slice(2)) + 1), 'consecutive', refs.join(','));
await q(`update companies set start_ref = 'Rh9998' where id = $1`, [c1]);
const big = [];
for (let i = 0; i < 3; i++) big.push((await sell(A, 1, 9.9)).reference);
ok(Number(big[0].slice(2)) > Number(refs[2].slice(2)), 'never back', big.join(','));
const plan = (await q(`explain select (substring(reference from '[0-9]{1,30}$'))::numeric from transfers
  where owner_id = $1 and cancelled_at is null and reference ~ '^[^0-9]*[0-9]{1,30}$'
    and substring(reference from '^[^0-9]*') = 'Rh'
  order by (substring(reference from '[0-9]{1,30}$'))::numeric desc limit 1`, [ADMIN])).map((r) => r['QUERY PLAN']).join('\n');
await q(`set enable_seqscan = off`);
const plan2 = (await q(`explain select (substring(reference from '[0-9]{1,30}$'))::numeric from transfers
  where owner_id = $1 and cancelled_at is null and reference ~ '^[^0-9]*[0-9]{1,30}$'
    and substring(reference from '^[^0-9]*') = 'Rh'
  order by (substring(reference from '[0-9]{1,30}$'))::numeric desc limit 1`, [ADMIN])).map((r) => r['QUERY PLAN']).join('\n');
await q(`set enable_seqscan = on`);
ok(plan2.includes('transfers_owner_refnum_idx'), 'the index answers the highest number', plan + '\n' + plan2);

// ---------------------------------- 8) one credit limit over both books
console.log('— one credit limit over both books');
const K = (await q(`insert into clients (owner_id, name) values ($1, 'كريم') returning id`, [ADMIN]))[0].id;
await adm(`select set_customer_credit_limit($1, 1000)`, [K]);
await sell(A, 1, 9.9, { book: 'bank' });   // the administrator's bank sell rate
await one(`select admin_set_opening($1,'bank',500,9.8) r`, [C]);
const credit = (ex, usd, book, uid = A_EMP) => as(db, uid, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,'',$6,$4,null,$5,0,false,$4)`,
  [c1, ex, usd, book, K, uid === ADMIN ? 9.9 : null])).then((r) => r.rows[0]);
await credit(A, 60, 'cash');                // ≈ 594 owed in the cash book
await rejects(credit(C, 50, 'bank'), 'credit_limit_exceeded', 'the bank book cannot add another 495 on top (≈ 1,089 > 1,000)');
await credit(C, 30, 'bank');                // ≈ 297: ≈ 891 in all, under 1,000
const kb = (await one(`select customer_balances() r`)).r.find((x) => x.client_id === K);
ok(Number(kb.balance) <= 1000 && Number(kb.balance_cash) > 0 && Number(kb.balance_bank) > 0,
  'both books together stay under the one limit', JSON.stringify(kb));
await rejects(credit(A, 20, 'cash', ADMIN), 'credit_limit_exceeded', 'the administrator is asked too (over the total)');

await checkLedger('at the end');
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
