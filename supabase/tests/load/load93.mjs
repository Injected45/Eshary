// Load / concurrency test of the real database — ONLY on a separate, empty
// Supabase TEST project. Never production.
//
//   set LOAD_DB_URL=postgresql://postgres.<test-ref>:<password>@<host>:5432/postgres
//   node load/load93.mjs setup     # applies migrations 0001..0093 to the EMPTY test db
//   node load/load93.mjs seed      # admins, employees, accounts, customers, history
//   node load/load93.mjs run       # concurrent employees + targeted races
//   node load/load93.mjs check     # money invariants after the run
//
// Every call runs the way PostgREST runs it: role authenticated + the jwt
// claims of the admin or of the employee's anonymous session.
// Knobs: LOAD_ADMINS (10) LOAD_EMPLOYEES (5 per admin) LOAD_ACCOUNTS (4)
// LOAD_CUSTOMERS (40) LOAD_HISTORY (1500 operations per admin) LOAD_SECONDS (60)
// LOAD_POOL (40 connections).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const PROD_REF = 'ashpubvnedhkgamnipky';
const URL_ = process.env.LOAD_DB_URL ?? '';
if (!URL_) die('LOAD_DB_URL is not set (the TEST project\'s connection string).');
if (URL_.includes(PROD_REF)) die('this is the PRODUCTION project — refusing.');

const env = (k, d) => Number(process.env[k] ?? d);
const ADMINS = env('LOAD_ADMINS', 10), EMPS = env('LOAD_EMPLOYEES', 5), ACCTS = env('LOAD_ACCOUNTS', 4);
const CUSTS = env('LOAD_CUSTOMERS', 40), HISTORY = env('LOAD_HISTORY', 1500), SECONDS = env('LOAD_SECONDS', 60);
const PW = 'load-test-pw';
const MIG = fileURLToPath(new URL('../../migrations', import.meta.url));

const LOCAL = /@(localhost|127\.0\.0\.1)[:/]/.test(URL_);   // the dry run (load/local-server.mjs)
const pool = new pg.Pool({ connectionString: URL_, max: env('LOAD_POOL', 40), ssl: LOCAL ? false : { rejectUnauthorized: false } });
pg.types.setTypeParser(1700, Number);   // numeric → number (reporting only)

function die(m) { console.error('✗ ' + m); process.exit(1); }
const q = async (sql, p) => (await pool.query(sql, p)).rows;
const uuid = () => crypto.randomUUID();
const pick = (a) => a[Math.floor(Math.random() * a.length)];
const rnd = (lo, hi) => Math.round((lo + Math.random() * (hi - lo)) * 100) / 100;

// one RPC as a signed-in user, timed; returns { ok, rows, code, ms }
async function call(uid, sql, params = []) {
  const c = await pool.connect();
  const t0 = performance.now();
  try {
    await c.query('begin');
    await c.query(`set local role authenticated;
      select set_config('request.jwt.claim.sub', '${uid}', true),
             set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true)`);
    const t1 = performance.now();
    const r = await c.query(sql, params);
    const ms = performance.now() - t1;
    await c.query('commit');
    return { ok: true, rows: r.rows, ms, total: performance.now() - t0 };
  } catch (e) {
    await c.query('rollback').catch(() => {});
    return { ok: false, code: e.message.split('\n')[0].slice(0, 60), sqlstate: e.code, ms: performance.now() - t0 };
  } finally {
    c.release();
  }
}

async function isTestDb() {
  return (await q(`select to_regclass('loadtest.marker') is not null ok`))[0].ok;
}

// ------------------------------------------------------------------ setup
async function setup() {
  const n = (await q(`select count(*)::int n from information_schema.tables where table_schema = 'public'`))[0].n;
  if (n > 0 && !(await isTestDb())) die(`the database already has ${n} tables and no test marker — not an empty test project.`);
  if (await isTestDb()) die('migrations are already applied (loadtest.marker exists).');
  await q(`create schema loadtest; create table loadtest.marker (made_at timestamptz default now()); insert into loadtest.marker default values;`);
  for (const f of fs.readdirSync(MIG).filter((x) => x.endsWith('.sql')).sort()) {
    if (parseInt(f, 10) > 93) break;
    process.stdout.write(f + ' … ');
    try { await q(fs.readFileSync(path.join(MIG, f), 'utf8')); console.log('ok'); }
    catch (e) { console.log('FAILED'); die(`${f}: ${e.message}`); }
  }
  console.log('✓ migrations applied');
}

