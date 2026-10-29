// 0093: the cash and bank books. Built on a database at 0092 with history
// (and a backup and a period close made then), 0093 applied on top, then
// every rule of the books, the old builds' calls, the restores, the wipe and
// the ledger's invariants per book.
import { freshDb, as } from './harness.mjs';
import fs from 'node:fs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const ADMIN = '11111111-1111-1111-1111-111111111111';
const PLATFORM = '22222222-2222-2222-2222-222222222222';
const A_EMP = '33333333-3333-3333-3333-333333333333';
const PW = 'pass-1234';
const n = (v) => (v === null || v === undefined ? null : Number(v));
const near = (a, b, eps = 0.011) => Math.abs(Number(a) - Number(b)) <= eps;
const r6 = (x) => Math.round(x * 1e6) / 1e6;

const db = await freshDb({ upTo: 92 });
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('${PW}', extensions.gen_salt('bf'))),
    ('${PLATFORM}', 'p@x.ly', 'x'), ('${A_EMP}', null, null);
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';
  insert into account_licenses (user_id, status, license_type, is_admin) values
    ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const adm = (sql, p = []) => as(db, ADMIN, (tx) => tx.query(sql, p)).then((r) => r.rows);
const one = async (sql, p = []) => (await adm(sql, p))[0];
const C = (await q(`insert into clients (owner_id, name) values ($1, 'محمد') returning id`, [ADMIN]))[0].id;
const S = (await q(`insert into clients (owner_id, name) values ($1, 'بائع') returning id`, [ADMIN]))[0].id;
const K = (await q(`insert into clients (owner_id, name) values ($1, 'كريم') returning id`, [ADMIN]))[0].id;
const M = (await q(`insert into clients (owner_id, name) values ($1, 'منير') returning id`, [ADMIN]))[0].id;
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);
const perms = (p) => q(`update sub_users set permissions = $1 where id = $2`, [p, emp]);

// ============================================================ before 0093
console.log('— history made at 0092');
const A = (await adm(`select * from admin_open_account($1,'بهاروز',1000,null,null,7)`, [c1]))[0].id;
await adm(`select set_customer_credit_limit($1, 5000)`, [C]);
await adm(`select lyd_open(5000, 20000)`);
const sell92 = (ex, usd, rate, o = {}) => adm(`select * from record_transfer($1,$2,'م',null,null,$3,'',$4,$5,null,$6,$7,false)`,
  [c1, ex, usd, rate, o.method ?? 'cash', o.customer ?? null, o.paid ?? null]).then((r) => r[0]);
const buy92 = (ex, usd, rate, o = {}) => adm(`select * from record_currency_buy($1,$2,$3,null,$4,$5,null,'',$6,null,$7)`,
  [c1, ex, o.client ?? null, usd, rate, o.method ?? 'cash', o.paid ?? null]).then((r) => r[0]);
await sell92(A, 100, 7.5, { method: 'cash' });               // box +750
await buy92(A, 200, 7.2, { method: 'bank' });                // bank −1,440
await sell92(A, 50, 7.4, { customer: C, paid: 0 });          // C owes 370
await adm(`select customer_add_entry($1,'collect',100,'cash')`, [C]);   // C owes 270
await adm(`select lyd_add_movement('cash_to_bank', null, 500)`);
await adm(`select set_customer_credit_limit($1, 5000)`, [M]);
const E = (await adm(`select * from admin_open_account($1,'هـ',500,null,null,7)`, [c1]))[0].id;
await sell92(E, 100, 7.4, { method: 'cash', customer: M, paid: 300 });   // M owes 440: a cash sale
await adm(`select customer_add_entry($1,'collect',100,'cash')`, [M]);     // M owes 340
const costA92 = n((await q(`select cost_rate from account_costs where exchange_id = $1`, [A]))[0].cost_rate);
// an hour back, so a close covers it
for (const t of ['transfers', 'currency_buys', 'account_cost_events', 'operation_costs', 'customer_lyd_entries',
                 'lyd_movements', 'balance_adjustments']) {
  await q(`update ${t} set created_at = created_at - interval '1 hour' where owner_id = $1`, [ADMIN]);
}
await q(`update lyd_treasury set started_at = started_at - interval '1 hour' where owner_id = $1`, [ADMIN]);
const close92 = await one(`select close_period(now() - interval '50 minutes', 'قبل الدفترين') r`);
ok(close92.r.ok, 'a close made at 0092');
const OLDB = (await q(`select _save_backup('manual') id`))[0].id;

// ============================================================ 0093 applied
const SQL93 = fs.readFileSync(new URL('../migrations/0093_cash_bank_books.sql', import.meta.url), 'utf8');
await db.exec('set search_path = public, extensions;\n' + SQL93);
await db.exec('set search_path = public, extensions;\n' + SQL93);   // twice: harmless
ok(true, '0093 runs, and runs again');
for (const f of ['0086_adjustments_and_dinar_treasury.sql', '0090_sell_buy_wording.sql', '0091_customer_credit.sql', '0092_general_ledger.sql']) {
  let msg = 'ran';
  try { await db.exec('set search_path = public, extensions;\n' + fs.readFileSync(new URL('../migrations/' + f, import.meta.url), 'utf8')); }
  catch (e) { msg = e.message; await db.exec('rollback'); }
  ok(msg.includes('لا تشغّله'), `${f.slice(0, 4)} refuses to run after 0093`, msg);
}

