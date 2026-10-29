import { freshDb, as } from './harness.mjs';

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
    ('${OTHER}', 'o@x.ly', 'x');
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';
  insert into account_licenses (user_id, status, license_type, is_admin) values
    ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const A = (await as(db, ADMIN, (tx) => tx.query(`select * from admin_open_account($1,'بهاروز',100000,null,null,7)`, [c1]))).rows[0].id;
const C = (await q(`insert into clients (owner_id, name, company) values ($1, 'محمد', 'السيادة') returning id`, [ADMIN]))[0].id;
const C2 = (await q(`insert into clients (owner_id, name) values ($1, 'بائع') returning id`, [ADMIN]))[0].id;
const otherClient = (await q(`insert into clients (owner_id, name) values ($1, 'غريب') returning id`, [OTHER]))[0].id;
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','rate_edit_sell','rate_edit_buy']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);

const sell = (uid, usd, { rate = 7, customer = null, paid = null, method = 'cash', over = false } = {}) =>
  as(db, uid, (tx) => tx.query(`select * from record_transfer($1,$2,'مستفيد',null,null,$3,'',$4,$5,null,$6,$7,$8)`,
    [c1, A, usd, rate, method, customer, paid, over])).then((r) => r.rows[0]);
const buy = (uid, usd, { rate = 7.1, client = null, paid = null, method = 'cash' } = {}) =>
  as(db, uid, (tx) => tx.query(`select * from record_currency_buy($1,$2,$3,null,$4,$5,null,'',$6,null,$7)`,
    [c1, A, client, usd, rate, method, paid])).then((r) => r.rows[0]);
const owed = async (client = C) => n((await q(`select coalesce(sum(amount),0) s from customer_lyd_entries where client_id = $1`, [client]))[0].s);
const entry = (kind, amount, pocket = null, client = C, note = null) => as(db, ADMIN, (tx) => tx.query(
  `select customer_add_entry($1,$2,$3,$4,$5) r`, [client, kind, amount, pocket, note])).then((r) => r.rows[0].r);
const limit = (l, client = C) => as(db, ADMIN, (tx) => tx.query(`select set_customer_credit_limit($1,$2)`, [client, l]));
const cash = async () => n((await as(db, ADMIN, (tx) => tx.query(`select lyd_summary('2000-01-01','2100-01-01') s`))).rows[0].s.cash);

await as(db, ADMIN, (tx) => tx.query(`select lyd_open(1000, 5000)`));

console.log('— paid in full, as before (an older build sends nothing new)');
const old = (await as(db, ADMIN, (tx) => tx.query(`select * from record_transfer($1,$2,'م',null,null,10,'',7,'cash')`, [c1, A]))).rows[0];
ok(n(old.lyd_paid) === 70 && old.lyd_method === 'cash' && old.customer_id === null, 'lyd_paid = lyd_amount = 70');
ok((await cash()) === 1070, 'the box: 1,000 + 70');

console.log('— a sale on credit needs a customer and a limit');
await rejects(sell(ADMIN, 100, { paid: 0 }), 'customer_required', 'no customer');
await rejects(sell(ADMIN, 100, { paid: 0, customer: otherClient }), 'client_not_found_or_forbidden', 'another administrator\'s customer');
await rejects(sell(ADMIN, 100, { paid: 0, customer: C }), 'credit_limit_exceeded', 'no limit set: no credit');
let t = await sell(ADMIN, 100, { paid: 0, customer: C, over: true });
ok(n(t.lyd_amount) === 700 && n(t.lyd_paid) === 0 && t.lyd_method === null, 'the administrator went over: all 700 on credit, no method', JSON.stringify([t.lyd_paid, t.lyd_method]));
ok((await owed()) === 700, 'the customer owes 700');
ok((await cash()) === 1070, 'nothing came into the box');
await rejects(sell(ADMIN, 1, { paid: 8 }), 'lyd_paid_invalid', 'paid more than the dinars');
await rejects(sell(ADMIN, 1, { paid: -1, customer: C }), 'lyd_paid_invalid', 'negative paid');

