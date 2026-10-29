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
const n = (v) => (v === null || v === undefined ? null : Number(v));
const near = (a, b, eps = 0.011) => Math.abs(Number(a) - Number(b)) <= eps;

const db = await freshDb({ upTo: 92 }); // a sale paid in cash from the account's dollars: 0093 sells from the cash book only
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password) values
    ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf'))),
    ('${PLATFORM}', 'p@x.ly', 'x'), ('${A_EMP}', null, null);
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';
  insert into account_licenses (user_id, status, license_type, is_admin) values
    ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);
const c1 = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
const adm = (sql, p = []) => as(db, ADMIN, (tx) => tx.query(sql, p)).then((r) => r.rows);
const A = (await adm(`select * from admin_open_account($1,'بهاروز',1000,null,null,7)`, [c1]))[0].id;
const B = (await adm(`select * from admin_open_account($1,'أنزار',0,null,null,null)`, [c1]))[0].id;
const C = (await q(`insert into clients (owner_id, name) values ($1, 'محمد') returning id`, [ADMIN]))[0].id;
const S = (await q(`insert into clients (owner_id, name) values ($1, 'بائع') returning id`, [ADMIN]))[0].id;
await adm(`select set_customer_credit_limit($1, 5000)`, [C]);
const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions) values ($1, 'موظف', '0911111111', 'x', array['transfers_create']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);

const sell = (ex, usd, rate, opt = {}) => adm(`select * from record_transfer($1,$2,'م',null,null,$3,'',$4,$5,null,$6,$7,false)`,
  [c1, ex, usd, rate, opt.method ?? 'cash', opt.customer ?? null, opt.paid ?? null]).then((r) => r[0]);
const buy = (ex, usd, rate, opt = {}) => adm(`select * from record_currency_buy($1,$2,$3,null,$4,$5,null,'',$6,null,$7)`,
  [c1, ex, opt.client ?? null, usd, rate, opt.method ?? 'cash', opt.paid ?? null]).then((r) => r[0]);

// before the dinar treasury: outside it (3200)
await sell(A, 10, 7.4);                                   // 74 dinars, cost 70 → +4
const t0 = new Date();
await new Promise((r) => setTimeout(r, 20));
await adm(`select lyd_open(5000, 20000)`);
await buy(A, 500, 7.2);                                   // cash −3600; cost (990×7 + 3600)/1490
await sell(A, 300, 7.5, { method: 'bank' });              // bank +2250
await sell(A, 100, 7.5, { customer: C, paid: 0 });        // he owes 750
await sell(B, 0.01, 7.5).catch(() => {});                 // B is empty: refused, nothing posted
await buy(B, 200, 7.0, { client: S, paid: 400 });         // B restarts at 7; we owe 1,000
await adm(`select customer_add_entry($1,'collect',300,'cash')`, [C]);
await adm(`select customer_add_entry($1,'pay',600,'bank')`, [S]);
const cx = await sell(A, 50, 7.6);                        // cancelled below
await adm(`select admin_cancel_operation('transfer',$1,'خطأ','pass-1234')`, [cx.id]);
await adm(`select admin_adjust_balance($1, $2, 'مطابقة', 'pass-1234')`, [A, n((await q(`select balance from exchanges where id=$1`, [A]))[0].balance) - 10]);
await adm(`select record_account_expense($1, 5, null, 'عمولة')`, [A]);
await adm(`select lyd_add_movement('in','cash',1000,'رأس مال')`);
await adm(`select lyd_record_count((select (lyd_summary('2000-01-01','2100-01-01')->>'cash')::numeric - 50), 'جرد', true)`);

const J = await adm(`select * from _journal($1)`, [ADMIN]).catch(async () => q(`select * from _journal($1)`, [ADMIN]));

console.log('— the journal balances');
const total = J.reduce((s, l) => s + Number(l.amount), 0);
ok(near(total, 0, 0.0001), 'debits = credits', String(total));
const bySource = {};
for (const l of J) { const k = `${l.source_id}|${l.at.toISOString?.() ?? l.at}`; bySource[k] = (bySource[k] ?? 0) + Number(l.amount); }
const off = Object.entries(bySource).filter(([, v]) => Math.abs(v) > 0.0001);
ok(off.length === 0, 'every entry balances on its own', JSON.stringify(off.slice(0, 3)));
await rejects(as(db, ADMIN, (tx) => tx.query(`select * from _journal($1)`, [ADMIN])), 'permission denied', 'the raw journal is internal');

const bal = (acct, filter = () => true) => J.filter((l) => l.account === acct && filter(l)).reduce((s, l) => s + Number(l.amount), 0);

console.log('— the ledger agrees with the screens');
const sum = (await adm(`select lyd_summary('2000-01-01','2100-01-01') s`))[0].s;
ok(near(bal('1100'), sum.cash), `the box: ledger ${bal('1100').toFixed(2)} = treasury ${sum.cash}`);
ok(near(bal('1110'), sum.bank), `the bank: ledger ${bal('1110').toFixed(2)} = treasury ${sum.bank}`);
const custs = (await adm(`select customer_balances() r`))[0].r;
for (const c of custs) {
  ok(near(bal('1200', (l) => l.client_id === c.client_id), c.balance), `customer ${c.name}: ${c.balance}`);
}
const positions = (await adm(`select * from treasury_positions()`));
for (const p of positions) {
  if (p.cost_rate == null) continue;
  const book = Number(p.balance) * Number(p.cost_rate);
  ok(near(bal('1300', (l) => l.exchange_id === p.exchange_id), book, 0.05),
    `${p.account_name}: inventory ${bal('1300', (l) => l.exchange_id === p.exchange_id).toFixed(2)} ≈ ${book.toFixed(2)}`);
}