// ------------------------------------------------------------- helpers
const books = async (ex) => {
  const o = {};
  for (const x of await q(`select book, balance, cost_rate from account_books where exchange_id = $1`, [ex])) {
    o[x.book] = { bal: n(x.balance), cost: n(x.cost_rate) };
  }
  return o;
};
const total = async (ex) => n((await q(`select balance from exchanges where id = $1`, [ex]))[0].balance);
async function booksInStep(label) {
  const bad = await q(`select e.id, e.balance, coalesce(sum(b.balance), 0) s, count(b.*)::int k
                         from exchanges e left join account_books b on b.exchange_id = e.id
                        group by e.id, e.balance having e.balance <> coalesce(sum(b.balance), 0) or count(b.*) <> 2`);
  ok(bad.length === 0, `${label}: cash + bank = the account, two books each`, JSON.stringify(bad));
}
const sell = (ex, usd, rate, o = {}) => as(db, o.uid ?? ADMIN, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,'',$4,$5,null,$6,$7,$8,$9)`,
  [c1, ex, usd, rate, o.method ?? null, o.customer ?? null, o.paid ?? null, o.over ?? false, o.book ?? null])).then((r) => r.rows[0]);
const buy = (ex, usd, rate, o = {}) => as(db, o.uid ?? ADMIN, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,$3,null,$4,$5,null,'',$6,null,$7,$8)`,
  [c1, ex, o.client ?? null, usd, rate, o.method ?? null, o.paid ?? null, o.book ?? null])).then((r) => r.rows[0]);
const cancel = (kind, id) => adm(`select admin_cancel_operation($1,$2,'خطأ',$3) r`, [kind, id, PW]).then((r) => r[0].r);
const summary = async () => (await one(`select lyd_summary('2000-01-01','2100-01-01') s`)).s;
const custs = async () => (await one(`select customer_balances() r`)).r;
const cust = async (id) => (await custs()).find((x) => x.client_id === id);

async function checkLedger(label) {
  const J = await q(`select * from _journal($1)`, [ADMIN]);
  const key = (l) => `${l.source}|${l.source_id}|${new Date(l.at).getTime()}`;
  const bySrc = {}, bySrcBook = {};
  for (const l of J) {
    bySrc[key(l)] = (bySrc[key(l)] ?? 0) + Number(l.amount);
    bySrcBook[key(l) + '|' + l.book] = (bySrcBook[key(l) + '|' + l.book] ?? 0) + Number(l.amount);
  }
  const off = Object.entries(bySrc).filter(([, v]) => Math.abs(v) > 0.0001);
  ok(off.length === 0, `${label}: every source sums to zero`, JSON.stringify(off.slice(0, 3)));
  const offB = Object.entries(bySrcBook).filter(([, v]) => Math.abs(v) > 0.0001);
  ok(offB.length === 0, `${label}: … and to zero in each book`, JSON.stringify(offB.slice(0, 3)));
  ok(J.every((l) => l.book === 'cash' || l.book === 'bank'), `${label}: every line has a book`);
  ok(J.filter((l) => l.account === '1100').every((l) => l.book === 'cash')
     && J.filter((l) => l.account === '1110').every((l) => l.book === 'bank'), `${label}: the box is the cash book's, the bank the bank book's`);
  const sum = (f) => J.filter(f).reduce((s, l) => s + Number(l.amount), 0);
  const s = await summary();
  if (s.open) {
    ok(near(sum((l) => l.account === '1100'), s.cash), `${label}: 1100 ${sum((l) => l.account === '1100').toFixed(2)} = box ${s.cash}`);
    ok(near(sum((l) => l.account === '1110'), s.bank), `${label}: 1110 ${sum((l) => l.account === '1110').toFixed(2)} = bank ${s.bank}`);
  }
  for (const c of await custs()) {
    for (const b of ['cash', 'bank']) {
      ok(near(sum((l) => l.account === '1200' && l.client_id === c.client_id && l.book === b), c[`balance_${b}`]),
        `${label}: 1200 of ${c.name} in ${b} = ${c[`balance_${b}`]}`);
    }
  }
  for (const r of await q(`select b.* from account_books b where b.owner_id = $1`, [ADMIN])) {
    if (r.cost_rate === null) continue;
    const want = Number(r.balance) * Number(r.cost_rate);
    const got = sum((l) => l.account === '1300' && l.exchange_id === r.exchange_id && l.book === r.book);
    ok(near(got, want, 0.02), `${label}: 1300 ${r.book} ${got.toFixed(2)} = ${r.balance} × ${r.cost_rate}`);
    ok(near(sum((l) => l.account === '1390' && l.exchange_id === r.exchange_id && l.book === r.book), 0),
      `${label}: nothing unvalued in ${r.book}`);
  }
  return J;
}