console.log('— the limit');
await rejects(q(`update clients set credit_limit = 5 where id = $1`, [C]).then(() => as(db, ADMIN, (tx) => tx.query(`update clients set credit_limit = 99999 where id = $1`, [C]))), 'credit_limit_direct_edit', 'not changed directly');
await rejects(as(db, A_EMP, (tx) => tx.query(`select set_customer_credit_limit($1, 5000)`, [C])), 'not_authorized', 'not by an employee');
await limit(1000);
await rejects(sell(A_EMP, 100, { paid: 200, customer: C }), 'credit_limit_exceeded', 'employee: 700 + 500 > 1,000 refused');
await rejects(sell(A_EMP, 100, { paid: 200, customer: C, over: true }), 'credit_limit_exceeded', 'an employee cannot go over even if he asks');
t = await sell(A_EMP, 100, { paid: 500, customer: C, method: 'bank' });
ok(n(t.lyd_paid) === 500 && t.lyd_method === 'bank', 'employee: 500 paid by bank, 200 on credit');
ok((await owed()) === 900, 'the customer owes 900 (within 1,000)');

console.log('— collections and payments');
let r = await entry('collect', 400, 'cash', C, 'دفعة');
ok(n(r.balance) === 500, 'collected 400: he owes 500');
ok((await cash()) === 1470, 'the box: +400');
await rejects(entry('collect', 0, 'cash'), 'lyd_amount_invalid', 'an amount is required');
await rejects(entry('collect', 10, null), 'lyd_kind_invalid', 'a pocket is required');
await rejects(as(db, A_EMP, (tx) => tx.query(`select customer_add_entry($1,'collect',10,'cash')`, [C])), 'not_authorized', 'not by an employee');

console.log('— buying on credit: we owe the seller');
const b = await buy(ADMIN, 50, { client: C2, paid: 100 });
ok(n(b.lyd_amount) === 355 && n(b.lyd_paid) === 100, 'paid 100 of 355');
ok((await owed(C2)) === -255, 'we owe the seller 255');
ok((await cash()) === 1370, 'the box: −100');
await rejects(buy(ADMIN, 50, { paid: 0 }), 'customer_required', 'credit needs the seller');
await rejects(entry('pay', 99999, 'cash', C2), 'lyd_insufficient', 'cannot pay more than the box holds');
r = await entry('pay', 255, 'cash', C2);
ok(n(r.balance) === 0 && (await cash()) === 1115, 'paid him 255 from the box: settled');

console.log('— cancelling gives the debt back');
const t3 = await sell(ADMIN, 50, { paid: 0, customer: C });   // +350 → 850
ok((await owed()) === 850, 'owes 850');
await as(db, ADMIN, (tx) => tx.query(`select admin_cancel_operation('transfer',$1,'خطأ','pass-1234')`, [t3.id]));
ok((await owed()) === 500, 'cancelled: back to 500');
const rev = (await q(`select kind, amount from customer_lyd_entries where operation_id = $1 order by created_at`, [t3.id]));
ok(rev.length === 2 && rev[1].kind === 'sale_cancel' && n(rev[1].amount) === -350, 'a reversing line', JSON.stringify(rev));

console.log('— the count sees collections');
const cnt = (await as(db, ADMIN, (tx) => tx.query(`select lyd_record_count($1,'جرد',false) r`, [1115]))).rows[0].r;
ok(n(cnt.difference) === 0, 'expected 1,115 in the box', JSON.stringify(cnt));
const s = (await as(db, ADMIN, (tx) => tx.query(`select lyd_summary('2000-01-01','2100-01-01') s`))).rows[0].s;
ok(n(s.flows.collect_cash) === 400 && n(s.flows.pay_cash) === 255 && n(s.flows.sales_bank) === 500, 'the flows', JSON.stringify(s.flows));