console.log('— the statements');
const tb = (await adm(`select ledger_trial_balance(now()) r`))[0].r;
ok(near(tb.reduce((s, r) => s + n(r.debit ?? 0), 0), tb.reduce((s, r) => s + n(r.credit ?? 0), 0), 0.0001), 'trial balance: debits = credits');
const is = (await adm(`select ledger_income_statement('2000-01-01', now()) r`))[0].r;
const line = (a) => n(is.lines.find((x) => x.account === a)?.amount ?? 0);
ok(near(line('4100'), -(bal('4100'))), 'sale result = ledger');
ok(near(line('5200'), -50), 'count shortage −50');
ok(line('5100') < 0 && line('5300') < 0, 'the adjustment and the commission are losses', JSON.stringify(is.lines));
ok(near(is.net, is.lines.reduce((s, x) => s + n(x.amount), 0)), 'net = sum of the lines');
const bs = (await adm(`select ledger_balance_sheet(now()) r`))[0].r;
const b = bs.balances;
const assets = ['1100', '1110', '1200', '1300', '1390'].reduce((s, k) => s + n(b[k] ?? 0), 0);
const equity = ['3100', '3150', '3200'].reduce((s, k) => s - n(b[k] ?? 0), 0) - n(b.profit ?? 0);
ok(near(assets, equity, 0.0001), `balance sheet: assets ${assets.toFixed(2)} = equity ${equity.toFixed(2)}`);
ok(near(n(bs.receivable), 450) && near(n(bs.payable), 400), 'customers apart: 450 owed to us, 400 we owe', JSON.stringify([bs.receivable, bs.payable]));
const jr = (await adm(`select ledger_journal('2000-01-01', now()) r`))[0].r;
ok(jr.total === J.length && jr.lines[0].name, 'the journal for the screen, with names');
await rejects(as(db, A_EMP, (tx) => tx.query(`select ledger_trial_balance(now())`)), 'not_authorized', 'not for an employee');

console.log('— the period close');
// one sale an hour back, so the close covers it
await q(`update transfers set created_at = created_at - interval '1 hour', archived_at = archived_at - interval '1 hour' where id = (select id from transfers where owner_id = $1 order by created_at limit 1)`, [ADMIN]);
const closed = (await adm(`select close_period(now() - interval '5 minutes', 'أكتوبر') r`))[0].r;
ok(closed.ok, 'closed');
let closes = (await adm(`select ledger_closes() r`))[0].r;
ok(closes.length === 1 && closes[0].intact === true, 'intact');
await rejects(adm(`select close_period(now() - interval '1 hour')`), 'period_already_closed', 'not twice over the same time');
// the past changed behind the ledger's back (as a restore of an older backup would)
await q(`update transfers set amount = amount + 1 where owner_id = $1 and created_at < now() - interval '2 seconds' and cancelled_at is null and lyd_amount is not null and id = (select id from transfers where owner_id = $1 order by created_at limit 1)`, [ADMIN]);
await q(`update transfers set lyd_amount = lyd_amount + 7.4, lyd_paid = lyd_paid + 7.4 where id = (select id from transfers where owner_id = $1 order by created_at limit 1)`, [ADMIN]);
closes = (await adm(`select ledger_closes() r`))[0].r;
ok(closes[0].intact === false, 'a changed past is caught');

console.log('— reconciling with the company\'s statement');
const atStart = t0.toISOString();
const r1 = (await adm(`select reconcile_account($1,$2,990,'كشف بهاروز') r`, [A, atStart]))[0].r;
ok(near(r1.our_balance, 990) && near(r1.difference, 0), `before the treasury: ours 990 (1,000 − 10)`, JSON.stringify(r1));
const now = n((await q(`select balance from exchanges where id=$1`, [A]))[0].balance);
const r2 = (await adm(`select reconcile_account($1, now(), $2, null) r`, [A, now + 25]))[0].r;
ok(near(r2.difference, 25), 'they say 25 more: the difference shows');
const list = (await adm(`select account_reconciliations_list($1) r`, [A]))[0].r;
ok(list.length === 2, 'both kept');
await rejects(adm(`select reconcile_account($1, now() + interval '1 day', 1, null)`, [A]), 'period_invalid', 'not in the future');

console.log('— backups and the wipe');
const bk = (await q(`select _save_backup('manual') id`))[0].id;
ok((await q(`select jsonb_array_length(data->'tables'->'period_closes') k from backups where id=$1`, [bk]))[0].k === 1, 'the closes are in the backup');
await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2)`, [bk, ADMIN]));
ok((await q(`select count(*)::int k from account_reconciliations`))[0].k === 2, 'restored');
const w = (await adm(`select owner_wipe_operations('pass-1234') r`))[0].r;
ok(w.ok && (await q(`select count(*)::int k from period_closes`))[0].k === 0, 'the wipe takes the closes too');
const J2 = await q(`select * from _journal($1)`, [ADMIN]);
ok(near(J2.reduce((s, l) => s + Number(l.amount), 0), 0, 0.0001), 'after the wipe the journal still balances');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