// ============================================================ the migration
console.log('— existing balances go into the bank book');
let bA = await books(A);
ok(bA.bank.bal === 1050 && near(bA.bank.cost, costA92, 0.000001) && bA.cash.bal === 0 && bA.cash.cost === null,
  'A: 1,050 at its cost in the bank book, the cash book empty', JSON.stringify(bA));
ok((await one(`select account_books_list() r`)).r[0].split === false, 'not split yet');
const rates = (await q(`select kind, rate from last_exchange_rates where owner_id = $1 order by kind`, [ADMIN]))
  .reduce((o, r) => ({ ...o, [r.kind]: n(r.rate) }), {});
ok(rates.sell_cash === 7.4 && rates.sell_bank === 7.4 && rates.buy_cash === 7.2 && rates.buy_bank === 7.2
   && rates.sell === undefined, 'the last rates go to both books', JSON.stringify(rates));
const cC = await cust(C);
ok(n(cC.balance_bank) === 370 && n(cC.balance_cash) === -100 && n(cC.balance) === 270, 'a debt on credit stays in the bank book, a collection into the box in the cash book', JSON.stringify(cC));
let cM = await cust(M);
ok(n(cM.balance_cash) === 340 && n(cM.balance_bank) === 0, 'a debt from a cash sale is in the cash book', JSON.stringify(cM));
await adm(`select customer_add_entry($1,'collect',340,'cash')`, [M]);
cM = await cust(M);
ok(n(cM.balance_cash) === 0 && n(cM.balance_bank) === 0, 'collected into the box: nothing left in either book', JSON.stringify(cM));
ok((await one(`select ledger_closes() r`)).r[0].intact === true, 'the close made before 0093 is still intact');
await booksInStep('after the migration');
await checkLedger('after the migration');

// ============================================================ the split
console.log('— the split, once');
await rejects(as(db, A_EMP, (tx) => tx.query(`select set_account_books($1, 300, 6.9, 7.1)`, [A])), 'not_authorized', 'not by an employee');
await rejects(adm(`select set_account_books($1, 2000, 6.9, 7.1)`, [A]), 'books_split_invalid', 'not more than the account holds');
await rejects(adm(`select set_account_books($1, 300, null, 7.1)`, [A]), 'opening_cost_required', 'a cost for every book with dollars');
await rejects(adm(`select set_account_books($1, 300, 0.5, 7.1)`, [A]), 'rate_out_of_range', 'a sensible cost');
const split = await one(`select set_account_books($1, 300, 6.9, 7.1) r`, [A]);
ok(split.r.ok, 'split');
bA = await books(A);
ok(bA.cash.bal === 300 && bA.cash.cost === 6.9 && bA.bank.bal === 750 && bA.bank.cost === 7.1, '300 cash at 6.9, 750 bank at 7.1', JSON.stringify(bA));
const ev = await q(`select book, kind from account_cost_events where exchange_id = $1 and created_at > now() - interval '1 minute' order by book`, [A]);
ok(ev.length === 2 && ev.every((e) => e.kind === 'opening'), 'an opening per book', JSON.stringify(ev));
await rejects(adm(`select set_account_books($1, 0, null, 7.1)`, [A]), 'books_already_split', 'only once');
await rejects(adm(`update exchanges set books_split_at = null where id = $1`, [A]), 'balance_direct_edit', 'the split is not undone from the app');
await buy(E, 10, 7.0, { book: 'cash' });
await rejects(adm(`select set_account_books($1, 0, null, 7)`, [E]), 'books_split_invalid', 'a cash book already used is not overwritten');
ok((await books(E)).cash.bal === 10, 'its purchase kept');
await booksInStep('after the split');

// ============================================================ saves per book
console.log('— saves go into their book; costs average per book');
const bc1 = await buy(A, 100, 7.0, { book: 'cash' });
ok(bc1.book === 'cash' && bc1.lyd_method === 'cash', 'a cash purchase is paid from the box');
bA = await books(A);
ok(near(bA.cash.cost, r6((300 * 6.9 + 100 * 7.0) / 400), 0.000001) && bA.bank.cost === 7.1, 'the cash cost moved, the bank cost did not', JSON.stringify(bA));
await buy(A, 250, 7.3, { book: 'bank' });
bA = await books(A);
ok(near(bA.bank.cost, r6((750 * 7.1 + 250 * 7.3) / 1000), 0.000001) && bA.bank.bal === 1000, 'the bank cost moved', JSON.stringify(bA));
const sc1 = await sell(A, 50, 7.2, { book: 'cash' });
const oc1 = (await q(`select cost_before, book from operation_costs where operation_id = $1`, [sc1.id]))[0];
ok(near(oc1.cost_before, bA.cash.cost, 0.000001) && oc1.book === 'cash', 'the sale left at the cash book\'s cost');
const sc2 = await sell(A, 10, 7.2, { book: 'cash', method: 'bank' });
ok(sc2.book === 'cash' && sc2.lyd_method === 'cash', 'the pocket is always the book\'s');
const sb1 = await sell(A, 100, 7.4, { book: 'bank' });
ok(sb1.lyd_method === 'bank' && sb1.book === 'bank', 'a bank sale is paid through the bank');
bA = await books(A);
ok(bA.cash.bal === 340 && bA.bank.bal === 900 && (await total(A)) === 1240, 'cash 340 + bank 900 = 1,240', JSON.stringify(bA));
await rejects(sell(A, 1, 7.2, { book: 'gold' }), 'book_invalid', 'a book is cash or bank');
await booksInStep('after the saves');