console.log('— the statement and the list');
await entry('opening', 120, null, C, 'قبل التطبيق');
const st = (await as(db, ADMIN, (tx) => tx.query(`select customer_statement($1,'2000-01-01','2100-01-01') r`, [C]))).rows[0].r;
ok(n(st.opening) === 0 && n(st.closing) === 620 && st.entries.length === 6, 'opening 0, closing 620, six lines', JSON.stringify([st.opening, st.closing, st.entries.length]));
ok(st.entries[0].reference === 'Rh0101' && n(st.entries[0].usd) === 100, 'each line knows its operation');
const list = (await as(db, ADMIN, (tx) => tx.query(`select customer_balances() r`))).rows[0].r;
const lc = list.find((x) => x.client_id === C);
ok(n(lc.balance) === 620 && n(lc.credit_limit) === 1000, 'the list: 620, limit 1,000');
ok(list.every((x) => x.client_id !== otherClient), 'only this administrator\'s customers');
await rejects(as(db, A_EMP, (tx) => tx.query(`select customer_balances()`)), 'not_authorized', 'employees do not see the accounts');
ok((await as(db, OTHER, (tx) => tx.query(`select count(*)::int k from customer_lyd_entries`))).rows[0].k === 0, 'another administrator reads none');
await rejects(as(db, ADMIN, (tx) => tx.query(`delete from clients where id = $1`, [C])), 'violates foreign key', 'a customer with a dinar account or a sale cannot be deleted');

await rejects(as(db, ADMIN, (tx) => tx.query(`select delete_party($1)`, [C])), 'client_has_operations', 'the app\'s delete says why, in words the app knows');
let empErr = '';
try { await sell(A_EMP, 1000, { paid: 0, customer: C }); } catch (e) { empErr = `${e.message} ${e.detail ?? ''}`; }
ok(empErr.includes('credit_limit_exceeded') && !empErr.includes('owed'), 'an employee is refused without seeing what the customer owes', empErr);

console.log('— a backup made before 0091 (no lyd_paid) still restores');
const oldB = (await q(`select _save_backup('manual') id`))[0].id;
await q(`update backups set data = jsonb_set(jsonb_set(data,
    '{tables,transfers}', (select jsonb_agg(e - 'lyd_paid') from jsonb_array_elements(data->'tables'->'transfers') e)),
    '{tables,currency_buys}', (select coalesce(jsonb_agg(e - 'lyd_paid'), '[]'::jsonb) from jsonb_array_elements(data->'tables'->'currency_buys') e))
  where id = $1`, [oldB]);
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [oldB, ADMIN]));
ok((await q(`select count(*)::int k from transfers where owner_id = $1 and lyd_amount is not null and lyd_paid = lyd_amount`, [ADMIN]))[0].k > 0, 'restored, read as paid in full');
const oldData = (await q(`select data from backups where id = $1`, [oldB]))[0].data;
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_backup($1)`, [oldData]));
ok(true, 'the full restore takes it too');

console.log('— backups, the one-subscriber restore and the wipe');
const backup = (await q(`select _save_backup('manual') id`))[0].id;
ok((await q(`select jsonb_array_length(data->'tables'->'customer_lyd_entries') k from backups where id = $1`, [backup]))[0].k === 8, 'the backup has the 8 lines');
await entry('collect', 20, 'cash', C);
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [backup, ADMIN]));
ok((await owed()) === 620, 'restored: 620 again (the later 20 gone)');
const w = (await as(db, ADMIN, (tx) => tx.query(`select owner_wipe_operations('pass-1234') r`))).rows[0].r;
ok(w.ok === true && (await q(`select count(*)::int k from customer_lyd_entries where owner_id = $1`, [ADMIN]))[0].k === 0, 'the wipe empties the dinar accounts');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
