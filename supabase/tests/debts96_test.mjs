// 0096: «كشف المديونيات» — both sides with the same details: the code, the
// cash and bank parts, the ageing (oldest settled first), the last
// settlement and the last movement.
import { freshDb, as } from './harness.mjs';
import fs from 'node:fs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
const near = (a, b, eps = 0.011) => Math.abs(Number(a) - Number(b)) <= eps;
const ADMIN = '11111111-1111-1111-1111-111111111111';

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email) values ('${ADMIN}', 'a@x.ly');
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';`);
const SQL96 = fs.readFileSync(new URL('../migrations/0096_debts_list.sql', import.meta.url), 'utf8');
await db.exec('set search_path = public, extensions;\n' + SQL96);
ok(true, '0096 runs again');
{
  let msg = 'ran';
  try { await db.exec('set search_path = public, extensions;\n' + fs.readFileSync(new URL('../migrations/0095_reports.sql', import.meta.url), 'utf8')); }
  catch (e) { msg = e.message; await db.exec('rollback'); }
  ok(msg.includes('لا تشغّله'), '0095 refuses to run after 0096', msg);
}
const adm = (sql, p = []) => as(db, ADMIN, (tx) => tx.query(sql, p)).then((r) => r.rows);
const client = async (name, code) => (await q(`insert into clients (owner_id, name, company, code) values ($1,$2,'أنزار',$3) returning id`, [ADMIN, name, code]))[0].id;
const entry = (c, kind, amount, book, daysAgo) => q(
  `insert into customer_lyd_entries (owner_id, client_id, kind, amount, book, created_at)
   values ($1,$2,$3,$4,$5, now() - make_interval(days => $6))`, [ADMIN, c, kind, amount, book, daysAgo]);

// a debtor: 300 cash 40 days ago, 196 bank 2 days ago; collected 300 → 196 this week
const K = await client('كريم', '5521');
await entry(K, 'opening', 300, 'cash', 40);
await entry(K, 'sale', 196, 'bank', 2);
await entry(K, 'collect', -300, 'cash', 1);
// a creditor: we owed 200 for 40 days and 50 since today; we paid 120 → 130:
// the old 200 is paid first (120), 80 of it is still 40 days old, 50 is new
const S = await client('بائع', '7000');
await entry(S, 'opening', -200, 'cash', 40);
await entry(S, 'buy', -50, 'bank', 0);
await entry(S, 'pay', 120, 'cash', 3);
// an old debt over the limit: 50 for 100 days, limit 10
const M = await client('منير', '6100');
await q(`update clients set credit_limit = 10 where id = $1`, [M]);
await entry(M, 'opening', 50, 'bank', 100);
// settled: not listed
const Z = await client('صفر', null);
await entry(Z, 'sale', 100, 'cash', 5);
await entry(Z, 'collect', -100, 'cash', 4);

const r = (await adm(`select report_debt_aging() r`))[0].r;
const k = r.debtors.find((x) => x.client_id === K);
const s = r.creditors.find((x) => x.client_id === S);
ok(k && k.code === '5521' && near(k.owed, 196) && near(k.d7, 196) && near(k.cash, 0) && near(k.bank, 196),
  'debtor: 196 owed this week, all in the bank book, with his code', JSON.stringify(k));
ok(k && k.last_settle && k.last_collect && k.last_move, 'debtor: last collection and last movement');
ok(s && s.code === '7000' && near(s.owed, 130) && near(s.d7, 50) && near(s.d90, 80),
  'creditor: 130 owed — 50 new and 80 of the 40-day-old debt', JSON.stringify(s));
ok(s && near(s.cash, 80) && near(s.bank, 50), 'creditor: 80 cash + 50 bank');
ok(s && s.last_settle && new Date(s.oldest) < new Date(Date.now() - 39 * 864e5), 'creditor: last payment, oldest open debt 40 days');
const m = r.debtors.find((x) => x.client_id === M);
ok(m && near(m.older, 50) && m.over_limit === true && r.debtors[0].client_id === M, 'the oldest debt first, over its limit', JSON.stringify(m));
ok(m && m.last_settle === null, 'never collected');
ok(!r.debtors.some((x) => x.client_id === Z) && !r.creditors.some((x) => x.client_id === Z), 'a settled customer is not listed');
const bal = (await adm(`select customer_balances() r`))[0].r;
ok(near(-bal.find((x) => x.client_id === S).balance, s.owed) && near(bal.find((x) => x.client_id === K).balance, k.owed),
  'both = customer_balances');

if (process.env.WRITE_FIXTURES) {
  fs.writeFileSync(new URL('../../test/fixtures/debt_aging.json', import.meta.url), JSON.stringify(r, null, 1));
  console.log('fixture written');
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