// ------------------------------------------------------------------- seed
async function seed() {
  if (!(await isTestDb())) die('not a test db (run setup first).');
  if ((await q(`select count(*)::int n from loadtest.marker where made_at is not null`))[0].n > 1) die('already seeded.');
  await q(`create table if not exists loadtest.actors (uid uuid primary key, admin uuid not null, kind text not null);
           create table if not exists loadtest.objs (id uuid primary key, admin uuid not null, kind text not null, company uuid);`);
  // Supabase's auth.users has aud/role; the dry run's simpler table has not
  const aud = (await q(`select count(*)::int n from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = 'aud'`))[0].n
    ? ", aud, role" : '';
  const audV = aud ? ", 'authenticated', 'authenticated'" : '';
  for (let a = 0; a < ADMINS; a++) {
    const admin = uuid();
    await q(`insert into auth.users (id, email, encrypted_password, raw_user_meta_data${aud})
             values ($1, $2, extensions.crypt($3, extensions.gen_salt('bf')), jsonb_build_object('full_name', $4::text)${audV})`,
            [admin, `load${a}@test.ly`, PW, `مدير ${a}`]);
    await q(`insert into account_licenses (user_id, status, license_type) values ($1, 'active', 'lifetime')
             on conflict (user_id) do update set status = 'active'`, [admin]);
    await q(`insert into loadtest.actors values ($1, $1, 'admin')`, [admin]);
    const co = (await q(`insert into companies (owner_id, name, start_ref) values ($1, $2, 'L0100') returning id`, [admin, `شركة ${a}`]))[0].id;
    const as = (sql, p) => call(admin, sql, p).then((r) => { if (!r.ok) throw new Error(`${sql.slice(0, 50)}: ${r.code}`); return r.rows; });
    await as(`select lyd_open(500000, 500000)`);
    for (let i = 0; i < ACCTS; i++) {
      const ex = (await as(`select id from admin_open_account($1, $2, 200000, null, null, 7.0, 'bank')`, [co, `حساب ${i}`]))[0].id;
      await as(`select move_between_books($1, 'bank', 100000, 7.0)`, [ex]);
      await q(`insert into loadtest.objs values ($1, $2, 'account', $3)`, [ex, admin, co]);
    }
    for (let i = 0; i < CUSTS; i++) {
      const c = (await q(`insert into clients (owner_id, name) values ($1, $2) returning id`, [admin, `زبون ${i}`]))[0].id;
      await as(`select set_customer_credit_limit($1, 50000)`, [c]);
      await q(`insert into loadtest.objs values ($1, $2, 'customer', null)`, [c, admin]);
    }
    for (let i = 0; i < EMPS; i++) {
      const anon = uuid();
      await q(`insert into auth.users (id, is_anonymous${aud}) values ($1, true${audV})`, [anon]);
      const su = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
        values ($1, $2, $3, 'x', array['transfers_create','buys_create']) returning id`,
        [admin, `موظف ${i}`, `09${String(a).padStart(3, '0')}${String(i).padStart(5, '0')}`]))[0].id;
      await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1, $2, $3)`, [su, anon, `dev-${anon}`]);
      await q(`insert into loadtest.actors values ($1, $2, 'employee')`, [anon, admin]);
    }
    // the administrator's rates of the four kinds, then history (server-side, fast)
    const accts = (await q(`select id from loadtest.objs where admin = $1 and kind = 'account'`, [admin])).map((r) => r.id);
    for (const book of ['cash', 'bank']) {
      await as(`select id from record_currency_buy($1,$2,null,null,10,7.0,null,'','${book}',null,null,'${book}')`, [co, accts[0]]);
      await as(`select id from record_transfer($1,$2,'م',null,null,10,'',7.2,'${book}',null,null,null,false,'${book}')`, [co, accts[0]]);
    }
    const t0 = performance.now();
    await q(`
      do $$
      declare i int; ex uuid; b text;
              accts uuid[] := (select array_agg(id) from loadtest.objs where admin = '${admin}' and kind = 'account');
              custs uuid[] := (select array_agg(id) from loadtest.objs where admin = '${admin}' and kind = 'customer');
      begin
        perform set_config('request.jwt.claim.sub', '${admin}', true);
        perform set_config('request.jwt.claims', '{"sub":"${admin}","role":"authenticated"}', true);
        for i in 1..${HISTORY} loop
          ex := accts[1 + floor(random() * array_length(accts, 1))];
          b := case when random() < 0.5 then 'cash' else 'bank' end;
          if i % 2 = 0 then
            perform record_currency_buy('${co}', ex, null, null, round((50 + random() * 900)::numeric, 2),
              round((6.9 + random() * 0.2)::numeric, 4), null, '', b, null, null, b);
          elsif i % 7 = 0 then
            perform record_transfer('${co}', ex, 'م', null, null, round((50 + random() * 400)::numeric, 2), '',
              round((7.1 + random() * 0.2)::numeric, 4), b, null,
              custs[1 + floor(random() * array_length(custs, 1))], 0, false, b);
          else
            perform record_transfer('${co}', ex, 'م', null, null, round((50 + random() * 900)::numeric, 2), '',
              round((7.1 + random() * 0.2)::numeric, 4), b, null, null, null, false, b);
          end if;
        end loop;
      end $$;`);
    console.log(`admin ${a}: ${ACCTS} accounts, ${CUSTS} customers, ${EMPS} employees, ${HISTORY} operations (${((performance.now() - t0) / 1000).toFixed(1)} s)`);
  }
  await q(`insert into loadtest.marker default values`);
  console.log('✓ seeded');
}

