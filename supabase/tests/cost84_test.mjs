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
const n = (v) => (v === null || v === undefined ? null : Number(v));
const SQL84 = fs.readFileSync(new URL('../migrations/0084_cost_integrity.sql', import.meta.url), 'utf8');

async function setup(db, { balanceA = 0 } = {}) {
  const q = async (sql, p) => (await db.query(sql, p)).rows;
  await db.exec(`
    insert into auth.users (id, email, encrypted_password) values
      ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf'))),
      ('${PLATFORM}', 'p@x.ly', 'x'), ('${A_EMP}', null, null);
    insert into account_licenses (user_id, status, license_type) values
      ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';
    insert into account_licenses (user_id, status, license_type, is_admin) values
      ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);
  const c = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'الرحالة', 'Rh0100') returning id`, [ADMIN]))[0].id;
  const A = (await q(`insert into exchanges (company_id, name, balance) values ($1, 'بهاروز', $2) returning id`, [c, balanceA]))[0].id;
  const emp = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
    values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create','view_all','view_own','rate_edit_sell','rate_edit_buy']) returning id`, [ADMIN]))[0].id;
  await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1')`, [emp, A_EMP]);
  const buy = (uid, usd, rate, lyd = null) => as(db, uid, (tx) => tx.query(
    `select * from record_currency_buy($1,$2,null,null,$3,$4,$5,'')`, [c, A, usd, rate, lyd])).then((r) => r.rows[0]);
  const sell = (uid, usd, rate) => as(db, uid, (tx) => tx.query(
    `select * from record_transfer($1,$2,'م',null,null,$3,'R',$4)`, [c, A, usd, rate])).then((r) => r.rows[0]);
  const cancel = (kind, id) => as(db, ADMIN, (tx) => tx.query(
    `select admin_cancel_operation($1, $2, 'خطأ', 'pass-1234')`, [kind, id]));
  const setCost = (rate) => as(db, ADMIN, (tx) => tx.query(`select set_account_cost($1,$2)`, [A, rate]));
  const cost = async () => n((await q(`select cost_rate from account_costs where exchange_id = $1`, [A]))[0]?.cost_rate);
  const bal = async () => n((await q(`select balance from exchanges where id = $1`, [A]))[0].balance);
  return { q, c, A, buy, sell, cancel, setCost, cost, bal };
}

{
  console.log('— the costs already stored move out of the operation tables');
  const db = await freshDb({ upTo: 83 });
  const t = await setup(db, { balanceA: 0 });
  const b = await t.buy(ADMIN, 1000, 7.0);
  const s = await t.sell(ADMIN, 100, 7.3);
  await db.exec('set search_path = public, extensions;\n' + SQL84);
  const oc = await t.q(`select operation_id, kind, cost_before::float cb, cost_after::float ca from operation_costs order by kind`);
  ok(oc.length === 2 && oc[0].kind === 'buy' && oc[0].operation_id === b.id && oc[0].ca === 7, 'the entry\'s cost', JSON.stringify(oc));
  ok(oc[1].kind === 'sell' && oc[1].operation_id === s.id && oc[1].ca === 7, 'the exit\'s cost');
  const cols = (await t.q(`select table_name, column_name from information_schema.columns
    where table_schema='public' and column_name in ('cost_rate','cost_before','cost_after') and table_name in ('transfers','currency_buys')`));
  ok(cols.length === 0, 'the columns are gone from transfers and currency_buys', JSON.stringify(cols));
  await db.exec('set search_path = public, extensions;\n' + SQL84);
  ok((await t.q(`select count(*)::int k from operation_costs`))[0].k === 2, 'running it again changes nothing');
}

const db = await freshDb();
const t = await setup(db, { balanceA: 0 });
const { q, A } = t;