console.log('— a cash sale is refused when only bank dollars exist');
const B = (await adm(`select * from admin_open_account($1,'أنزار',1000,null,null,7,'bank')`, [c1]))[0].id;
let bB = await books(B);
ok(bB.bank.bal === 1000 && bB.bank.cost === 7 && bB.cash.bal === 0, 'B opened in the bank book');
ok((await one(`select account_books_list() r`)).r.find((x) => x.exchange_id === B).split === true, 'born split');
await rejects(sell(B, 10, 7.2, { book: 'cash' }), 'book_insufficient', 'cash sale with only bank dollars');
await rejects(sell(B, 10, 7.2, { method: 'cash' }), 'book_insufficient', 'an older build paid in cash: the cash book');
await rejects(sell(B, 5000, 7.2, { book: 'bank' }), 'insufficient_balance', 'more than the account: as before');
const Cc = (await adm(`select * from admin_open_account($1,'صندوق',500,null,null,6.8,'cash')`, [c1]))[0].id;
const bCc = await books(Cc);
ok(bCc.cash.bal === 500 && bCc.cash.cost === 6.8 && bCc.bank.bal === 0, 'an account opened in the cash book');

// ============================================================ moves
console.log('— moving dollars between the books');
await rejects(as(db, A_EMP, (tx) => tx.query(`select move_between_books($1,'bank',10,7.1)`, [B])), 'not_authorized', 'not by an employee');
await rejects(adm(`select move_between_books($1,'cash',10,7.1)`, [B]), 'book_insufficient', 'not more than the book holds');
await rejects(adm(`select move_between_books($1,'bank',10,0.7)`, [B]), 'rate_out_of_range', 'a sensible price');
const mv = (await one(`select move_between_books($1,'bank',400,7.1,'نقل') r`, [B])).r;
ok(n(mv.from_balance) === 600 && n(mv.to_balance) === 400 && n(mv.to_cost) === 7.1, 'bank 600, cash 400 at 7.1', JSON.stringify(mv));
const mv2 = (await one(`select move_between_books($1,'bank',100,7.3) r`, [B])).r;
ok(near(mv2.to_cost, r6((400 * 7.1 + 100 * 7.3) / 500), 0.000001), 'averaged into the cash cost', JSON.stringify(mv2));
bB = await books(B);
ok(bB.bank.bal === 500 && bB.bank.cost === 7 && bB.cash.bal === 500 && (await total(B)) === 1000, 'the account did not change, the bank cost neither', JSON.stringify(bB));
await sell(B, 10, 7.5, { book: 'cash' });
ok((await books(B)).cash.bal === 490, 'now the cash sale goes through');
ok((await q(`select count(*)::int k from book_transfers where exchange_id = $1`, [B]))[0].k === 2, 'both moves kept');
await booksInStep('after the moves');

// ============================================================ cancels
console.log('— cancels restore the right book and cost');
let before = await books(A);
await cancel('buy', bc1.id);                             // 100 cash at 7.0 out
let after = await books(A);
ok(after.cash.bal === before.cash.bal - 100 && after.bank.bal === before.bank.bal, 'the purchase left the cash book only');
ok(near(after.cash.cost, r6((before.cash.bal * before.cash.cost - 100 * 7.0) / (before.cash.bal - 100)), 0.000001),
  'at its own price', JSON.stringify([before.cash, after.cash]));
ok(after.bank.cost === before.bank.cost, 'the bank cost untouched');
await buy(A, 100, 7.6, { book: 'bank' });
before = await books(A);
await cancel('transfer', sb1.id);                        // 100 bank back at their cost
after = await books(A);
const exitCost = n((await q(`select cost_after from operation_costs where operation_id = $1`, [sb1.id]))[0].cost_after);
ok(after.bank.bal === before.bank.bal + 100 && after.cash.bal === before.cash.bal, 'the sale came back into the bank book');
ok(near(after.bank.cost, r6((before.bank.bal * before.bank.cost + 100 * exitCost) / (before.bank.bal + 100)), 0.000001),
  'at the cost it left at', JSON.stringify([before.bank, after.bank, exitCost]));