// -------------------------------------------------------------------- run
const stats = {};
function rec(name, r) {
  const s = (stats[name] ??= { ms: [], errors: {} });
  if (r.ok) s.ms.push(r.ms); else s.errors[r.code] = (s.errors[r.code] ?? 0) + 1;
}
// refusals that are the rules working, not failures
const EXPECTED = /insufficient_balance|book_insufficient|credit_limit|over_limit|not_found|already|same_day|nothing_to/;

async function world(admin) {
  const co = (await q(`select company from loadtest.objs where admin = $1 and kind = 'account' limit 1`, [admin]))[0].company;
  const accts = (await q(`select id from loadtest.objs where admin = $1 and kind = 'account'`, [admin])).map((r) => r.id);
  const custs = (await q(`select id from loadtest.objs where admin = $1 and kind = 'customer'`, [admin])).map((r) => r.id);
  const emps = (await q(`select uid from loadtest.actors where admin = $1 and kind = 'employee'`, [admin])).map((r) => r.uid);
  return { admin, co, accts, custs, emps };
}

const sale = (uid, w, o = {}) => {
  const book = o.book ?? pick(['cash', 'bank']);
  const credit = o.customer !== undefined;
  return call(uid, `select id, reference from record_transfer($1,$2,'م',null,null,$3,'',$4,$5,$6,$7,$8,false,$9)`,
    [w.co, o.ex ?? pick(w.accts), o.usd ?? rnd(20, 600), 7.2, book, o.rid ?? uuid(),
     credit ? o.customer : null, credit ? 0 : null, book]);
};
const buy = (uid, w, o = {}) => {
  const book = o.book ?? pick(['cash', 'bank']);
  return call(uid, `select id from record_currency_buy($1,$2,null,null,$3,7.0,null,'',$4,$5,null,$6)`,
    [w.co, o.ex ?? pick(w.accts), o.usd ?? rnd(20, 600), book, o.rid ?? uuid(), book]);
};

