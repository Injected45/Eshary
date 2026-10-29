import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const ADMIN = '11111111-1111-1111-1111-111111111111';
const A_EMP = '33333333-3333-3333-3333-333333333333';
const OTHER = '44444444-4444-4444-4444-444444444444';
const REQ1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const REQ2 = 'aaaaaaaa-0000-4000-8000-000000000002';
const n = (v) => (v === null || v === undefined ? null : Number(v));

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf'))),
    ('${A_EMP}', null, null),
    ('${OTHER}', 'o@x.ly', extensions.crypt('other-1234', extensions.gen_salt('bf')));
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const A = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'بهاروز', 10000) returning id`, [c1]))[0].id;
const cO = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'آخر', 'X100') returning id`, [OTHER]))[0].id;
const otherClient = (await q(`insert into clients (owner_id, name) values ($1, 'عميل آخر') returning id`, [OTHER]))[0].id;
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','rate_edit_sell','accounts_all']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);

const bal = async (id = A) => n((await q(`select balance from exchanges where id = $1`, [id]))[0].balance);
const sell = (uid, usd, { rate = 7.35, ref = 'ANY', req = null } = {}) => as(db, uid, (tx) => tx.query(
  `select * from record_transfer($1,$2,'م',null,null,$3,$4,$5,'cash',$6)`, [c1, A, usd, ref, rate, req])).then((r) => r.rows[0]);
const buy = (uid, usd, { rate = 7.1, req = null, client = null } = {}) => as(db, uid, (tx) => tx.query(
  `select * from record_currency_buy($1,$2,$3,null,$4,$5,null,'','cash',$6)`, [c1, A, client, usd, rate, req])).then((r) => r.rows[0]);
const nextRef = () => as(db, ADMIN, (tx) => tx.query(`select next_reference($1) r`, [c1])).then((r) => r.rows[0].r);

console.log('— A) the reference is given by the database');
let t = await sell(ADMIN, 100, { ref: 'WHATEVER' });
ok(t.reference === 'Rh0100', 'the phone\'s number is ignored: Rh0100', t.reference);
t = await sell(ADMIN, 100, { ref: 'Rh0100' });
ok(t.reference === 'Rh0101', 'a stale number on the phone cannot repeat: Rh0101', t.reference);
ok((await nextRef()) === 'Rh0102', 'the next one is Rh0102');
await rejects(q(`insert into transfers (owner_id, company_id, exchange_id, beneficiary_name, amount, reference, status)
  values ($1,$2,$3,'x',1,'Rh0101','archived')`, [ADMIN, c1, A]), 'transfers_owner_ref_active_uq', 'an active reference can never be stored twice');
await as(db, ADMIN, (tx) => tx.query(`select admin_cancel_operation('transfer', $1, 'خطأ', 'pass-1234')`, [t.id]));
t = await sell(ADMIN, 100);
ok(t.reference === 'Rh0101', 'the last one cancelled: its number is given again (0080)', t.reference);

console.log('— B) the same request twice saves once');
const before = await bal();
const t1 = await sell(ADMIN, 250, { req: REQ1 });
const t2 = await sell(ADMIN, 250, { req: REQ1 });
ok(t1.id === t2.id && t1.reference === t2.reference, 'the retry returns the saved exit');
ok((await bal()) === before - 250, 'debited once', String(await bal()));
const b1 = await buy(ADMIN, 300, { req: REQ2 });
const b2 = await buy(ADMIN, 300, { req: REQ2 });
ok(b1.id === b2.id, 'the retry returns the saved entry');
ok((await bal()) === before - 250 + 300, 'credited once', String(await bal()));
const tOther = await as(db, OTHER, (tx) => tx.query(`select count(*)::int k from transfers where request_id = $1`, [REQ1]));
ok(tOther.rows[0].k === 0, 'another administrator does not see the request');

console.log('— C) a customer of another administrator is refused');
await rejects(buy(ADMIN, 10, { client: otherClient }), 'client_not_found_or_forbidden', 'the entry is refused');

console.log('— D) an employee\'s typed rate stays near the administrator\'s');
await sell(ADMIN, 10, { rate: 7.35 }); // the administrator's last sell rate
await rejects(sell(A_EMP, 10, { rate: 8.6 }), 'rate_unusual', '8.60 against 7.35 (+17 %) is refused');
t = await sell(A_EMP, 10, { rate: 7.8 });
ok(n(t.rate) === 7.8, 'within 15 %: 7.80 is kept');
t = await buy(A_EMP, 10, { rate: 99 });
ok(n(t.rate) === 7.1, 'no permission for the buy rate: the administrator\'s 7.10, whatever was typed', String(t.rate));
const lastSell = n((await q(`select rate from last_exchange_rates where owner_id = $1 and kind = 'sell'`, [ADMIN]))[0].rate);
ok(lastSell === 7.35, 'an employee\'s rate never becomes the administrator\'s last rate');

console.log('— E) accounts');
await rejects(as(db, ADMIN, (tx) => tx.query(`insert into exchanges (company_id, name, balance) values ($1,'مباشر',5000)`, [c1])), 'balance_direct_edit', 'no account is created with a balance directly');
const open = (args, uid = ADMIN) => as(db, uid, (tx) => tx.query(
  `select * from admin_open_account($1,$2,$3,$4,$5,$6)`, args)).then((r) => r.rows[0]);