await cancel('transfer', sc2.id);                        // a cash sale back
ok((await books(A)).cash.bal === after.cash.bal + 10, 'a cash sale back into the cash book');
const bb2 = await buy(B, 50, 7.0, { book: 'cash' });     // cash 540
await adm(`select move_between_books($1,'cash',540,7.0)`, [B]);
await rejects(cancel('buy', bb2.id), 'cancel_insufficient_balance', 'a purchase whose book no longer holds it is not cancelled');
await booksInStep('after the cancels');

// ============================================================ adjustments and commissions
console.log('— adjustments and commissions per book');
before = await books(A);
const tA = await total(A);
const adj = (await one(`select admin_adjust_balance($1,$2,'جرد الصندوق',$3,'cash') r`, [A, before.cash.bal + 5, PW])).r;
ok(adj.ok && adj.book === 'cash' && n(adj.balance_after) === before.cash.bal + 5, 'the cash book +5', JSON.stringify(adj));
after = await books(A);
ok(after.cash.cost === before.cash.cost && (await total(A)) === tA + 5 && after.bank.bal === before.bank.bal, 'the cost kept, the account +5');
ok((await q(`select book, delta from balance_adjustments where exchange_id = $1 and kind = 'adjust'`, [A]))[0].book === 'cash', 'the line knows its book');
await rejects(adm(`select admin_adjust_balance($1, 1, 'تسوية', $2)`, [A, PW]), 'book_required', 'both books hold dollars: the book is required');
const D = (await adm(`select * from admin_open_account($1,'د',500,null,null,7)`, [c1]))[0].id;
const adjOld = (await one(`select admin_adjust_balance(p_exchange_id => $1, p_new_balance => 450, p_reason => 'قديم', p_password => $2) r`, [D, PW])).r;
ok(adjOld.ok && (await books(D)).bank.bal === 450, 'an older build: the book that holds everything');
before = await books(A);
const x1 = (await one(`select * from record_account_expense($1, 5, null, 'عمولة', 'bank')`, [A]));
ok(x1.book === 'bank' && (await books(A)).bank.bal === before.bank.bal - 5, 'a commission from the bank book');
await adm(`select admin_cancel_expense($1, 'خطأ', $2)`, [x1.id, PW]);
ok((await books(A)).bank.bal === before.bank.bal, 'cancelled: back into the bank book');
await adm(`select * from record_account_expense($1, 2, null, 'عمولة', 'cash')`, [A]);
await rejects(adm(`select * from record_account_expense($1, 5, null, 'عمولة')`, [A]), 'book_required', 'a commission names its book');
await rejects(adm(`select * from record_account_expense($1, $2, null, 'عمولة', 'cash')`, [A, (await books(A)).cash.bal + 1]), 'book_insufficient', 'not more than the book');
const xOld = await one(`select * from record_account_expense($1, 3, null, 'عمولة')`, [D]);
ok(xOld.book === 'bank', 'an older build\'s commission');
await booksInStep('after adjustments and commissions');

// ============================================================ credit
console.log('— customers per book');
await adm(`select set_customer_credit_limit($1, 1000)`, [K]);
await sell(A, 100, 7.0, { book: 'cash', customer: K, paid: 0 });
await sell(A, 100, 7.1, { book: 'bank', customer: K, paid: 0 });
let k = await cust(K);
ok(n(k.balance_cash) === 700 && n(k.balance_bank) === 710 && n(k.balance) === 1410, 'two books, each within the limit', JSON.stringify(k));
await rejects(sell(A, 50, 7.1, { uid: A_EMP, book: 'bank', customer: K, paid: 0 }), 'credit_limit_exceeded', 'the limit applies to each book');
const boxBefore = n((await summary()).cash);
const col = (await one(`select customer_add_entry($1,'collect',200,'cash') r`, [K])).r;
ok(col.book === 'cash' && n(col.balance_cash) === 500 && n(col.balance_bank) === 710, 'collected into the box: the cash book', JSON.stringify(col));
ok(n((await summary()).cash) === boxBefore + 200, 'the box +200');
await buy(A, 100, 7.0, { book: 'bank', client: S, paid: 0 });
await adm(`select customer_add_entry($1,'pay',300,'bank')`, [S]);
ok(n((await cust(S)).balance_bank) === -400, 'we owe the seller 400 bank dinars');
await adm(`select customer_add_entry($1,'opening',50,null,'قديم',null,'cash')`, [K]);
k = await cust(K);
ok(n(k.balance_cash) === 550, 'an opening in the cash book');
await adm(`select customer_add_entry($1,'opening',10,null,'قديم')`, [S]);
ok(n((await cust(S)).balance_bank) === -390, 'an older build\'s opening: the bank book');
const stC = (await one(`select customer_statement($1,'2000-01-01','2100-01-01','cash') r`, [K])).r;
ok(n(stC.closing) === 550 && stC.entries.every((e) => e.book === 'cash') && stC.entries.length === 3, 'the cash statement', JSON.stringify(stC));
const stAll = (await one(`select customer_statement($1,'2000-01-01','2100-01-01') r`, [K])).r;
ok(n(stAll.closing) === 1260 && stAll.entries.length === 4, 'both books (an older build)');