async function employeeLoop(uid, w, until) {
  while (Date.now() < until) {
    const x = Math.random();
    if (x < 0.5) rec('sale (employee)', await sale(uid, w));
    else if (x < 0.8) rec('purchase (employee)', await buy(uid, w));
    else if (x < 0.85) rec('credit sale (employee)', await sale(uid, w, { customer: pick(w.custs), usd: rnd(10, 100) }));
    else if (x < 0.95) {
      rec('today list', await call(uid, `select id, amount, reference, created_at from transfers
        where status = 'archived' and created_at >= date_trunc('day', now() at time zone 'Africa/Tripoli') at time zone 'Africa/Tripoli'
        order by created_at desc limit 200`));
    } else {
      // a retry storm: the same request sent three times at once
      const rid = uuid();
      const rs = await Promise.all([0, 1, 2].map(() => sale(uid, w, { rid, ex: w.accts[0], book: 'bank', usd: 25 })));
      const ids = new Set(rs.filter((r) => r.ok).map((r) => r.rows[0].id));
      rec('retry ×3 same id', rs.every((r) => r.ok) && ids.size === 1 ? rs[0] : { ok: false, code: `retry: ${ids.size} rows, ${rs.filter((r) => !r.ok).map((r) => r.code).join(',')}` });
    }
  }
}

async function adminLoop(w, until) {
  const a = w.admin;
  while (Date.now() < until) {
    const x = Math.random();
    if (x < 0.2) rec('sale (admin)', await sale(a, w));
    else if (x < 0.35) rec('purchase (admin)', await buy(a, w));
    else if (x < 0.45) rec('customer collect', await call(a, `select customer_add_entry($1,'collect',$2,$3,null,$4,$3)`, [pick(w.custs), rnd(5, 50), pick(['cash', 'bank']), uuid()]));
    else if (x < 0.55) rec('treasury_positions', await call(a, `select treasury_positions()`));
    else if (x < 0.62) rec('customer_balances', await call(a, `select customer_balances()`));
    else if (x < 0.67) rec('account_books_list', await call(a, `select account_books_list()`));
    else if (x < 0.72) rec('trial balance', await call(a, `select ledger_trial_balance(now(), null, 1)`));
    else if (x < 0.77) rec('lyd_summary', await call(a, `select lyd_summary(now() - interval '1 day', now())`));
    else if (x < 0.85) rec('move between books', await call(a, `select move_between_books($1, $2, $3, 7.0)`, [pick(w.accts), pick(['cash', 'bank']), rnd(1, 50)]));
    else if (x < 0.92) {
      const t = await q(`select id from transfers where owner_id = $1 and cancelled_at is null
                          and created_at > now() - interval '10 minutes' order by random() limit 1`, [a]);
      if (t.length) rec('cancel sale (admin)', await call(a, `select admin_cancel_operation('transfer', $1, 'اختبار', $2)`, [t[0].id, PW]));
    } else {
      rec('lyd movement', await call(a, `select lyd_add_movement('cash_to_bank', null, $1)`, [rnd(10, 200)]));
    }
  }
}