await rejects(open([c1, 'أنزار', 100, null, null, null]), 'opening_cost_required', 'dollars need a cost');
await rejects(open([c1, 'أنزار', 100, null, null, 0.5]), 'rate_out_of_range', 'a cost out of range');
const before2 = n((await q(`select count(*)::int k from exchanges`))[0].k);
ok(before2 === 1, 'nothing was created by the refused tries');
await rejects(open([c1, 'أنزار', 100, null, null, 9.5], A_EMP), 'not_authorized', 'an employee cannot open one');
await rejects(open([cO, 'أنزار', 100, null, null, 9.5]), 'company_not_found_or_forbidden', 'nor in another administrator\'s company');
const acc = await open([c1, ' أنزار ', 100, 'Z-1', 'تركيا', 9.5]);
ok(acc.name === 'أنزار' && n(acc.balance) === 100 && acc.our_code === 'Z-1', 'opened with 100 $', JSON.stringify(acc));
const openLine = (await q(`select * from balance_adjustments where exchange_id = $1`, [acc.id]))[0];
ok(openLine.kind === 'opening' && n(openLine.balance_before) === 0 && n(openLine.delta) === 100 && openLine.reason === 'رصيد افتتاحي', 'the opening line', JSON.stringify(openLine));
ok(n((await q(`select cost_rate from account_costs where exchange_id = $1`, [acc.id]))[0].cost_rate) === 9.5, 'cost 9.5: the 100 $ cost 950 LYD');
ok((await q(`select kind from account_cost_events where exchange_id = $1`, [acc.id]))[0].kind === 'opening', 'recorded as the opening cost');
const empty = await open([c1, 'فارغ', 0, null, null, null]);
ok(n(empty.balance) === 0, 'an empty account needs no cost');
ok((await q(`select count(*)::int k from balance_adjustments where exchange_id = $1`, [empty.id]))[0].k === 0, 'and has no opening line');

await rejects(as(db, ADMIN, (tx) => tx.query(`delete from exchanges where id = $1`, [acc.id])), 'account_has_history', 'an account with a balance stays');
await rejects(as(db, ADMIN, (tx) => tx.query(`delete from companies where id = $1`, [c1])), 'account_has_history', 'its company too');
await as(db, ADMIN, (tx) => tx.query(`delete from exchanges where id = $1`, [empty.id]));
ok((await q(`select count(*)::int k from exchanges where id = $1`, [empty.id]))[0].k === 0, 'an empty account with no history can be deleted');
await rejects(q(`update exchanges set balance = -1 where id = $1`, [A]), 'insufficient_balance', 'a balance never goes below zero');

console.log('— F) the dinar treasury still works with its locks');
await as(db, ADMIN, (tx) => tx.query(`select lyd_open(1000, 0)`));
await as(db, ADMIN, (tx) => tx.query(`select lyd_add_movement('in','cash',500,null)`));
await sell(ADMIN, 100, { rate: 7 }); // +700 cash
const c = (await as(db, ADMIN, (tx) => tx.query(`select lyd_record_count(2200, 'جرد', true) r`))).rows[0].r;
ok(n(c.expected) === 2200 && n(c.difference) === 0, 'expected 1,000 + 500 + 700 = 2,200', JSON.stringify(c));

console.log('— H) the legacy pending buy is closed');
await rejects(as(db, ADMIN, (tx) => tx.query(`select record_pending_buy($1,$2,null,null,10,7,70,'')`, [c1, A])), 'permission denied', 'record_pending_buy');

console.log('— G) wiping asks for the password and leaves nothing behind');
const wipe = (pw) => as(db, ADMIN, (tx) => tx.query(`select owner_wipe_operations($1) r`, [pw])).then((r) => r.rows[0].r);
const lastRef = (await q(`select reference from transfers where owner_id = $1 and cancelled_at is null order by created_at desc limit 1`, [ADMIN]))[0].reference;
let w = await wipe('wrong');
ok(w.ok === false && w.error === 'wrong_password', 'a wrong password wipes nothing', JSON.stringify(w));
ok((await q(`select count(*)::int k from transfers`))[0].k > 0, 'the transfers are still there');
await rejects(as(db, A_EMP, (tx) => tx.query(`select owner_wipe_operations('pass-1234')`)), 'not_authorized', 'an employee cannot wipe');
const expectedNext = await nextRef();
w = await wipe('pass-1234');
ok(w.ok === true, 'wiped', JSON.stringify(w));
for (const tbl of ['transfers', 'currency_buys', 'operation_costs', 'account_cost_events', 'account_costs', 'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts']) {
  ok((await q(`select count(*)::int k from ${tbl} where owner_id = $1`, [ADMIN]))[0].k === 0, `${tbl} emptied`);
}
ok((await bal()) === 0 && (await bal(acc.id)) === 0, 'balances at zero');
ok((await nextRef()) === expectedNext, `the numbering goes on: ${expectedNext} (last used ${lastRef})`, await nextRef());
ok((await q(`select count(*)::int k from transfers where owner_id = $1`, [OTHER]))[0].k === 0 &&
   (await q(`select count(*)::int k from companies where owner_id = $1`, [OTHER]))[0].k === 1, 'another administrator is untouched');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
