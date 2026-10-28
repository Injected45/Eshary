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
const OTHER = '44444444-4444-4444-4444-444444444444';
const n = (v) => (v === null || v === undefined ? null : Number(v));

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf'))),
    ('${PLATFORM}', 'p@x.ly', 'x'), ('${A_EMP}', null, null),
    ('${OTHER}', 'o@x.ly', extensions.crypt('other-1234', extensions.gen_salt('bf')));
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';
  insert into account_licenses (user_id, status, license_type, is_admin) values
    ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const A = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'بهاروز', 10000) returning id`, [c1]))[0].id;
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','rate_edit_sell','rate_edit_buy','accounts_all']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);

const bal = async () => n((await q(`select balance from exchanges where id = $1`, [A]))[0].balance);
const adjust = (uid, newBal, reason = 'مطابقة كشف بهاروز', pw = 'pass-1234') => as(db, uid, (tx) => tx.query(
  `select admin_adjust_balance($1,$2,$3,$4) r`, [A, newBal, reason, pw])).then((r) => r.rows[0].r);
const sell = (uid, usd, rate, method) => as(db, uid, (tx) => tx.query(
  method === undefined
    ? `select * from record_transfer($1,$2,'م',null,null,$3,'R',$4)`
    : `select * from record_transfer($1,$2,'م',null,null,$3,'R',$4,$5)`,
  method === undefined ? [c1, A, usd, rate] : [c1, A, usd, rate, method])).then((r) => r.rows[0]);
const buy = (uid, usd, rate, method) => as(db, uid, (tx) => tx.query(
  method === undefined
    ? `select * from record_currency_buy($1,$2,null,null,$3,$4,null,'')`
    : `select * from record_currency_buy($1,$2,null,null,$3,$4,null,'',$5)`,
  method === undefined ? [c1, A, usd, rate] : [c1, A, usd, rate, method])).then((r) => r.rows[0]);
const summary = (uid, from = '2000-01-01T00:00:00Z', to = '2100-01-01T00:00:00Z') =>
  as(db, uid, (tx) => tx.query(`select lyd_summary($1,$2) s`, [from, to])).then((r) => r.rows[0].s);
const move = (kind, pocket, amount, note = null) => as(db, ADMIN, (tx) => tx.query(
  `select lyd_add_movement($1,$2,$3,$4) r`, [kind, pocket, amount, note])).then((r) => r.rows[0].r);
const count = (counted, post = true, note = 'جرد المساء') => as(db, ADMIN, (tx) => tx.query(
  `select lyd_record_count($1,$2,$3) r`, [counted, note, post])).then((r) => r.rows[0].r);

console.log('— A) a balance no longer changes by hand');
await rejects(as(db, ADMIN, (tx) => tx.query(`update exchanges set balance = 99999 where id = $1`, [A])), 'balance_direct_edit', 'the administrator\'s direct update is refused');
ok((await bal()) === 10000, 'unchanged');
await as(db, ADMIN, (tx) => tx.query(`update exchanges set our_code = 'X-1' where id = $1`, [A]));
ok((await q(`select our_code from exchanges where id = $1`, [A]))[0].our_code === 'X-1', 'other fields still edit');
await as(db, ADMIN, (tx) => tx.query(`update exchanges set our_code = 'X-2', balance = 10000 where id = $1`, [A]));
ok((await q(`select our_code from exchanges where id = $1`, [A]))[0].our_code === 'X-2', 'sending the same balance back is harmless');

console.log('— A) the documented adjustment');
await as(db, ADMIN, (tx) => tx.query(`select set_account_cost($1, 7.2)`, [A]));
let r = await adjust(ADMIN, 9950, 'مطابقة كشف بهاروز', 'wrong');
ok(r.ok === false && r.error === 'wrong_password', 'a wrong password changes nothing', JSON.stringify(r));
ok((await bal()) === 10000, 'still 10,000');
r = await adjust(ADMIN, 9950.004);
ok(r.ok === true && n(r.balance_before) === 10000 && n(r.balance_after) === 9950, 'adjusted to 9,950.00', JSON.stringify(r));
ok((await bal()) === 9950, 'the balance moved');
const a1 = (await q(`select * from balance_adjustments`))[0];
ok(n(a1.delta) === -50 && a1.reason === 'مطابقة كشف بهاروز' && n(a1.balance_before) === 10000, 'kept with its reason and the balance before', JSON.stringify(a1));
ok(n((await q(`select cost_rate from account_costs where exchange_id = $1`, [A]))[0].cost_rate) === 7.2, 'the cost is untouched (at cost)');
await rejects(adjust(ADMIN, 9950), 'adjust_no_change', 'the same balance is refused');
await rejects(adjust(ADMIN, -1), 'adjust_amount_invalid', 'a negative balance is refused');
await rejects(adjust(ADMIN, 100, 'ab'), 'adjust_reason_required', 'a reason is required');
await rejects(adjust(A_EMP, 100), 'not_authorized', 'an employee cannot adjust');
await rejects(adjust(OTHER, 100, 'محاولة', 'other-1234'), 'not_authorized', 'another administrator cannot, even with his own password');
ok((await as(db, ADMIN, (tx) => tx.query(`select count(*)::int k from balance_adjustments`))).rows[0].k === 1, 'the administrator reads his adjustments');
ok((await as(db, OTHER, (tx) => tx.query(`select count(*)::int k from balance_adjustments`))).rows[0].k === 0, 'another one reads none');
await rejects(as(db, ADMIN, (tx) => tx.query(`delete from balance_adjustments`)), 'permission denied', 'nobody deletes one');

console.log('— B) the dinar treasury: closed until it is opened');
ok((await summary(ADMIN)).open === false, 'not open yet');
const before = await sell(ADMIN, 100, 7.3);
ok(before.lyd_method === 'cash', 'an exit without a method is paid in cash');
await rejects(move('in', 'cash', 10), 'lyd_not_open', 'no movement before the opening');
await as(db, ADMIN, (tx) => tx.query(`select lyd_open(5000, 20000)`));
await rejects(as(db, ADMIN, (tx) => tx.query(`select lyd_open(1, 1)`)), 'lyd_already_open', 'opened once only');
let s = await summary(ADMIN);
ok(s.open === true && n(s.cash) === 5000 && n(s.bank) === 20000, 'the opening: 5,000 cash, 20,000 bank (the exit before it does not count)', JSON.stringify(s));

console.log('— B) operations move the box and the bank');
await sell(ADMIN, 1000, 7.35, 'cash');      // +7,350 cash
await sell(A_EMP, 2000, 7.4, 'bank');       // +14,800 bank
await buy(ADMIN, 500, 7.1, 'cash');         // −3,550 cash
const b2 = await buy(ADMIN, 100, 7.0, 'bank');  // −700 bank
ok(b2.lyd_method === 'bank', 'the method is stored');
await rejects(sell(ADMIN, 1, 7.3, 'card'), 'lyd_method_invalid', 'only cash or bank');
s = await summary(ADMIN);
ok(n(s.cash) === 5000 + 7350 - 3550, 'cash = 5,000 + 7,350 − 3,550 = 8,800', String(s.cash));
ok(n(s.bank) === 20000 + 14800 - 700, 'bank = 20,000 + 14,800 − 700 = 34,100', String(s.bank));
ok(n(s.flows.sales_cash) === 7350 && n(s.flows.sales_bank) === 14800 && n(s.flows.buys_cash) === 3550 && n(s.flows.buys_bank) === 700, 'the period\'s flows', JSON.stringify(s.flows));

console.log('— B) a cancelled exit gives its dinars back');
const cx = await sell(ADMIN, 100, 7.3, 'cash');
ok(n((await summary(ADMIN)).cash) === 8800 + 730, '+730');
await as(db, ADMIN, (tx) => tx.query(`select admin_cancel_operation('transfer', $1, 'خطأ', 'pass-1234')`, [cx.id]));
ok(n((await summary(ADMIN)).cash) === 8800, 'back to 8,800');

console.log('— B) deposits, withdrawals, transfers');
await move('in', 'cash', 1000, 'رأس مال');
await move('out', 'bank', 4100, 'مصاريف');
await move('cash_to_bank', null, 2000, 'إيداع في المصرف');
await move('bank_to_cash', null, 500);
s = await summary(ADMIN);
ok(n(s.cash) === 8800 + 1000 - 2000 + 500 && n(s.bank) === 34100 - 4100 + 2000 - 500, 'cash 8,300 · bank 31,500', JSON.stringify([s.cash, s.bank]));
await rejects(move('out', 'cash', 999999), 'lyd_insufficient', 'nothing leaves a box that does not hold it');
await rejects(move('cash_to_bank', null, 999999), 'lyd_insufficient', 'nor moves from it');
await rejects(move('in', null, 10), 'lyd_kind_invalid', 'a deposit needs a pocket');
await rejects(move('in', 'cash', 0), 'lyd_amount_invalid', 'an amount is required');
ok(s.movements.length === 4 && s.movements[0].kind === 'bank_to_cash', 'the movements, newest first');

console.log('— B) the end-of-day count');
let c = await count(8250);                  // 50 short
ok(n(c.expected) === 8300 && n(c.counted) === 8250 && n(c.difference) === -50, 'short by 50', JSON.stringify(c));
ok(n((await summary(ADMIN)).cash) === 8250, 'the shortage is posted: the box now says 8,250');
c = await count(8260, false);               // 10 over, not posted
ok(n(c.difference) === 10 && n((await summary(ADMIN)).cash) === 8250, 'not posted: the box still says 8,250');
s = await summary(ADMIN);
ok(s.counts.length === 2 && s.counts[0].posted === false && s.counts[1].posted === true, 'both counts kept', JSON.stringify(s.counts.map((x) => x.posted)));
await rejects(count(-1), 'lyd_amount_invalid', 'a negative count is refused');

console.log('— B) for the administrator only');
await rejects(summary(A_EMP), 'not_authorized', 'an employee sees no dinar treasury');
await rejects(as(db, A_EMP, (tx) => tx.query(`select lyd_add_movement('in','cash',1,null)`)), 'not_authorized', 'nor moves it');
ok((await summary(OTHER)).open === false, 'another administrator has his own (closed)');
const direct = await as(db, ADMIN, (tx) => tx.query(`select * from lyd_movements`)).catch(() => ({ rows: null }));
ok(direct.rows === null || direct.rows.length === 0, 'the tables are not readable directly');
await q(`update account_licenses set status = 'expired' where user_id = $1`, [ADMIN]);
await rejects(move('in', 'cash', 1), 'license', 'an expired licence moves nothing');
await q(`update account_licenses set status = 'active' where user_id = $1`, [ADMIN]);

console.log('— C) a backup and a restore keep all of it');
const snap = await summary(ADMIN);
const backup = (await q(`select _build_backup() b`))[0].b;
ok(['balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts'].every((k) => (backup.tables[k] ?? []).length > 0), 'in the backup');
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_backup($1::jsonb)`, [JSON.stringify(backup)]));
const after = await summary(ADMIN);
ok(n(after.cash) === n(snap.cash) && n(after.bank) === n(snap.bank) && after.counts.length === 2, 'the same box and bank after the restore', JSON.stringify([after.cash, after.bank]));
ok((await q(`select count(*)::int k from balance_adjustments`))[0].k === 1, 'and the adjustment');

console.log('— the older build still saves (no method): cash');
const legacy = await as(db, ADMIN, (tx) => tx.query(`select * from record_transfer($1,$2,'م',null,null,10,'R',7.3)`, [c1, A])).then((x) => x.rows[0]);
ok(legacy.lyd_method === 'cash', 'cash');

console.log('— re-running: this file is harmless, 0084 refuses');
const sql86 = fs.readFileSync(new URL('../migrations/0086_adjustments_and_dinar_treasury.sql', import.meta.url), 'utf8');
await db.exec('set search_path = public, extensions;\n' + sql86);
ok(n((await summary(ADMIN)).cash) === n(after.cash) + 73, 'still works (+73 from the last exit)');
const sql84 = fs.readFileSync(new URL('../migrations/0084_cost_integrity.sql', import.meta.url), 'utf8');
let msg = 'ran';
try { await db.exec('set search_path = public, extensions;\n' + sql84); } catch (e) { msg = e.message; }
await db.exec('rollback').catch(() => {});
ok(msg.includes('طُبّق سابقًا'), '0084 refuses after 0086', msg);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