// targeted races on admin 0
async function races(w) {
  console.log('\n— races');
  const bad = [];
  // 1. over-selling one book: 1,000 $ in its cash book, 30 sales of 50 at once
  const ex = (await call(w.admin, `select id from admin_open_account($1, $2, 1000, null, null, 7.0, 'cash')`, [w.co, 'سباق ' + Date.now()])).rows[0].id;
  let rs = await Promise.all(Array.from({ length: 30 }, (_, i) => sale(w.emps[i % w.emps.length], w, { ex, book: 'cash', usd: 50 })));
  const okN = rs.filter((r) => r.ok).length;
  const bal = (await q(`select balance from account_books where exchange_id = $1 and book = 'cash'`, [ex]))[0].balance;
  console.log(`  over-sell: ${okN} of 30 saved, book left ${bal} (want 20 and 0); refusals: ${[...new Set(rs.filter((r) => !r.ok).map((r) => r.code))]}`);
  if (okN !== 20 || bal !== 0) bad.push('over-sell');
  // 2. credit limit: limit 1,000 LYD, 20 credit sales of 100 LYD (13.89 $ × 7.2) at once
  const c = (await q(`insert into clients (owner_id, name) values ($1, 'سباق الحد') returning id`, [w.admin]))[0].id;
  await call(w.admin, `select set_customer_credit_limit($1, 1000)`, [c]);
  const before = (await call(w.admin, `select customer_balances() r`)).rows[0].r.find((x) => x.client_id === c);
  const owed0 = before ? Number(before.balance) : 0;
  rs = await Promise.all(Array.from({ length: 20 }, (_, i) => sale(w.emps[i % w.emps.length], w, { customer: c, usd: 13.89, ex: w.accts[1] })));
  const after = (await call(w.admin, `select customer_balances() r`)).rows[0].r.find((x) => x.client_id === c);
  console.log(`  credit limit: owed ${owed0} → cash ${after?.balance_cash} + bank ${after?.balance_bank}, ${rs.filter((r) => r.ok).length} saved (limit 1,000); refusals: ${[...new Set(rs.filter((r) => !r.ok).map((r) => r.code))]}`);
  // one limit over both books (0094)
  if (Number(after?.balance ?? 0) > 1000.01 || !rs.some((r) => r.ok)) bad.push('credit limit');
  // 3. one request id ten times at once
  const rid = uuid();
  rs = await Promise.all(Array.from({ length: 10 }, () => buy(w.emps[0], w, { rid, usd: 33.33, book: 'cash' })));
  const n = (await q(`select count(*)::int n from currency_buys where request_id = $1`, [rid]))[0].n;
  console.log(`  same request ×10: ${n} row(s), ${rs.filter((r) => !r.ok).length} errors ${[...new Set(rs.filter((r) => !r.ok).map((r) => r.code))]}`);
  if (n !== 1 || rs.some((r) => !r.ok)) bad.push('idempotency');
  // 4. crossing locks: moves both ways + sales + an adjustment on one account
  const ex2 = w.accts[2];
  rs = await Promise.all([
    ...Array.from({ length: 10 }, (_, i) => call(w.admin, `select move_between_books($1, $2, 5, 7.0)`, [ex2, i % 2 ? 'cash' : 'bank'])),
    ...Array.from({ length: 10 }, (_, i) => sale(w.emps[i % w.emps.length], w, { ex: ex2, usd: 5 })),
    ...Array.from({ length: 10 }, (_, i) => buy(w.emps[i % w.emps.length], w, { ex: ex2, usd: 5 })),
  ]);
  const dl = rs.filter((r) => r.sqlstate === '40P01' || /deadlock/.test(r.code ?? ''));
  console.log(`  crossing locks: ${rs.filter((r) => r.ok).length}/30 ok, deadlocks ${dl.length}, other ${[...new Set(rs.filter((r) => !r.ok).map((r) => r.code))]}`);
  if (dl.length) bad.push('deadlock');
  return bad;
}

function pct(a, p) { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))] : 0; }

async function run() {
  if (!(await isTestDb())) die('not a test db.');
  const admins = (await q(`select uid from loadtest.actors where kind = 'admin'`)).map((r) => r.uid);
  if (!admins.length) die('seed first.');
  const worlds = await Promise.all(admins.map(world));
  const until = Date.now() + SECONDS * 1000;
  console.log(`— ${worlds.length} admins + ${worlds.reduce((s, w) => s + w.emps.length, 0)} employees for ${SECONDS} s`);
  const t0 = Date.now();
  await Promise.all(worlds.flatMap((w) => [adminLoop(w, until), ...w.emps.map((e) => employeeLoop(e, w, until))]));
  const secs = (Date.now() - t0) / 1000;
  let all = 0, unexpected = 0;
  console.log('\ncall                         n   p50 ms  p95 ms  p99 ms  errors');
  for (const [k, s] of Object.entries(stats).sort()) {
    all += s.ms.length;
    const errs = Object.entries(s.errors).map(([c, n]) => { if (!EXPECTED.test(c)) unexpected += n; return `${c}×${n}`; }).join(' ');
    console.log(`${k.padEnd(26)} ${String(s.ms.length).padStart(5)} ${pct(s.ms, 0.5).toFixed(0).padStart(7)} ${pct(s.ms, 0.95).toFixed(0).padStart(7)} ${pct(s.ms, 0.99).toFixed(0).padStart(7)}  ${errs}`);
  }
  console.log(`\n${all} calls in ${secs.toFixed(0)} s = ${(all / secs).toFixed(1)}/s; unexpected errors: ${unexpected}`);
  const bad = await races(worlds[0]);
  console.log(bad.length ? `\n✗ races failed: ${bad.join(', ')}` : '\n✓ races hold');
  await check();
}