console.log('— an employee cannot read any cost, even with "view all"');
await t.buy(ADMIN, 1000, 7.0);
await t.sell(ADMIN, 100, 7.3);
const empSees = await as(db, A_EMP, (tx) => tx.query(`select * from operation_costs`)).catch(() => ({ rows: null }));
ok(empSees.rows === null || empSees.rows.length === 0, 'operation_costs is closed');
const empRow = await as(db, A_EMP, (tx) => tx.query(`select * from transfers limit 1`)).then((r) => r.rows[0]).catch(() => null);
ok(!empRow || !('cost_rate' in empRow), 'a transfer row carries no cost', JSON.stringify(empRow && Object.keys(empRow)));
const empBuy = await as(db, A_EMP, (tx) => tx.query(`select * from currency_buys limit 1`)).then((r) => r.rows[0]).catch(() => null);
ok(!empBuy || !('cost_after' in empBuy), 'an entry row carries no cost');

console.log('— cancelling an exit: its dollars come back at THEIR cost (the reviewer\'s case)');
// reset: sell everything, then: buy 1000 at 5, exit 1000, buy 1000 at 7, cancel the exit
await t.sell(ADMIN, await t.bal(), 7.3);
await t.buy(ADMIN, 1000, 5);
const out = await t.sell(ADMIN, 1000, 5.5);
await t.buy(ADMIN, 1000, 7);
ok((await t.cost()) === 7, 'after the second buy on an empty account: 7');
await t.cancel('transfer', out.id);
ok((await t.bal()) === 2000 && (await t.cost()) === 6, '1000 at 7 + 1000 back at 5 = 6.00 (not 7)', String(await t.cost()));
let ev = await q(`select kind from account_cost_events where exchange_id = $1 order by created_at desc limit 1`, [A]);
ok(ev[0].kind === 'sell_cancel', 'recorded');

console.log('— cancelling an entry that was never costed leaves the cost (the reviewer\'s case)');
const db2 = await freshDb();
const u = await setup(db2, { balanceA: 1000 });       // dollars of unknown cost
const never = await u.buy(ADMIN, 1000, 7);              // not costed: no opening yet
ok((await u.cost()) === null, 'not costed');
await u.setCost(5);                                     // opening on the 2,000
await u.cancel('buy', never.id);
ok((await u.cost()) === 5, 'still 5, not 3', String(await u.cost()));

console.log('— a correction after an entry: cancelling it leaves the cost');
const db3 = await freshDb();
const w = await setup(db3, { balanceA: 1000 });
await w.setCost(7);
const b3 = await w.buy(ADMIN, 1000, 8);
ok((await w.cost()) === 7.5, '7.50');
await w.setCost(7.6);                                   // the administrator re-set it
await w.cancel('buy', b3.id);
ok((await w.cost()) === 7.6, 'kept at the corrected 7.60', String(await w.cost()));

console.log('— a costed entry cancelled: as before');
const b4 = await w.buy(ADMIN, 1000, 7.9);               // 1000 at 7.6 + 1000 at 7.9 = 7.75
ok((await w.cost()) === 7.75, '7.75');
await w.cancel('buy', b4.id);
ok((await w.cost()) === 7.6, 'back to 7.60');

console.log('— the old entry screen: the placeholder rate 1, even rounded');
const old = await t.buy(ADMIN, 100.555, 1, 100.56);
ok(old.rate === null && old.lyd_amount === null, 'stored without a rate', JSON.stringify([old.rate, old.lyd_amount]));
const r = (await as(db, ADMIN, (tx) => tx.query(`select current_exchange_rates() r`))).rows[0].r;
ok(n(r.buy) === 7, 'the last buy rate is not 1', String(r.buy));

console.log('— a rate out of range is refused (a misplaced point)');
await rejects(t.buy(ADMIN, 100, 725), 'rate_out_of_range', '725 for 7.25');
await rejects(t.sell(ADMIN, 1, 0.725), 'rate_out_of_range', '0.725 for 7.25');
await rejects(t.sell(ADMIN, 1, 1), 'rate_out_of_range', 'exactly 1');
await rejects(t.setCost(72.5 * 10), 'rate_out_of_range', 'a cost of 725');
ok(n((await t.sell(ADMIN, 1, 100)).rate) === 100, '100 is the ceiling, accepted');