// ============================================================ dinar conversion
console.log('— converting dinars has two amounts');
let s0 = await summary();
await adm(`select lyd_add_movement('bank_to_cash', null, 1000, 'تسييل صك', 990)`);
let s1 = await summary();
ok(near(s1.bank, n(s0.bank) - 1000) && near(s1.cash, n(s0.cash) + 990), 'bank −1,000, box +990');
ok(near(s1.flows.conversion_result, 10), 'the conversion cost 10', JSON.stringify(s1.flows));
ok(s1.movements.find((m) => m.kind === 'bank_to_cash' && n(m.amount_in) === 990), 'the movement keeps both amounts');
await adm(`select lyd_add_movement('cash_to_bank', null, 100, null)`);
s0 = s1; s1 = await summary();
ok(near(s1.bank, n(s0.bank) + 100) && near(s1.cash, n(s0.cash) - 100), 'an older build\'s conversion: the same amount');
await rejects(adm(`select lyd_add_movement('in','cash',100,null,90)`), 'lyd_amount_invalid', 'a deposit has one amount');
const isBank = (await one(`select ledger_income_statement('2000-01-01', now(), 'bank') r`)).r;
ok(near(isBank.lines.find((l) => l.account === '4400')?.amount, -10), 'the bank book shows the conversion loss', JSON.stringify(isBank.lines));

// ============================================================ rates and employees
console.log('— four last rates, the employee rules');
let cr = (await one(`select current_exchange_rates() r`)).r;
ok(n(cr.sell_cash) === 7.0 && n(cr.sell_bank) === 7.1 && n(cr.buy_cash) === 7.0 && n(cr.buy_bank) === 7.0
   && n(cr.sell) === n(cr.sell_cash) && n(cr.buy) === n(cr.buy_cash), 'sell_cash / sell_bank / buy_cash / buy_bank; sell = sell_cash', JSON.stringify(cr));
const e1 = await sell(A, 1, 9.0, { uid: A_EMP, book: 'bank' });
ok(n(e1.rate) === 7.1, 'an employee without the permission: the bank sell rate');
const e2 = await sell(A, 1, 9.0, { uid: A_EMP, book: 'cash' });
ok(n(e2.rate) === 7.0, '… and the cash sell rate in the cash book');
const e3 = await buy(A, 1, 9.0, { uid: A_EMP, book: 'cash' });
ok(n(e3.rate) === 7.0, '… and the cash buy rate');
await perms(['transfers_create', 'buys_create', 'rate_edit_sell']);
await rejects(sell(A, 1, 8.5, { uid: A_EMP, book: 'bank' }), 'rate_unusual', 'with the permission: not 15 % away from the bank rate');
const e4 = await sell(A, 1, 7.15, { uid: A_EMP, book: 'bank' });
ok(n(e4.rate) === 7.15, 'near it: his rate');
cr = (await one(`select current_exchange_rates() r`)).r;
ok(n(cr.sell_bank) === 7.1, 'an employee\'s rate is not the administrator\'s last');
const empRates = (await as(db, A_EMP, (tx) => tx.query(`select current_exchange_rates() r`))).rows[0].r;
ok(empRates.can_edit_sell === true && empRates.can_edit_buy === false && n(empRates.sell_bank) === 7.1, 'what the employee sees', JSON.stringify(empRates));

// ============================================================ older builds
console.log('— calls of an older build');
const o1 = (await adm(`select * from record_transfer(p_company_id => $1, p_exchange_id => $2, p_beneficiary_name => 'م',
  p_beneficiary_account_company => null, p_beneficiary_code => null, p_amount => 5, p_reference => '', p_rate => 7.2,
  p_lyd_method => 'bank', p_request_id => null, p_customer_id => null, p_lyd_paid => null, p_over_limit => false)`, [c1, A]))[0];
ok(o1.book === 'bank' && o1.lyd_method === 'bank', 'named, paid by bank: the bank book');
const o2 = (await adm(`select * from record_transfer($1,$2,'م',null,null,5,'',7.2)`, [c1, A]))[0];
ok(o2.book === 'bank' && o2.lyd_method === 'bank', 'nothing said: the bank book');
const o3 = (await adm(`select * from record_currency_buy($1,$2,null,null,5,7.0,null,'','cash',null,null)`, [c1, A]))[0];
ok(o3.book === 'cash', 'a purchase paid in cash: the cash book');
const o4 = (await adm(`select * from record_transfer($1,$2,'م',null,null,5,'',null)`, [c1, A]))[0];
ok(o4.book === 'bank' && o4.rate === null && o4.lyd_method === null, 'without a rate: the bank book, at cost');
ok((await adm(`select ledger_trial_balance(now()) r`))[0].r.length > 0, 'ledger_trial_balance(p_to)');
ok((await adm(`select ledger_income_statement('2000-01-01', now()) r`))[0].r.lines, 'ledger_income_statement(from, to)');
ok((await adm(`select ledger_balance_sheet(now()) r`))[0].r.balances, 'ledger_balance_sheet(at)');
ok((await adm(`select ledger_journal('2000-01-01', now()) r`))[0].r.total > 0, 'ledger_journal(from, to)');
ok((await adm(`select * from account_cost_history($1)`, [A])).length > 0, 'account_cost_history(account)');
ok((await adm(`select * from treasury_positions()`)).find((p) => p.exchange_id === A).cost_rate !== null, 'treasury_positions(): both books together');
const sc = (await one(`select set_account_cost($1, 7.05) r`, [D])).r;
ok(sc.book === 'bank' && n((await books(D)).bank.cost) === 7.05, 'set_account_cost(account, rate): the book that holds everything');
await rejects(adm(`select set_account_cost($1, 7.05)`, [A]), 'book_required', '… both hold: the book is required');
const pr = await adm(`select * from profit_report('2000-01-01', now())`);
ok(pr.some((r) => r.book === 'cash') && pr.some((r) => r.book === 'bank') && pr.every((r) => r.book), 'the profit report per book');
await booksInStep('after the older builds');