// ------------------------------------------------------------------ check
async function check() {
  if (!(await isTestDb())) die('not a test db.');
  console.log('\n— invariants');
  const fails = [];
  const t = (cond, label, extra = '') => { if (!cond) fails.push(label); console.log(`  ${cond ? '✓' : '✗'} ${label}${cond ? '' : ' ' + extra}`); };
  const split = await q(`select e.id from exchanges e left join account_books b on b.exchange_id = e.id
                          group by e.id, e.balance having e.balance <> coalesce(sum(b.balance), 0) or count(b.*) <> 2`);
  t(split.length === 0, 'every account = cash book + bank book', JSON.stringify(split.slice(0, 3)));
  const neg = await q(`select exchange_id, book, balance from account_books where balance < 0`);
  t(neg.length === 0, 'no book below zero', JSON.stringify(neg.slice(0, 3)));
  for (const tb of ['transfers', 'currency_buys']) {
    const d = await q(`select request_id, count(*) from ${tb} where request_id is not null group by owner_id, request_id having count(*) > 1`);
    t(d.length === 0, `${tb}: one row per request id`, JSON.stringify(d.slice(0, 3)));
  }
  const refs = await q(`select owner_id, reference, count(*) from transfers where cancelled_at is null
                         group by owner_id, reference having count(*) > 1`);
  t(refs.length === 0, 'no two active sales share a reference', JSON.stringify(refs.slice(0, 3)));
  const lim = await q(`select c.id, c.credit_limit, sum(e.amount) owed from clients c join customer_lyd_entries e on e.client_id = c.id
                        where c.credit_limit is not null group by c.id, c.credit_limit having sum(e.amount) > c.credit_limit + 0.01`);
  t(lim.length === 0, 'no customer above the limit (both books together)', JSON.stringify(lim.slice(0, 3)));
  for (const { uid } of await q(`select uid from loadtest.actors where kind = 'admin'`)) {
    const tb = (await call(uid, `select ledger_trial_balance(now(), null, 1) r`)).rows?.[0]?.r ?? [];
    const dr = tb.reduce((s, l) => s + Number(l.debit), 0), cr = tb.reduce((s, l) => s + Number(l.credit), 0);
    const J = await q(`select source, source_id, at, book, account, exchange_id, amount from _journal($1)`, [uid]);
    const by = {}, atCost = {};
    for (const l of J) {
      const k = `${l.source}|${l.source_id}|${+l.at}|${l.book}`;
      by[k] = (by[k] ?? 0) + Number(l.amount);
      if (l.account === '1300') atCost[`${l.exchange_id}|${l.book}`] = (atCost[`${l.exchange_id}|${l.book}`] ?? 0) + Number(l.amount);
    }
    const off = Object.entries(by).filter(([, v]) => Math.abs(v) > 0.0001);
    t(Math.abs(dr - cr) < 0.01 && off.length === 0, `admin ${uid.slice(0, 8)}: trial balance ${dr.toFixed(2)} = ${cr.toFixed(2)}, every entry balanced per book`, JSON.stringify(off.slice(0, 2)));
    const offC = (await q(`select exchange_id, book, balance * cost_rate want from account_books where owner_id = $1 and cost_rate is not null`, [uid]))
      // each operation is posted rounded to the dirham: allow that drift (≈ 1 dirham per 10,000 dinars)
      .filter((r) => Math.abs(Number(r.want) - (atCost[`${r.exchange_id}|${r.book}`] ?? 0)) > 0.05 + Math.abs(Number(r.want)) * 1e-6);
    t(offC.length === 0, `admin ${uid.slice(0, 8)}: dollars at cost (1300) = balance × cost in each book`, JSON.stringify(offC.slice(0, 2)));
  }
  console.log(fails.length ? `\n✗ ${fails.length} invariant(s) broken` : '\n✓ all invariants hold');
  if (fails.length) process.exitCode = 1;
}

const cmd = process.argv[2];
try {
  if (cmd === 'setup') await setup();
  else if (cmd === 'seed') await seed();
  else if (cmd === 'run') await run();
  else if (cmd === 'check') await check();
  else die('usage: node load/load93.mjs setup|seed|run|check');
} finally {
  await pool.end();
}