console.log('— dollars are rounded before they move a balance');
const before = await t.bal();
const tiny = await t.sell(ADMIN, 0.005, 7.3);
ok(n(tiny.amount) === 0.01 && Math.abs((await t.bal()) - (before - 0.01)) < 1e-9, 'stored 0.01 and the balance moved 0.01', JSON.stringify([tiny.amount, before, await t.bal()]));

console.log('— the 1.0.6 build sends "rate_edit": it means both');
const set = await as(db, ADMIN, (tx) => tx.query(
  `select admin_set_employee_permissions(id, array['transfers_create','rate_edit']) p from sub_users where employee_name = 'موظف'`));
const perms = set.rows[0].p;
ok(perms.includes('rate_edit_sell') && perms.includes('rate_edit_buy') && !perms.includes('rate_edit'), 'mapped to both', JSON.stringify(perms));

console.log('— setting a cost needs a valid licence');
await q(`update account_licenses set status = 'expired' where user_id = $1`, [ADMIN]);
await rejects(t.setCost(7), 'license', 'refused when expired');
await q(`update account_licenses set status = 'active' where user_id = $1`, [ADMIN]);

console.log('— a backup holds the costs and a restore brings them back');
const costBefore = await t.cost();
const evBefore = (await q(`select count(*)::int k from account_cost_events`))[0].k;
const ocBefore = (await q(`select count(*)::int k from operation_costs`))[0].k;
const backup = (await q(`select _build_backup() b`))[0].b;
ok(['last_exchange_rates', 'account_costs', 'account_cost_events', 'operation_costs'].every((k) => Array.isArray(backup.tables[k]) && backup.tables[k].length > 0),
  'all four tables in the backup');
const counts = (await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_backup($1::jsonb) c`, [JSON.stringify(backup)]))).rows[0].c;
ok(counts.account_costs === 1 && counts.operation_costs === ocBefore, 'restored', JSON.stringify(counts));
ok((await t.cost()) === costBefore, 'the cost is the same after the restore', String(await t.cost()));
ok((await q(`select count(*)::int k from account_cost_events`))[0].k === evBefore, 'and its history');
ok((await q(`select count(*)::int k from last_exchange_rates`))[0].k === 2, 'and the last rates');

console.log('— an old backup (before 0081) restores without them');
const legacy = JSON.parse(JSON.stringify(backup));
for (const k of ['last_exchange_rates', 'account_costs', 'account_cost_events', 'operation_costs']) delete legacy.tables[k];
const c2 = (await as(db, PLATFORM, (tx) => tx.query(`select admin_restore_backup($1::jsonb) c`, [JSON.stringify(legacy)]))).rows[0].c;
ok(c2.account_costs === 0 && c2.exchanges === 1, 'restored, with no costs', JSON.stringify(c2));

console.log('— a deleted subscriber leaves no cost in the stored backups');
await q(`insert into backups (kind, data, size_bytes) values ('manual', $1::jsonb, 1)`, [JSON.stringify(backup)]).catch(async () => {
  await q(`insert into backups (data) values ($1::jsonb)`, [JSON.stringify(backup)]);
});
await q(`select _redact_owner_from_backups($1)`, [ADMIN]);
const left = (await q(`select data from backups order by created_at desc limit 1`))[0].data.tables;
ok(['last_exchange_rates', 'account_costs', 'account_cost_events', 'operation_costs'].every((k) => (left[k] ?? []).length === 0), 'all four redacted');

console.log('— the old files refuse to run again after this one');
for (const f of ['0081_lyd_exchange_rate.sql', '0082_account_cost.sql', '0083_rate_edit_per_kind.sql']) {
  const sql = fs.readFileSync(new URL('../migrations/' + f, import.meta.url), 'utf8');
  let msg = 'ran';
  try { await db.exec('set search_path = public, extensions;\n' + sql); } catch (e) { msg = e.message; }
  await db.exec('rollback').catch(() => {});
  ok(msg.includes('طُبّق سابقًا'), f + ' refuses', msg);
}
ok((await t.sell(ADMIN, 1, 7.3)).rate !== null, 'and the database still works as 0084 left it');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