// ============================================================ the ledger per book
console.log('— the ledger, per book and combined');
let J = await checkLedger('after everything');
for (const b of ['cash', 'bank']) {
  const tb = (await one(`select ledger_trial_balance(now(), $1) r`, [b])).r;
  ok(near(tb.reduce((s, r) => s + n(r.debit), 0), tb.reduce((s, r) => s + n(r.credit), 0), 0.001), `the ${b} trial balance balances`);
  ok(!tb.some((r) => r.account === (b === 'cash' ? '1110' : '1100')), `the ${b} book has only its own pocket`);
}
const F = 0.98;
const tbF = (await one(`select ledger_trial_balance(now(), null, $1) r`, [F])).r;
ok(near(tbF.reduce((s, r) => s + n(r.debit), 0), tbF.reduce((s, r) => s + n(r.credit), 0), 0.02), 'combined at 0.98: debits = credits');
let factorOk = true;
for (const r of tbF) {
  const want = J.filter((l) => l.account === r.account).reduce((s, l) => s + Number(l.amount) * (l.book === 'bank' ? F : 1), 0);
  if (!near(n(r.balance), want, 0.02)) { factorOk = false; console.log('  ', r.account, r.balance, want); }
}
ok(factorOk, 'combined = cash lines + bank lines × factor, account by account');
const isC = (await one(`select ledger_income_statement('2000-01-01', now(), 'cash') r`)).r;
const isB = (await one(`select ledger_income_statement('2000-01-01', now(), 'bank') r`)).r;
const isF = (await one(`select ledger_income_statement('2000-01-01', now(), null, $1) r`, [F])).r;
ok(near(n(isF.net), n(isC.net) + F * n(isB.net), 0.02), `net combined ${isF.net} = cash ${isC.net} + ${F} × bank ${isB.net}`);
ok(isC.lines.some((l) => l.account === '4100') && isB.lines.some((l) => l.account === '4500'), 'sales in the cash book, the move result in the bank book');
for (const [b, f] of [['cash', 1], ['bank', 1], [null, F]]) {
  const bs = (await one(`select ledger_balance_sheet(now(), $1, $2) r`, [b, f])).r;
  const x = bs.balances;
  const assets = ['1100', '1110', '1200', '1300', '1390'].reduce((s, a) => s + n(x[a] ?? 0), 0);
  const equity = ['3100', '3150', '3200', '3300'].reduce((s, a) => s - n(x[a] ?? 0), 0) - n(x.profit ?? 0);
  ok(near(assets, equity, 0.05), `balance sheet ${b ?? 'combined'}: assets ${assets.toFixed(2)} = equity ${equity.toFixed(2)}`);
  if (b) ok(bs.inventory.every((i) => i.book === b && near(i.book_value, i.ledger_value, 0.02)), `${b}: each book's dollars = its ledger value`, JSON.stringify(bs.inventory));
}
const jr = (await one(`select ledger_journal('2000-01-01', now(), 'cash') r`)).r;
ok(jr.lines.every((l) => l.book === 'cash'), 'the cash journal');
await rejects(adm(`select ledger_trial_balance(now(), null, 0)`), 'factor_invalid', 'a factor above zero');
await rejects(adm(`select ledger_trial_balance(now(), 'gold')`), 'book_invalid', 'a book is cash or bank');
await rejects(as(db, A_EMP, (tx) => tx.query(`select ledger_trial_balance(now(), 'cash')`)), 'not_authorized', 'not for an employee');
await rejects(as(db, A_EMP, (tx) => tx.query(`select account_books_list()`)), 'not_authorized', 'the books are not for an employee');
ok((await as(db, A_EMP, (tx) => tx.query(`select count(*)::int k from account_books`))).rows[0].k === 0, 'an employee reads no book');
const cl = (await one(`select close_period(now() - interval '6 minutes') r`)).r;
ok(cl.ok, 'a close after 0093');
const closes = (await one(`select ledger_closes() r`)).r;
ok(closes.length === 2 && closes.every((c) => c.intact === true), 'both closes intact', JSON.stringify(closes));
await booksInStep('after the close');

// ============================================================ backups
console.log('— backups and restores');
const bkNow = (await q(`select _save_backup('manual') id`))[0].id;
const snapA = await books(A), snapB = await books(B);
ok((await q(`select jsonb_array_length(data->'tables'->'account_books') k from backups where id = $1`, [bkNow]))[0].k > 0, 'the books are in the backup');
await adm(`select move_between_books($1,'bank',50,7.2)`, [A]);
await sell(A, 3, 7.0, { book: 'cash' });
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [bkNow, ADMIN]));
ok(JSON.stringify(await books(A)) === JSON.stringify(snapA) && JSON.stringify(await books(B)) === JSON.stringify(snapB), 'restored: the books as they were');
ok((await q(`select count(*)::int k from book_transfers where owner_id = $1`, [ADMIN]))[0].k === 3, 'the moves as they were');
await booksInStep('after a restore');
await checkLedger('after a restore');

// a backup as an older database made it: no book anywhere, one rate per kind
const stripped = (await q(`select data from backups where id = $1`, [bkNow]))[0].data;
for (const t of ['transfers', 'currency_buys', 'account_expenses', 'balance_adjustments', 'customer_lyd_entries', 'account_cost_events', 'operation_costs']) {
  stripped.tables[t] = stripped.tables[t].map(({ book, ...r }) => r);
}
stripped.tables.exchanges = stripped.tables.exchanges.map(({ books_split_at, ...r }) => r);
stripped.tables.lyd_movements = stripped.tables.lyd_movements.map(({ amount_in, ...r }) => r);
stripped.tables.last_exchange_rates = stripped.tables.last_exchange_rates
  .filter((r) => r.kind.endsWith('_cash')).map((r) => ({ ...r, kind: r.kind.replace('_cash', '') }));
delete stripped.tables.account_books;
delete stripped.tables.book_transfers;
const bkOld = (await q(`insert into backups (kind, data, size_bytes) select 'manual', $1::jsonb, 1 returning id`, [JSON.stringify(stripped)]))[0].id;
const cnt = (await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2) r`, [bkOld, ADMIN]))).rows[0].r;
ok(cnt.account_books_from_balances > 0, 'the books made from the balances', JSON.stringify(cnt));
const bA2 = await books(A);
ok(bA2.cash.bal === 0 && bA2.bank.bal === await total(A), 'all of A in the bank book', JSON.stringify(bA2));
ok((await one(`select account_books_list() r`)).r.every((x) => x.split === false), 'not split');
const rates2 = (await q(`select kind from last_exchange_rates where owner_id = $1 order by kind`, [ADMIN])).map((r) => r.kind);
ok(rates2.join() === 'buy_bank,buy_cash,sell_bank,sell_cash', 'the rates for both books', rates2.join());
await booksInStep('after an older backup');

console.log('— the real backup made at 0092');
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [OLDB, ADMIN]));
bA = await books(A);
ok(bA.bank.bal === 1050 && near(bA.bank.cost, costA92, 0.000001) && bA.cash.bal === 0, 'A: 1,050 in the bank book at its old cost', JSON.stringify(bA));
ok(n((await cust(C)).balance_bank) === 370 && n((await cust(C)).balance_cash) === -100, 'C: 370 bank, −100 cash, as after the migration');
ok(n((await cust(M)).balance_cash) === 340, 'M: 340 in the cash book');
ok((await one(`select ledger_closes() r`)).r.every((c) => c.intact), 'its close intact');
await booksInStep('after the 0092 backup');
await checkLedger('after the 0092 backup');
const oldData = (await q(`select data from backups where id = $1`, [OLDB]))[0].data;
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_backup($1)`, [oldData]));
ok((await books(A)).bank.bal === 1050, 'the full restore takes it too');
await booksInStep('after a full restore');
await adm(`select set_account_books($1, 50, 6.95, 7.05)`, [A]);
ok((await books(A)).cash.bal === 50, 'and it can be split then');
await checkLedger('after splitting a restored account');

// ============================================================ the wipe
console.log('— the wipe');
await adm(`select move_between_books($1,'bank',10,7.0)`, [A]);
const w = (await one(`select owner_wipe_operations($1) r`, [PW])).r;
ok(w.ok, 'wiped');
const left = await q(`select count(*) filter (where balance <> 0 or cost_rate is not null)::int k from account_books where owner_id = $1`, [ADMIN]);
ok(left[0].k === 0, 'every book empty, no cost');
ok((await q(`select count(*)::int k from book_transfers where owner_id = $1`, [ADMIN]))[0].k === 0, 'the moves gone');
await booksInStep('after the wipe');
const J2 = await q(`select coalesce(sum(amount), 0) s from _journal($1)`, [ADMIN]);
ok(near(J2[0].s, 0, 0.0001), 'the journal still balances');
await sell(A, 1, 7, { book: 'cash' }).catch((e) => ok(e.message.includes('insufficient_balance'), 'an empty account sells nothing', e.message));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
