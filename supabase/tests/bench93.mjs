// Performance benchmark of the database functions at 0093, at a realistic
// volume. NOT a test (no pass/fail): it seeds, times, explains and prints.
//
//   cd supabase/tests && node bench93.mjs
//
// Environment:
//   BENCH_N        sales per year of the main administrator (= purchases), default 20000
//   BENCH_OTHERS   other administrators (each with BENCH_N / 5 of each), default 5
//   BENCH_EXPLAIN  1 (default): profile + auto_explain every call slower than 100 ms
//   BENCH_SCRATCH  1 (default): apply the candidate fixes to THIS in-memory copy
//                  and time the affected calls again (the migrations are never touched)
//   BENCH_OUT      directory for the JSON result and the plans, default the OS temp dir
//   BENCH_UPTO     last migration applied, default 93 (what this benchmark measures)
//
// The bulk history is inserted directly (as the superuser, triggers off) with
// balances, books and weighted-average costs simulated exactly as the save
// functions compute them; then every timed call goes through the real RPCs as
// the authenticated administrator (and the employee where the app does that).
// The database is built like harness.freshDb (same roles and stubs), plus the
// auto_explain module so the plans of statements nested in functions show.
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import { auto_explain } from '@electric-sql/pglite/contrib/auto_explain';
import { as } from './harness.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';

const N = Number(process.env.BENCH_N ?? 20000);
const OTHERS = Number(process.env.BENCH_OTHERS ?? 5);
const EXPLAIN = (process.env.BENCH_EXPLAIN ?? '1') !== '0';
const SCRATCH = (process.env.BENCH_SCRATCH ?? '1') !== '0';
const OUT = process.env.BENCH_OUT ?? os.tmpdir();
const UPTO = Number(process.env.BENCH_UPTO ?? 93);
const SLOW_MS = 100;
const T_START = performance.now();
for (const ev of ['unhandledRejection', 'uncaughtException']) process.on(ev, (e) => {
  console.error('FAILED:', e?.message ?? e, e?.query ? `\n  in: ${String(e.query).slice(0, 300)}` : '');
  process.exit(1);
});
const log = (...a) => console.log(`[${((performance.now() - T_START) / 1000).toFixed(1)}s]`, ...a);

// ------------------------------------------------------------------ the database
const MIG = fileURLToPath(new URL('../migrations', import.meta.url));
async function benchDb() {
  const db = new PGlite({ extensions: { pgcrypto, uuid_ossp, auto_explain } });
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create role supabase_auth_admin nologin;
    create schema extensions;
    create extension pgcrypto schema extensions;
    create extension "uuid-ossp" schema extensions;
    alter database template1 set search_path = public, extensions;
    set search_path = public, extensions;
    create schema auth;
    create table auth.users (
      id uuid primary key default extensions.gen_random_uuid(),
      email text, phone text,
      encrypted_password text,
      raw_user_meta_data jsonb default '{}'::jsonb,
      raw_app_meta_data jsonb default '{}'::jsonb,
      is_anonymous boolean default false,
      email_confirmed_at timestamptz, last_sign_in_at timestamptz,
      created_at timestamptz default now(), updated_at timestamptz default now()
    );
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.role() returns text language sql stable as
      $$ select current_setting('request.jwt.claim.role', true) $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth, extensions, public to anon, authenticated, service_role;
    create schema net;
    create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
      headers jsonb default '{}', timeout_milliseconds int default 1000) returns bigint
      language sql as $$ select 1::bigint $$;
    create table net._http_response (id bigint primary key, status_code int, error_msg text);
    create publication supabase_realtime;
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  `);
  for (const f of fs.readdirSync(MIG).filter((x) => x.endsWith('.sql') && parseInt(x.slice(0, 4), 10) <= UPTO).sort()) {
    const sql = fs.readFileSync(path.join(MIG, f), 'utf8')
      .replace(/create extension if not exists pg_net;/g, '')
      .replace(/create extension if not exists pgcrypto;/g, '');
    try { await db.exec('set search_path = public, extensions;\n' + sql); }
    catch (e) { throw new Error(`${f}: ${e.message}`); }
  }
  await db.exec(`load 'auto_explain'; set auto_explain.log_min_duration = -1;`);
  return db;
}

// ------------------------------------------------------------------ helpers
function rngFrom(seed) {               // mulberry32: the same data on every run
  return () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const DAY = 86400000;
const r4 = (x) => Math.round(x * 1e4) / 1e4;
const r6 = (x) => Math.round(x * 1e6) / 1e6;
const money = (c) => (c / 100).toFixed(2);           // cents → numeric text
const iso = (ms) => new Date(ms).toISOString();
const NOW = Date.now();
// the Libya day (UTC+2, no summer time) as lib/shared/libya_time.dart has it
const LIBYA_OFF = 2 * 3600000;
const DAY_START = Math.floor((NOW + LIBYA_OFF) / DAY) * DAY - LIBYA_OFF;
const YEAR_START = DAY_START - 364 * DAY;

async function bulkInsert(db, table, rows) {
  if (!rows.length) return;
  const cols = Object.keys(rows[0]);
  const per = Math.max(1, Math.floor(30000 / cols.length));
  for (let i = 0; i < rows.length; i += per) {
    const chunk = rows.slice(i, i + per);
    const params = [];
    const values = chunk.map((r) => '(' + cols.map((c) => { params.push(r[c]); return '$' + params.length; }).join(',') + ')');
    await db.query(`insert into ${table} (${cols.join(',')}) values ${values.join(',')}`, params);
  }
}

// ------------------------------------------------------------------ the market
// cash and bank rates move slowly over the year; a bank dollar costs more dinars
function market(rng) {
  const sellCash = (t) => r4(7.1 + 0.35 * Math.sin(((t - YEAR_START) / DAY) / 58) + 0.04 * (rng() - 0.5));
  return {
    sell: (book, t) => (book === 'cash' ? sellCash(t) : r4(sellCash(t) * 1.09)),
    buy: (book, t) => (book === 'cash' ? r4(sellCash(t) - 0.05 - 0.1 * rng()) : r4(sellCash(t) * 1.09 - 0.05 - 0.1 * rng())),
  };
}

// ------------------------------------------------------------------ one administrator's year
// Simulates the save functions (0093) in time order and returns the rows.
function simulate({ owner, company, companyName, accounts, customers, nKind, emp, refStart, seed }) {
  const rng = rngFrom(seed);
  const mk = market(rng);
  const pick = (a) => a[Math.floor(rng() * a.length)];
  const rows = { transfers: [], currency_buys: [], operation_costs: [], account_cost_events: [],
    customer_lyd_entries: [], lyd_movements: [], balance_adjustments: [], book_transfers: [],
    account_expenses: [], operation_cancellations: [] };
  const total = (a) => a.books.cash.bal + a.books.bank.bal;
  const counts = { sale: nKind, buy: nKind, collect: Math.round(nKind * 0.03), pay: Math.round(nKind * 0.015),
    lyd: Math.round(nKind * 0.01), adjust: Math.max(3, Math.round(nKind * 0.002)),
    move: Math.max(3, Math.round(nKind * 0.001)), expense: Math.max(3, Math.round(nKind * 0.002)) };
  const kinds = [];
  for (const [k, c] of Object.entries(counts)) for (let i = 0; i < c; i++) kinds.push(k);
  for (let i = kinds.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [kinds[i], kinds[j]] = [kinds[j], kinds[i]]; }
  // 1/365 of everything happens today (before now), the rest over the year
  const todayEnd = Math.max(DAY_START + 1000, NOW - 120000);
  const times = kinds.map(() => (rng() < 1 / 365
    ? DAY_START + rng() * (todayEnd - DAY_START)
    : YEAR_START + rng() * (DAY_START - YEAR_START))).sort((a, b) => a - b);
  let ref = refStart;
  const custBal = new Map(customers.map((c) => [c, { cash: 0, bank: 0 }]));
  const custWithLimit = customers.slice(0, Math.ceil(customers.length * 0.6));
  let lastRates = {};

  const cancelRow = (kind, op, a, amount, party, at, cAt, empId, before, after) => rows.operation_cancellations.push({
    id: randomUUID(), owner_id: owner, kind, operation_id: op, company_id: company, exchange_id: a.id,
    company_name: companyName, exchange_name: a.name, exchange_code: null, amount: money(amount),
    reference: kind === 'transfer' ? party.ref : '', party_name: party.name, operation_created_at: iso(at),
    operation_employee_id: empId, operation_employee_name: empId ? 'موظف' : 'المدير', reason: 'خطأ في الإدخال',
    balance_before: money(before), balance_after: money(after), cancelled_by: owner, cancelled_by_name: 'المدير',
    cancelled_at: iso(cAt) });

  for (let i = 0; i < kinds.length; i++) {
    const kind = kinds[i];
    const at = times[i];
    const cAt = Math.min(at + 120000, NOW - 30000);
    const empId = emp && rng() < 0.3 ? emp : null;
    if (kind === 'sale') {
      let amount = Math.round((50 + 4950 * rng() ** 2) * 100);
      let a = pick(accounts);
      let book = rng() < 0.5 ? 'cash' : 'bank';
      if (a.books[book].bal < amount) {
        const alt = accounts.flatMap((x) => ['cash', 'bank'].map((b) => [x, b])).find(([x, b]) => x.books[b].bal >= amount);
        if (alt) [a, book] = alt;
        else continue;
      }
      const B = a.books[book];
      const rate = mk.sell(book, at);
      lastRates[`sell_${book}`] = rate;
      const lyd = Math.round(amount * Math.round(rate * 1e4) / 1e4);
      const r = rng();
      const paid = r < 0.85 ? lyd : r < 0.95 ? 0 : Math.round(lyd * (0.3 + 0.4 * rng()));
      const customer = paid < lyd || rng() < 0.2 ? pick(paid < lyd ? custWithLimit : customers) : null;
      const id = randomUUID();
      const reference = 'Rh' + String(ref++).padStart(4, '0');
      rows.transfers.push({ id, owner_id: owner, company_id: company, exchange_id: a.id,
        beneficiary_name: 'مستفيد ' + (i % 997), beneficiary_account_company: null, beneficiary_code: null,
        amount: money(amount), reference, status: 'archived', created_at: iso(at), archived_at: iso(at),
        created_by_employee_id: empId, cancelled_at: null, rate: rate.toFixed(4), lyd_amount: money(lyd),
        lyd_method: paid > 0 ? book : null, request_id: randomUUID(), customer_id: customer,
        lyd_paid: money(paid), book });
      const cost = B.cost;
      if (cost !== null) rows.operation_costs.push({ operation_id: id, kind: 'sell', owner_id: owner,
        exchange_id: a.id, cost_before: cost.toFixed(6), cost_after: cost.toFixed(6), created_at: iso(at), book });
      if (lyd - paid > 0) {
        rows.customer_lyd_entries.push({ id: randomUUID(), owner_id: owner, client_id: customer, kind: 'sale',
          amount: money(lyd - paid), pocket: null, operation_id: id, note: null, request_id: null,
          created_by_employee_id: empId, created_at: iso(at), book });
        custBal.get(customer)[book] += lyd - paid;
      }
      const before = total(a);
      B.bal -= amount;
      if (rng() < 0.03) {                                    // cancelled the same day
        const tr = rows.transfers[rows.transfers.length - 1];
        tr.cancelled_at = iso(cAt);
        B.bal += amount;
        if (lyd - paid > 0) {
          rows.customer_lyd_entries.push({ id: randomUUID(), owner_id: owner, client_id: customer, kind: 'sale_cancel',
            amount: money(-(lyd - paid)), pocket: null, operation_id: id, note: null, request_id: null,
            created_by_employee_id: null, created_at: iso(cAt), book });
          custBal.get(customer)[book] -= lyd - paid;
        }
        // _cost_on_sell_cancel
        if (cost !== null && B.cost !== null && B.bal > 0) {
          const q = amount / 100, vb = B.bal / 100, vbefore = vb - q;
          const nc = vbefore < 1 ? r6(cost) : r6((vbefore * B.cost + q * cost) / vb);
          if (nc !== B.cost) {
            rows.account_cost_events.push({ id: randomUUID(), owner_id: owner, exchange_id: a.id, kind: 'sell_cancel',
              operation_id: id, balance_before: vbefore.toFixed(2), cost_before: B.cost.toFixed(6), usd_amount: q.toFixed(2),
              rate: cost.toFixed(6), balance_after: vb.toFixed(2), cost_after: nc.toFixed(6), created_at: iso(cAt), book });
            B.cost = nc;
          }
        }
        cancelRow('transfer', id, a, amount, { ref: reference, name: 'مستفيد' }, at, cAt, empId, before - amount, before);
      }
    } else if (kind === 'buy') {
      const amount = Math.round((50 + 5600 * rng() ** 2) * 100);
      const a = pick(accounts);
      const book = rng() < 0.5 ? 'cash' : 'bank';
      const B = a.books[book];
      const rate = mk.buy(book, at);
      lastRates[`buy_${book}`] = rate;
      const lyd = Math.round(amount * Math.round(rate * 1e4) / 1e4);
      const partial = rng() < 0.1;
      const paid = partial ? Math.round(lyd * (0.2 + 0.6 * rng())) : lyd;
      const client = partial || rng() < 0.4 ? pick(customers) : null;
      const id = randomUUID();
      const q = amount / 100, vb = B.bal / 100;
      const cBefore = B.cost;
      let cAfter;
      if (vb <= 0) cAfter = r6(rate);
      else if (cBefore === null) cAfter = null;
      else cAfter = r6((vb * cBefore + q * rate) / (vb + q));
      if (cAfter !== null) {
        rows.account_cost_events.push({ id: randomUUID(), owner_id: owner, exchange_id: a.id, kind: 'buy', operation_id: id,
          balance_before: vb.toFixed(2), cost_before: cBefore === null ? null : cBefore.toFixed(6), usd_amount: q.toFixed(2),
          rate: rate.toFixed(4), balance_after: (vb + q).toFixed(2), cost_after: cAfter.toFixed(6), created_at: iso(at), book });
        rows.operation_costs.push({ operation_id: id, kind: 'buy', owner_id: owner, exchange_id: a.id,
          cost_before: cBefore === null ? null : cBefore.toFixed(6), cost_after: cAfter.toFixed(6), created_at: iso(at), book });
        B.cost = cAfter;
      }
      rows.currency_buys.push({ id, owner_id: owner, my_company_id: company, exchange_id: a.id, client_id: client,
        client_from_account: client ? null : 'بائع ' + (i % 389), usd_amount: money(amount), rate: rate.toFixed(4),
        lyd_amount: money(lyd), status: 'archived', created_at: iso(at), archived_at: iso(at), reference: '',
        created_by_employee_id: empId, cancelled_at: null, lyd_method: paid > 0 ? book : null,
        request_id: randomUUID(), lyd_paid: money(paid), book });
      if (lyd - paid > 0) {
        rows.customer_lyd_entries.push({ id: randomUUID(), owner_id: owner, client_id: client, kind: 'buy',
          amount: money(-(lyd - paid)), pocket: null, operation_id: id, note: null, request_id: null,
          created_by_employee_id: empId, created_at: iso(at), book });
        custBal.get(client)[book] -= lyd - paid;
      }
      const before = total(a);
      B.bal += amount;
      if (rng() < 0.03 && cAfter !== null) {
        const bu = rows.currency_buys[rows.currency_buys.length - 1];
        bu.cancelled_at = iso(cAt);
        B.bal -= amount;
        if (lyd - paid > 0) {
          rows.customer_lyd_entries.push({ id: randomUUID(), owner_id: owner, client_id: client, kind: 'buy_cancel',
            amount: money(lyd - paid), pocket: null, operation_id: id, note: null, request_id: null,
            created_by_employee_id: null, created_at: iso(cAt), book });
          custBal.get(client)[book] += lyd - paid;
        }
        // _cost_on_buy_cancel
        const vbal = B.bal / 100;
        const value = (vbal + q) * B.cost - q * rate;
        const nc = vbal < 1 || value <= 0 ? B.cost : r6(value / vbal);
        rows.account_cost_events.push({ id: randomUUID(), owner_id: owner, exchange_id: a.id, kind: 'buy_cancel', operation_id: id,
          balance_before: (vbal + q).toFixed(2), cost_before: B.cost.toFixed(6), usd_amount: q.toFixed(2), rate: rate.toFixed(4),
          balance_after: vbal.toFixed(2), cost_after: nc.toFixed(6), created_at: iso(cAt), book });
        B.cost = nc;
        cancelRow('buy', id, a, amount, { name: 'بائع' }, at, cAt, empId, before + amount, before);
      }
    } else if (kind === 'collect' || kind === 'pay') {
      const want = kind === 'collect' ? 1 : -1;
      let found = null;
      for (let k = 0; k < 20 && !found; k++) {
        const c = pick(customers);
        const book = rng() < 0.5 ? 'cash' : 'bank';
        if (custBal.get(c)[book] * want > 0) found = [c, book];
      }
      if (!found) continue;
      const [c, book] = found;
      const amt = Math.max(1, Math.round(Math.abs(custBal.get(c)[book]) * (0.3 + 0.7 * rng())));
      rows.customer_lyd_entries.push({ id: randomUUID(), owner_id: owner, client_id: c, kind,
        amount: money(-want * amt), pocket: book, operation_id: null, note: null, request_id: randomUUID(),
        created_by_employee_id: null, created_at: iso(at), book });
      custBal.get(c)[book] -= want * amt;
    } else if (kind === 'lyd') {
      const r = rng();
      const k = r < 0.4 ? 'in' : r < 0.7 ? 'out' : r < 0.85 ? 'cash_to_bank' : 'bank_to_cash';
      const amount = Math.round((1000 + 49000 * rng()) * 100);
      const conv = k === 'cash_to_bank' || k === 'bank_to_cash';
      const amountIn = conv && rng() < 0.5 ? Math.round(amount * (0.97 + 0.02 * rng())) : null;
      rows.lyd_movements.push({ id: randomUUID(), owner_id: owner, kind: k, pocket: conv ? null : (rng() < 0.5 ? 'cash' : 'bank'),
        amount: money(amount), note: null, count_id: null, created_at: iso(at),
        amount_in: amountIn !== null && amountIn !== amount ? money(amountIn) : null });
    } else if (kind === 'adjust' || kind === 'expense') {
      const a = pick(accounts);
      const book = a.books.cash.bal > a.books.bank.bal ? 'cash' : 'bank';
      const B = a.books[book];
      if (B.bal < 10000) continue;
      const before = total(a);
      if (kind === 'adjust') {
        const delta = Math.round((1 + 49 * rng()) * 100) * (rng() < 0.5 ? -1 : 1);
        B.bal += delta;
        rows.balance_adjustments.push({ id: randomUUID(), owner_id: owner, exchange_id: a.id, balance_before: money(before),
          balance_after: money(before + delta), delta: money(delta), reason: 'مطابقة الكشف', adjusted_by_name: 'المدير',
          created_at: iso(at), kind: 'adjust', book });
      } else {
        const amt = Math.round((1 + 19 * rng()) * 100);
        B.bal -= amt;
        rows.account_expenses.push({ id: randomUUID(), owner_id: owner, exchange_id: a.id, amount: money(amt), code: null,
          note: 'عمولة', balance_before: money(before), balance_after: money(before - amt), created_at: iso(at),
          created_by_name: 'المدير', cancelled_at: null, cancelled_by_name: null, cancel_reason: null, book });
      }
    } else if (kind === 'move') {
      const a = pick(accounts);
      const from = a.books.cash.bal > a.books.bank.bal ? 'cash' : 'bank';
      const to = from === 'cash' ? 'bank' : 'cash';
      const F = a.books[from], T = a.books[to];
      if (F.bal < 100000 || F.cost === null || (T.bal > 0 && T.cost === null)) continue;
      const q = Math.round(F.bal * (0.1 + 0.2 * rng()));
      const price = mk.sell(to, at) - 0.1;
      const vq = q / 100, vb = T.bal / 100;
      const nc = vb <= 0 ? r6(price) : r6((vb * T.cost + vq * price) / (vb + vq));
      const id = randomUUID();
      rows.book_transfers.push({ id, owner_id: owner, exchange_id: a.id, from_book: from, to_book: to, usd: money(q),
        from_cost: F.cost.toFixed(6), to_price: price.toFixed(4), note: null, created_by_name: 'المدير', created_at: iso(at) });
      rows.account_cost_events.push({ id: randomUUID(), owner_id: owner, exchange_id: a.id, kind: 'move_in', operation_id: id,
        balance_before: vb.toFixed(2), cost_before: T.cost === null ? null : T.cost.toFixed(6), usd_amount: vq.toFixed(2),
        rate: price.toFixed(4), balance_after: (vb + vq).toFixed(2), cost_after: nc.toFixed(6), created_at: iso(at), book: to });
      F.bal -= q; T.bal += q; T.cost = nc;
    }
  }
  return { rows, lastRates, nextRef: ref };
}

// ------------------------------------------------------------------ seed
const PW = 'pass-1234';
const db = await benchDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;
log(`database built up to migration ${UPTO}; N = ${N} sales + ${N} purchases for the main administrator, ${OTHERS} others with ${Math.round(N / 5)} + ${Math.round(N / 5)} each`);

const ADMIN = '11111111-1111-1111-1111-111111111111';
const A_EMP = '33333333-3333-3333-3333-333333333333';
const OTHER_ADMINS = Array.from({ length: OTHERS }, (_, i) => `aaaaaaaa-0000-0000-0000-${String(i + 1).padStart(12, '0')}`);
// GoTrue hashes passwords with bcrypt cost 10: the cancel / adjust password check pays that
await q(`insert into auth.users (id, email, encrypted_password) values ($1, 'a@x.ly', extensions.crypt($2, extensions.gen_salt('bf', 10)))`, [ADMIN, PW]);
await q(`insert into auth.users (id, email) values ($1, null)`, [A_EMP]);
for (const o of OTHER_ADMINS) await q(`insert into auth.users (id, email, encrypted_password) values ($1, $2, 'x')`, [o, o.slice(-3) + '@x.ly']);
for (const o of [ADMIN, ...OTHER_ADMINS]) {
  await q(`insert into account_licenses (user_id, status, license_type) values ($1, 'active', 'lifetime')
           on conflict (user_id) do update set status = 'active', license_type = 'lifetime'`, [o]);
}
const EMP = (await q(`insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
  values ($1, 'موظف', '0911111111', 'x', array['transfers_create','buys_create']) returning id`, [ADMIN]))[0].id;
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1, $2, 'd1')`, [EMP, A_EMP]);

const OPEN_AT = YEAR_START - DAY;
async function seedOwner(owner, { nAccounts, nCustomers, nKind, emp, seed, companyName }) {
  const company = (await q(`insert into companies (owner_id, name, start_ref) values ($1, $2, 'Rh1000') returning id`, [owner, companyName]))[0].id;
  const rng = rngFrom(seed * 7919);
  const accounts = [];
  for (let i = 0; i < nAccounts; i++) {
    const book = i % 2 === 0 ? 'cash' : 'bank';
    const bal = Math.round((20000 + 180000 * rng()) * 100);
    const cost = book === 'cash' ? r4(6.9 + 0.2 * rng()) : r4(7.6 + 0.2 * rng());
    const ex = (await as(db, owner, (tx) => tx.query(`select * from admin_open_account($1,$2,$3,null,null,$4,$5)`,
      [company, `حساب ${i + 1}`, money(bal), cost, book]))).rows[0];
    accounts.push({ id: ex.id, name: ex.name, books: {
      cash: { bal: book === 'cash' ? bal : 0, cost: book === 'cash' ? cost : null },
      bank: { bal: book === 'bank' ? bal : 0, cost: book === 'bank' ? cost : null } } });
  }
  // the openings a day before the year
  await q(`update exchanges set created_at = $2, books_split_at = $2 where company_id = $1`, [company, iso(OPEN_AT)]);
  for (const t of ['balance_adjustments', 'account_cost_events']) await q(`update ${t} set created_at = $2 where owner_id = $1`, [owner, iso(OPEN_AT)]);
  await q(`insert into lyd_treasury (owner_id, started_at, opening_cash, opening_bank) values ($1, $2, $3, $3)`, [owner, iso(OPEN_AT + 3600000), Math.max(5e6, nKind * 10000)]);
  const custRows = Array.from({ length: nCustomers }, (_, i) => ({ id: randomUUID(), owner_id: owner, name: `عميل ${i + 1}`,
    company: null, code: `C${i + 1}`, created_at: iso(OPEN_AT), credit_limit: i < nCustomers * 0.6 ? '500000.00' : null }));
  await bulkInsert(db, 'clients', custRows);
  const customers = custRows.map((c) => c.id);
  const sim = simulate({ owner, company, companyName, accounts, customers, nKind, emp, refStart: 1000, seed });
  // a few customers had a balance before the app
  for (let i = 0; i < Math.min(30, customers.length); i += 3) {
    sim.rows.customer_lyd_entries.push({ id: randomUUID(), owner_id: owner, client_id: customers[i], kind: 'opening',
      amount: money(100000 + i * 1000), pocket: null, operation_id: null, note: 'رصيد سابق', request_id: null,
      created_by_employee_id: null, created_at: iso(OPEN_AT + 7200000), book: i % 2 ? 'cash' : 'bank' });
  }
  await db.exec(`set session_replication_role = replica`);   // triggers and FK checks off for the bulk
  for (const [t, rows] of Object.entries(sim.rows)) await bulkInsert(db, t, rows);
  await db.exec(`set session_replication_role = origin`);
  // the books and the accounts as the simulation ended
  for (const a of accounts) {
    for (const b of ['cash', 'bank']) {
      await q(`update account_books set balance = $3, cost_rate = $4 where exchange_id = $1 and book = $2`,
        [a.id, b, money(a.books[b].bal), a.books[b].cost === null ? null : a.books[b].cost.toFixed(6)]);
    }
    await q(`update exchanges set balance = $2 where id = $1`, [a.id, money(a.books.cash.bal + a.books.bank.bal)]);
  }
  for (const [k, r] of Object.entries(sim.lastRates)) {
    await q(`insert into last_exchange_rates (owner_id, kind, rate) values ($1,$2,$3)
             on conflict (owner_id, kind) do update set rate = excluded.rate`, [owner, k, r]);
  }
  const counts = Object.fromEntries(Object.entries(sim.rows).map(([t, r]) => [t, r.length]));
  return { company, accounts, customers, counts };
}

const MAIN = await seedOwner(ADMIN, { nAccounts: 30, nCustomers: 500, nKind: N, emp: EMP, seed: 1, companyName: 'الرحالة' });
log('main administrator seeded', JSON.stringify(MAIN.counts));
for (let i = 0; i < OTHER_ADMINS.length; i++) {
  await seedOwner(OTHER_ADMINS[i], { nAccounts: 5, nCustomers: 50, nKind: Math.round(N / 5), emp: null, seed: 100 + i, companyName: `شركة ${i + 1}` });
}
log(`${OTHER_ADMINS.length} other administrators seeded`);
// eleven monthly closes (what ledger_closes re-checks every time)
for (let m = 1; m <= 11; m++) {
  await q(`insert into period_closes (owner_id, period_end, trial, net_profit, seal, seal_version, note, closed_by, created_at)
           values ($1, $2, '[]', 0, md5(''), 2, $3, 'المدير', $2)`, [ADMIN, iso(YEAR_START + m * 30 * DAY), `شهر ${m}`]);
}
await db.exec('vacuum analyze');
const sizes = await q(`select relname, n_live_tup::int n from pg_stat_user_tables where relname in
  ('transfers','currency_buys','account_cost_events','operation_costs','customer_lyd_entries','lyd_movements',
   'balance_adjustments','account_expenses','book_transfers','operation_cancellations','clients','exchanges') order by n desc`);
log('rows:', sizes.map((r) => `${r.relname} ${r.n}`).join(', '));
// sanity: the books follow the accounts
const off = await q(`select count(*)::int k from exchanges e where e.balance <> (select sum(balance) from account_books b where b.exchange_id = e.id)`);
if (off[0].k) throw new Error('books out of step after the seed');

// ------------------------------------------------------------------ timing
const results = {};
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.ceil((p / 100) * s.length) - 1)]; };
// every timed call goes through runImpl.fn, so the profile can swap it for one that keeps the notices
const runImpl = { fn: (uid, sql, params = []) => as(db, uid, (tx) => tx.query(sql, params)) };
const run = (uid, sql, params = []) => runImpl.fn(uid, sql, params).then((r) => r.rows);
const A = (sql, p) => run(ADMIN, sql, p);
const E = (sql, p) => run(A_EMP, sql, p);
const CALLS = new Map();             // name → fn(i, opts), for the profile and the re-timing

async function bench(name, fn, { warm = true, min = 5, max = 20, budget = 3000 } = {}) {
  CALLS.set(name, fn);
  const times = [];
  let i = 0;
  if (warm) {
    const s = performance.now();
    await fn(i++);
    const w = performance.now() - s;
    if (w > 1500) { times.push(w); min = 3; max = 3; }   // a heavy call: the first run counts, 3 in all
  }
  const t0 = performance.now();
  while (times.length < max && (times.length < min || performance.now() - t0 < budget)) {
    const s = performance.now();
    await fn(i++);
    times.push(performance.now() - s);
  }
  const r = { runs: times.length, median: +pct(times, 50).toFixed(1), p95: +pct(times, 95).toFixed(1), max: +Math.max(...times).toFixed(1) };
  results[name] = r;
  log(`${name.padEnd(46)} median ${String(r.median).padStart(8)} ms   p95 ${String(r.p95).padStart(8)} ms   (${r.runs} runs)`);
  return r;
}

const C1 = MAIN.company;
const acc = MAIN.accounts;
const accWith = async (book, usd) => (await q(`select exchange_id from account_books where owner_id = $1 and book = $2 and balance > $3 order by balance desc limit 1`, [ADMIN, book, usd]))[0].exchange_id;
const EX_CASH = await accWith('cash', 1000);
const EX_BANK = await accWith('bank', 1000);
const EX_BUSY = (await q(`select exchange_id from transfers where owner_id = $1 group by 1 order by count(*) desc limit 1`, [ADMIN]))[0].exchange_id;
const CUST_BUSY = (await q(`select client_id from customer_lyd_entries where owner_id = $1 group by 1 order by count(*) desc limit 1`, [ADMIN]))[0].client_id;
const CUST_LIMIT = (await q(`select id from clients where owner_id = $1 and credit_limit is not null order by name limit 1`, [ADMIN]))[0].id;
const rates = Object.fromEntries((await q(`select kind, rate::float r from last_exchange_rates where owner_id = $1`, [ADMIN])).map((x) => [x.kind, x.r]));
const iso0 = iso(DAY_START);
const MONTH_AGO = iso(NOW - 30 * DAY), YEAR_AGO = iso(YEAR_START), NOWS = iso(NOW + 60000);
const savedSales = [], savedBuys = [];

log('— writes (as the administrator, and the employee)');
const HASH = (await q(`select encrypted_password h from auth.users where id = $1`, [ADMIN]))[0].h;
await bench('crypt() alone (bcrypt cost 10)', () => A(`select extensions.crypt($1, $2) x`, [PW, HASH]), { min: 3, budget: 1500 });
await bench('next_reference', () => A(`select next_reference($1) r`, [C1]));
await bench('record_transfer (admin, paid, cash book)', async (i) => {
  const r = await A(`select * from record_transfer($1,$2,'مستفيد',null,null,$3,'',$4,'cash',$5,null,null,false,'cash')`,
    [C1, EX_CASH, 10 + (i % 7), rates.sell_cash, randomUUID()]);
  savedSales.push(r[0].id);
});
await bench('record_transfer (admin, bank book, on credit)', async () => {
  const r = await A(`select * from record_transfer($1,$2,'مستفيد',null,null,12,'',$3,null,$4,$5,0,true,'bank')`,
    [C1, EX_BANK, rates.sell_bank, randomUUID(), CUST_LIMIT]);
  savedSales.push(r[0].id);
});
await bench('record_transfer (employee)', () => E(`select * from record_transfer($1,$2,'مستفيد',null,null,10,'',$3,'cash',$4,null,null,false,'cash')`,
  [C1, EX_CASH, rates.sell_cash, randomUUID()]));
await bench('record_currency_buy (admin, cash book)', async () => {
  const r = await A(`select * from record_currency_buy($1,$2,null,null,25,$3,null,'',null,$4,null,'cash')`, [C1, EX_CASH, rates.buy_cash, randomUUID()]);
  savedBuys.push(r[0].id);
});
await bench('record_currency_buy (employee, bank book)', () => E(`select * from record_currency_buy($1,$2,null,null,25,$3,null,'',null,$4,null,'bank')`,
  [C1, EX_BANK, rates.buy_bank, randomUUID()]));
await bench('admin_cancel_operation (sale)', (i) => A(`select admin_cancel_operation('transfer',$1,'خطأ في الإدخال',$2) r`, [savedSales[i], PW]), { min: 3, max: 8 });
await bench('admin_cancel_operation (purchase)', (i) => A(`select admin_cancel_operation('buy',$1,'خطأ في الإدخال',$2) r`, [savedBuys[i], PW]), { min: 3, max: 8 });
await bench('customer_add_entry (collect)', () => A(`select customer_add_entry($1,'collect',5,'cash',null,$2) r`, [CUST_BUSY, randomUUID()]));
await bench('customer_add_entry (pay: checks the pocket)', () => A(`select customer_add_entry($1,'pay',5,'bank',null,$2) r`, [CUST_BUSY, randomUUID()]));
await bench('move_between_books', (i) => A(`select move_between_books($1,$2,1,$3) r`, [EX_CASH, i % 2 ? 'bank' : 'cash', rates.sell_cash]));
await bench('lyd_add_movement (out: checks the pocket)', () => A(`select lyd_add_movement('out','cash',10) r`));
await bench('admin_adjust_balance', async (i) => {
  const b = (await q(`select balance::float b from account_books where exchange_id = $1 and book = 'cash'`, [EX_CASH]))[0].b;
  return A(`select admin_adjust_balance($1,$2,'مطابقة الكشف',$3,'cash') r`, [EX_CASH, (b + (i % 2 ? 1 : -1)).toFixed(2), PW]);
}, { min: 3, max: 6 });
await bench('reconcile_account (_balance_at, a month back)', () => A(`select reconcile_account($1,$2,1000,null) r`, [EX_BUSY, MONTH_AGO]));

log('— reads the screens make');
// PostgREST: select … with the filters, as json (the app's .from(...).select())
const rest = (sel) => `select coalesce(json_agg(_t), '[]') r from (${sel}) _t`;
await bench('today sales list (admin)', () => A(rest(`select * from transfers where status = 'archived' and created_at >= $1 order by created_at desc`), [iso0]));
await bench('today purchases list (admin)', () => A(rest(`select * from currency_buys where status = 'archived' and created_at >= $1 order by created_at desc`), [iso0]));
await bench('today sales list (employee, own rows)', () => E(rest(`select * from transfers where status = 'archived' and created_at >= $1 and created_by_employee_id = $2 order by created_at desc`), [iso0, EMP]));
await bench('today purchases list (employee, own rows)', () => E(rest(`select * from currency_buys where status = 'archived' and created_at >= $1 and created_by_employee_id = $2 order by created_at desc`), [iso0, EMP]));
const page = (table) => rest(`select * from ${table} where status = 'archived' order by created_at desc, id limit 1000 offset $1`);
await bench('archive sales: first page of 1000', () => A(page('transfers'), [0]));
const allPages = async (table) => { for (let o = 0; ; o += 1000) { const r = await A(page(table), [o]); if ((r[0].r?.length ?? 0) < 1000) break; } };
await bench('archive sales: every page (العمليات tab)', () => allPages('transfers'), { min: 2, max: 3 });
await bench('archive purchases: every page', () => allPages('currency_buys'), { min: 2, max: 3 });
const stmt = async (from) => {
  for (const t of ['transfers', 'currency_buys']) {
    for (let o = 0; ; o += 1000) {
      const r = await A(rest(`select * from ${t} where status = 'archived' and archived_at >= $1 and archived_at <= $2 order by archived_at, id limit 1000 offset $3`), [from, NOWS, o]);
      if ((r[0].r?.length ?? 0) < 1000) break;
    }
  }
  await A(rest(`select * from account_expenses where created_at >= $1 order by created_at, id`), [from]);
  await A(rest(`select * from balance_adjustments where created_at >= $1 order by created_at, id`), [from]);
};
await bench('account statement data (1 month)', () => stmt(MONTH_AGO));
await bench('account statement data (1 year)', () => stmt(YEAR_AGO), { min: 2, max: 3 });
await bench('accounts list (exchanges)', () => A(rest(`select * from exchanges order by created_at`)));
await bench('customers list (clients)', () => A(rest(`select * from clients order by created_at`)));
await bench('current_exchange_rates (admin)', () => A(`select current_exchange_rates() r`));
await bench('current_exchange_rates (employee)', () => E(`select current_exchange_rates() r`));
await bench('treasury_positions', () => A(`select coalesce(json_agg(x), '[]') r from treasury_positions() x`));
await bench('account_books_list', () => A(`select account_books_list() r`));
await bench('account_cost_history', () => A(`select coalesce(json_agg(x), '[]') r from account_cost_history($1) x`, [EX_BUSY]));
await bench('profit_report (1 month)', () => A(`select coalesce(json_agg(x), '[]') r from profit_report($1,$2) x`, [MONTH_AGO, NOWS]));
await bench('profit_report (1 year)', () => A(`select coalesce(json_agg(x), '[]') r from profit_report($1,$2) x`, [YEAR_AGO, NOWS]));
await bench('customer_balances', () => A(`select customer_balances() r`));
await bench('customer_statement (1 month, both books)', () => A(`select customer_statement($1,$2,$3) r`, [CUST_BUSY, MONTH_AGO, NOWS]));
await bench('customer_statement (1 year, both books)', () => A(`select customer_statement($1,$2,$3) r`, [CUST_BUSY, YEAR_AGO, NOWS]));
await bench('customer_statement (1 year, cash book)', () => A(`select customer_statement($1,$2,$3,'cash') r`, [CUST_BUSY, YEAR_AGO, NOWS]));
await bench('lyd_summary (today)', () => A(`select lyd_summary($1,$2) r`, [iso0, NOWS]));
await bench('lyd_summary (1 year)', () => A(`select lyd_summary($1,$2) r`, [YEAR_AGO, NOWS]));
await bench('ledger_trial_balance (both books)', () => A(`select ledger_trial_balance($1) r`, [NOWS]));
await bench('ledger_trial_balance (cash book)', () => A(`select ledger_trial_balance($1,'cash') r`, [NOWS]));
await bench('ledger_trial_balance (both, bank × 0.85)', () => A(`select ledger_trial_balance($1,null,0.85) r`, [NOWS]));
await bench('ledger_income_statement (1 month)', () => A(`select ledger_income_statement($1,$2) r`, [MONTH_AGO, NOWS]));
await bench('ledger_income_statement (1 year)', () => A(`select ledger_income_statement($1,$2) r`, [YEAR_AGO, NOWS]));
await bench('ledger_income_statement (1 month, bank book)', () => A(`select ledger_income_statement($1,$2,'bank') r`, [MONTH_AGO, NOWS]));
await bench('ledger_balance_sheet (both books)', () => A(`select ledger_balance_sheet($1) r`, [NOWS]));
await bench('ledger_balance_sheet (cash book)', () => A(`select ledger_balance_sheet($1,'cash') r`, [NOWS]));
await bench('ledger_journal (1 month)', () => A(`select ledger_journal($1,$2) r`, [MONTH_AGO, NOWS]));
await bench('ledger_journal (1 year, first 3000 lines)', () => A(`select ledger_journal($1,$2) r`, [YEAR_AGO, NOWS]));
await bench('ledger_closes (11 closes)', () => A(`select ledger_closes() r`));
// what _journal does for each cancelled sale (and purchase, adjustment, commission): the cost at that moment
await bench('_cost_at for every cancelled sale (internal)', () => db.query(`select count(_cost_at(t.exchange_id, coalesce(t.book, 'bank'), t.cancelled_at))
  from transfers t where t.owner_id = $1 and t.cancelled_at is not null`, [ADMIN]));
await bench('account_reconciliations_list', () => A(`select account_reconciliations_list($1) r`, [EX_BUSY]));
let closeEnd = NOW - 30 * 60000;
await bench('close_period', () => A(`select close_period($1, 'شهر') r`, [iso(closeEnd += 1000)]), { warm: false, min: 2, max: 2 });

// ------------------------------------------------------------------ why the slow ones are slow
const plansFile = path.join(OUT, `bench93-N${N}${UPTO === 93 ? "" : "-m" + UPTO}-plans.txt`);
const profiles = {};
if (EXPLAIN) {
  // every call over SLOW_MS, plus the saves and the per-screen reads whose cost grows with the history
  const ALWAYS = ['record_transfer (admin, paid, cash book)', 'lyd_summary (1 year)', 'customer_add_entry (pay: checks the pocket)',
    'archive sales: first page of 1000', 'today sales list (admin)'];
  const slow = Object.entries(results).filter(([n, r]) => (r.median > SLOW_MS || ALWAYS.includes(n)) && CALLS.has(n)
    && !n.startsWith('admin_cancel') && !n.startsWith('admin_adjust') && !n.startsWith('crypt') && !n.startsWith('_cost_at') && n !== 'close_period');
  log(`— profiling ${slow.length} calls (function calls + auto_explain of nested statements)`);
  fs.writeFileSync(plansFile, `bench93 N=${N} ${new Date().toISOString()}\n`);
  for (const [name, r] of slow) {
    const thr = Math.max(10, Math.round(r.median * 0.05));
    await db.exec(`set track_functions = 'all';
      set auto_explain.log_min_duration = ${thr}; set auto_explain.log_analyze = on; set auto_explain.log_buffers = on;
      set auto_explain.log_nested_statements = on; set auto_explain.log_timing = on; set auto_explain.log_format = text; set auto_explain.log_level = notice;`);
    const notes = [];
    let stats = [];
    const fn = CALLS.get(name);
    // re-run through a wrapper that keeps the notices and reads the per-function stats
    const runProfiled = (uid, sql, params = []) => as(db, uid, async (tx) => {
      // the per-function counters of this backend, before and after: the difference is this call
      const statSql = `select funcname, calls::int c, total_time::float t, self_time::float s from pg_stat_xact_user_functions`;
      const before = new Map((await tx.query(statSql)).rows.map((x) => [x.funcname, x]));
      const res = await tx.query(sql, params, { onNotice: (n) => notes.push(n.message) });
      for (const x of (await tx.query(statSql)).rows) {
        const b = before.get(x.funcname) ?? { c: 0, t: 0, s: 0 };
        if (x.c > b.c) stats.push({ funcname: x.funcname, calls: x.c - b.c, total_ms: x.t - b.t, self_ms: x.s - b.s });
      }
      return res;
    });
    const s = performance.now();
    await withRunner(runProfiled, () => fn(1000));
    const took = performance.now() - s;
    await db.exec(`set auto_explain.log_min_duration = -1; set auto_explain.log_analyze = off; set track_functions = 'none';`);
    // merge the stats of the several statements a call may make
    const merged = {};
    for (const x of stats) {
      const m = (merged[x.funcname] ??= { calls: 0, total_ms: 0, self_ms: 0 });
      m.calls += x.calls; m.total_ms += x.total_ms; m.self_ms += x.self_ms;
    }
    const top = Object.entries(merged).sort((a, b) => b[1].self_ms - a[1].self_ms).slice(0, 8)
      .map(([f, m]) => `${f} ×${m.calls} self ${m.self_ms.toFixed(0)} ms / total ${m.total_ms.toFixed(0)} ms`);
    const plans = notes.filter((m) => m.startsWith('duration:'))
      .map((m) => ({ ms: Number(m.match(/duration: ([\d.]+)/)[1]), text: m }))
      .sort((a, b) => b.ms - a.ms);
    profiles[name] = { profiled_ms: +took.toFixed(0), functions: top, slowest_statements: plans.slice(0, 3).map((p) => p.text.split('\n').slice(0, 3).join(' | ').slice(0, 300)) };
    fs.appendFileSync(plansFile, `\n\n######## ${name} (median ${r.median} ms; profiled run ${took.toFixed(0)} ms)\n` +
      `functions (self time): \n  ${top.join('\n  ')}\n` + plans.slice(0, 4).map((p) => p.text).join('\n\n----\n'));
    log(`profiled ${name}: ${top.slice(0, 3).join('; ')}`);
  }
  log(`plans written to ${plansFile}`);
}

// the call functions use A / E; the profile swaps the runner underneath them
function withRunner(runner, body) {
  const saved = runImpl.fn;
  runImpl.fn = runner;
  return body().finally(() => { runImpl.fn = saved; });
}


// ------------------------------------------------------------------ plans of the plain queries
const explains = {};
async function explainAs(label, uid, sql, params = []) {
  const ex = `explain (analyze, buffers) ${sql}`;
  const res = uid ? await as(db, uid, (tx) => tx.query(ex, params)) : await db.query(ex, params);
  const text = res.rows.map((r) => r['QUERY PLAN']).join('\n');
  explains[label] = Number(text.match(/Execution Time: ([\d.]+)/)?.[1] ?? NaN);
  fs.appendFileSync(plansFile, `\n\n######## EXPLAIN ${label} (${uid ? 'as ' + (uid === ADMIN ? 'the administrator' : 'the employee') : 'superuser'})\n${sql}\n${text}`);
  return text;
}
if (EXPLAIN) {
  if (!fs.existsSync(plansFile)) fs.writeFileSync(plansFile, `bench93 N=${N}\n`);
  const nArch = (await q(`select count(*)::int k from transfers where owner_id = $1 and status = 'archived'`, [ADMIN]))[0].k;
  await explainAs('today sales list (admin)', ADMIN, `select * from transfers where status = 'archived' and created_at >= $1 order by created_at desc`, [iso0]);
  await explainAs('today sales list (employee)', A_EMP, `select * from transfers where status = 'archived' and created_at >= $1 and created_by_employee_id = $2 order by created_at desc`, [iso0, EMP]);
  await explainAs('archive sales page, offset 0', ADMIN, `select * from transfers where status = 'archived' order by created_at desc, id limit 1000 offset 0`);
  await explainAs(`archive sales page, last offset (${Math.floor(nArch / 1000) * 1000})`, ADMIN,
    `select * from transfers where status = 'archived' order by created_at desc, id limit 1000 offset ${Math.floor(nArch / 1000) * 1000}`);
  await explainAs('statement sales page (1 year, offset 0)', ADMIN, `select * from transfers where status = 'archived' and archived_at >= $1 and archived_at <= $2 order by archived_at, id limit 1000`, [YEAR_AGO, NOWS]);
  await explainAs('statement sales page (1 month, offset 0)', ADMIN, `select * from transfers where status = 'archived' and archived_at >= $1 and archived_at <= $2 order by archived_at, id limit 1000`, [MONTH_AGO, NOWS]);
  await explainAs('statement adjustments since (1 month)', ADMIN, `select * from balance_adjustments where created_at >= $1 order by created_at, id`, [MONTH_AGO]);
  await explainAs('next_reference: the count', null, `select count(*) from transfers where owner_id = $1 and cancelled_at is null`, [ADMIN]);
  await explainAs('next_reference: the highest number', null, `select max(substr(reference, 3)::numeric) from transfers
     where owner_id = $1 and cancelled_at is null and left(reference, 2) = 'Rh' and substr(reference, 3) ~ '^[0-9]{1,30}$'`, [ADMIN]);
  await explainAs('_lyd_position: the sales since the opening', null, `select coalesce(sum(t.lyd_paid) filter (where t.lyd_method = 'cash'), 0),
     coalesce(sum(t.lyd_paid) filter (where t.lyd_method = 'bank'), 0) from transfers t
     where t.owner_id = $1 and t.status = 'archived' and t.cancelled_at is null and t.lyd_amount is not null
       and t.created_at >= (select started_at from lyd_treasury where owner_id = $1)`, [ADMIN]);
  // the plan _cost_at's query really runs with inside the journal (after five calls the
  // plan cache of a SQL function may use a generic plan): every call logged, the slowest kept
  {
    const notes = [];
    await db.exec(`set auto_explain.log_min_duration = 0; set auto_explain.log_analyze = on; set auto_explain.log_buffers = on;
      set auto_explain.log_nested_statements = on; set auto_explain.log_level = notice;`);
    await db.query(`select count(_cost_at(t.exchange_id, coalesce(t.book, 'bank'), t.cancelled_at)) from transfers t
      where t.owner_id = $1 and t.cancelled_at is not null`, [ADMIN], { onNotice: (n) => notes.push(n.message) });
    await db.exec(`set auto_explain.log_min_duration = -1; set auto_explain.log_analyze = off;`);
    const inner = notes.filter((m) => m.includes('account_cost_events'))
      .map((m) => ({ ms: Number(m.match(/duration: ([\d.]+)/)?.[1] ?? 0), m })).sort((a, b) => b.ms - a.ms);
    const avg = inner.reduce((s, x) => s + x.ms, 0) / Math.max(1, inner.length);
    explains[`_cost_at inner query: ${inner.length} calls, avg ms`] = +avg.toFixed(3);
    fs.appendFileSync(plansFile, `\n\n######## _cost_at inner query as called per cancelled sale: ${inner.length} calls, average ${avg.toFixed(3)} ms; the slowest:\n${inner[0]?.m ?? '(none)'}\n----\n${inner[Math.floor(inner.length / 2)]?.m ?? ''}`);
  }
  log(`plain-query plans appended to ${plansFile}`);
}

// ------------------------------------------------------------------ candidate fixes, in this copy only
// Each fix is applied to this in-memory database, its result is checked
// against the original where it can be, and the calls it affects are timed again.
const journalHash = async () => (await q(`select count(*)::int n, md5(string_agg(concat_ws('|', at, source, source_id, account, amount, book, exchange_id, client_id), ','
  order by at, source, source_id, account, book, amount, exchange_id, client_id)) h from _journal($1)`, [ADMIN]))[0];
const LEDGER_CALLS = ['ledger_trial_balance (both books)', 'ledger_income_statement (1 month)', 'ledger_balance_sheet (both books)',
  'ledger_journal (1 month)', 'ledger_closes (11 closes)'];
const patchFunction = async (sig, from, to) => {
  const def = (await q(`select pg_get_functiondef($1::regprocedure) d`, [sig]))[0].d;
  if (!def.includes(from)) throw new Error(`patch of ${sig}: text not found`);
  await db.exec('set search_path = public, extensions;\n' + def.replace(from, to));
};
const FIXES = [
  {
    name: 'A. _journal: compute the unvalued-dollars CTE once (MATERIALIZED)',
    sql: `-- in _journal (0093): "unval (exchange_id, book, at, amount) as (" → "… as materialized ("
-- (the CTE is read only by the correlated subquery of "openings", so Postgres inlines it
--  and rescans every sale and purchase once per opening / correction event)`,
    apply: () => patchFunction('_journal(uuid)', 'unval (exchange_id, book, at, amount) as (', 'unval (exchange_id, book, at, amount) as materialized ('),
    verify: journalHash,
    affects: LEDGER_CALLS,
  },
  {
    name: 'C. ledger_closes: the journal summed once per stretch between closes, instead of one aggregate per close',
    sql: `create or replace function ledger_closes()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $fn$
declare
  v_admin uuid := _lyd_admin();
  v_ends  timestamptz[];
  v_out   jsonb;
begin
  -- each close's end plus a microsecond, oldest first: width_bucket(at, v_ends)
  -- is then the number of closes strictly before a line ("at <= period_end")
  select coalesce(array_agg(p.period_end + interval '1 microsecond' order by p.period_end, p.id), '{}')
    into v_ends from period_closes p where p.owner_id = v_admin;
  if cardinality(v_ends) = 0 then
    return '[]'::jsonb;
  end if;
  with c as (
    select p.*, row_number() over (order by p.period_end, p.id) as k
      from period_closes p where p.owner_id = v_admin
  ),
  -- the journal once, summed per account and per stretch between two closes
  agg as (
    select width_bucket(l.at, v_ends) as bucket, l.account,
           coalesce(sum(l.amount) filter (where l.amount > 0), 0) as d,
           coalesce(-sum(l.amount) filter (where l.amount < 0), 0) as cr
      from _journal(v_admin) l
     group by 1, 2
  ),
  -- each close: every stretch before it
  cum as (
    select c.id, a.account, sum(a.d) as debit, sum(a.cr) as credit
      from c join agg a on a.bucket < c.k
     where c.seal_version >= 2 or a.account <> '3300'
     group by c.id, a.account
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'period_end', c.period_end, 'net_profit', c.net_profit,
           'note', c.note, 'closed_by', c.closed_by, 'created_at', c.created_at,
           'intact', c.seal = _trial_seal(coalesce((
             select jsonb_agg(jsonb_build_object('account', x.account, 'debit', x.debit, 'credit', x.credit))
               from cum x where x.id = c.id), '[]'::jsonb)))
         order by c.period_end desc), '[]'::jsonb)
    into v_out
    from c;
  return v_out;
end;
$fn$;`,
    verify: async () => JSON.stringify((await A(`select ledger_closes() r`))[0].r),
    affects: ['ledger_closes (11 closes)'],
  },
  {
    name: 'D. close_period: one journal instead of two (the trial balance and the profit from the same lines)',
    sql: `create or replace function close_period(p_end timestamptz, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_admin uuid := _lyd_admin();
  v_trial jsonb;
  v_net   numeric;
  v_name  text;
  v_id    uuid;
  v_last  timestamptz;
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_end is null or p_end > now() - interval '5 minutes' then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  if exists (select 1 from period_closes where owner_id = v_admin and period_end >= p_end) then
    raise exception 'period_already_closed' using errcode = 'P0001';
  end if;
  select coalesce(max(period_end), '-infinity') into v_last from period_closes where owner_id = v_admin;
  with j as materialized (
    select l.at, l.account, l.amount from _journal(v_admin) l where l.at <= p_end
  ),
  t as (
    select j.account,
           round(coalesce(sum(j.amount) filter (where j.amount > 0), 0), 2) as debit,
           round(coalesce(-sum(j.amount) filter (where j.amount < 0), 0), 2) as credit
      from j group by j.account
  )
  select coalesce((select jsonb_agg(jsonb_build_object(
                     'account', t.account, 'name', _ledger_account_name(t.account),
                     'debit', t.debit, 'credit', t.credit, 'balance', t.debit - t.credit)
                   order by t.account) from t), '[]'::jsonb),
         (select coalesce(-sum(j.amount), 0) from j where j.at > v_last and j.account >= '4000')
    into v_trial, v_net;
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''), u.email)
    into v_name from auth.users u where u.id = v_admin;
  insert into period_closes (owner_id, period_end, trial, net_profit, seal, seal_version, note, closed_by)
  values (v_admin, p_end, v_trial, round(v_net, 2), _trial_seal(v_trial), 2,
          nullif(btrim(coalesce(p_note, '')), ''), v_name)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'net_profit', round(v_net, 2));
end;
$$;`,
    affects: ['close_period'],
  },
  {
    name: 'E. next_reference: the highest number from an index instead of a scan of every transfer',
    sql: `-- the trailing digits as a number, highest first (the prefix of start_ref holds no digits, 0006/0089)
create index if not exists transfers_owner_active_refnum_idx on transfers
  (owner_id, ((substring(reference from '([0-9]{1,30})$'))::numeric) desc nulls last)
  where cancelled_at is null;
-- the count of active transfers from the index alone
create index if not exists transfers_owner_active_idx on transfers (owner_id) where cancelled_at is null;
create or replace function _next_reference_for(p_owner uuid, p_company_id uuid)
returns text language plpgsql stable security definer set search_path = public, extensions as $fn$
declare
  v_start_ref text; v_count integer; v_match text[]; v_prefix text;
  v_first numeric; v_pad_width integer; v_max numeric;
begin
  select start_ref into v_start_ref from companies where id = p_company_id and owner_id = p_owner;
  if not found then return null; end if;
  select count(*) into v_count from transfers where owner_id = p_owner and cancelled_at is null;
  v_match := regexp_match(coalesce(v_start_ref, ''), '^([^0-9]*)([0-9]+)$');
  if v_match is not null then
    v_prefix := v_match[1]; v_first := v_match[2]::numeric; v_pad_width := length(v_match[2]);
  else
    v_prefix := coalesce(v_start_ref, ''); v_first := 1; v_pad_width := 3;
  end if;
  -- the 50 highest numbers of the owner from the index; the highest of this prefix among them
  select max(substr(s.reference, length(v_prefix) + 1)::numeric) into v_max
    from (select t.reference from transfers t
           where t.owner_id = p_owner and t.cancelled_at is null
           order by (substring(t.reference from '([0-9]{1,30})$'))::numeric desc nulls last
           limit 50) s
   where left(s.reference, length(v_prefix)) = v_prefix
     and substr(s.reference, length(v_prefix) + 1) ~ '^[0-9]{1,30}$';
  if v_max is null then
    -- another company's numbers hold the top: the full scan of 0089
    select max(substr(reference, length(v_prefix) + 1)::numeric) into v_max
      from transfers
     where owner_id = p_owner and cancelled_at is null
       and left(reference, length(v_prefix)) = v_prefix
       and substr(reference, length(v_prefix) + 1) ~ '^[0-9]{1,30}$';
  end if;
  return v_prefix || _ref_pad(greatest(v_first + v_count, coalesce(v_max + 1, 0)), v_pad_width);
end;
$fn$;`,
    verify: async () => (await A(`select next_reference($1) r`, [C1]))[0].r,
    affects: ['next_reference', 'record_transfer (admin, paid, cash book)'],
  },
  {
    name: 'G. _cost_at: an index in its exact filter and order (exchange, book as it reads it, time desc, id desc)',
    sql: `-- _cost_at (0093) filters coalesce(book, 'bank') = p_book and orders created_at desc, id desc;
-- account_cost_events_book_idx is on the raw "book", so it walks the account's events instead
create index if not exists account_cost_events_cost_at_idx
  on account_cost_events (exchange_id, (coalesce(book, 'bank')), created_at desc, id desc);`,
    verify: journalHash,
    affects: ['_cost_at for every cancelled sale (internal)', 'ledger_trial_balance (both books)', 'ledger_closes (11 closes)'],
  },
];
const scratch = {};
if (SCRATCH) {
  for (const f of FIXES) {
    log(`— scratch fix ${f.name}`);
    const before = f.verify ? await f.verify() : null;
    if (f.apply) await f.apply(); else await db.exec('set search_path = public, extensions;\n' + f.sql);
    await db.exec('analyze');
    const after = f.verify ? await f.verify() : null;
    const same = f.verify ? JSON.stringify(before) === JSON.stringify(after) : null;
    if (f.verify) log(`   same result as before: ${same}${same ? '' : `  before ${JSON.stringify(before).slice(0, 200)} after ${JSON.stringify(after).slice(0, 200)}`}`);
    for (const n of f.affects) {
      if (!CALLS.has(n)) continue;
      const was = results[n];
      const saved = { ...results };
      const now = await bench(n, CALLS.get(n), n === 'close_period' ? { warm: false, min: 2, max: 2 } : { min: 3, max: 10 });
      Object.assign(results, saved);
      scratch[`${f.name} :: ${n}`] = { before: was.median, after: now.median, speedup: +(was.median / now.median).toFixed(1), same_result: same, sql: f.sql };
      log(`   ${n}: ${was.median} → ${now.median} ms`);
    }
  }
  // F. the archive page by page with a key instead of an offset: an app change
  //    (lib/features/*/data listByStatus), timed here side by side with the offset pages
  await db.exec(`create index if not exists transfers_owner_archived_created_idx on transfers (owner_id, created_at desc, id desc) where status = 'archived'`);
  const keyset = async (table) => {
    let last = null;
    for (;;) {
      const r = await A(rest(`select * from ${table} where status = 'archived'
        ${last ? 'and (created_at, id) < ($1::timestamptz, $2::uuid)' : ''} order by created_at desc, id desc limit 1000`), last ? [last.created_at, last.id] : []);
      const rows = r[0].r ?? [];
      if (rows.length < 1000) break;
      last = rows[rows.length - 1];
    }
  };
  const offsetMs = results['archive sales: every page (العمليات tab)'].median;
  const k = await bench('archive sales: every page by key (scratch F)', () => keyset('transfers'), { min: 2, max: 3 });
  scratch['F. archive by key (created_at, id) instead of offset :: archive sales: every page (العمليات tab)'] =
    { before: offsetMs, after: k.median, speedup: +(offsetMs / k.median).toFixed(1),
      sql: `-- app: .lt('created_at', last.created_at) (or an "or" on created_at/id) … .order('created_at', ascending: false).order('id', ascending: false).limit(1000)
create index transfers_owner_archived_created_idx on transfers (owner_id, created_at desc, id desc) where status = 'archived';` };

  // H. the two permissive read policies (own, read-only window) are OR-ed into
  //    owner_id = ANY(ARRAY[…]): no index can then give the rows in date order,
  //    so EVERY page reads and sorts the owner's whole history. One equality
  //    (the two functions never both answer: both come from _raw_admin_id())
  //    lets the (owner_id, created_at …) index stop after the page.
  const H_SQL = `drop policy if exists transfers_select_own on transfers;
drop policy if exists transfers_select_readonly on transfers;
create policy transfers_select_own on transfers
  for select using (owner_id = (select coalesce(effective_admin_id(), _readonly_admin_id())));
drop policy if exists currency_buys_select_own on currency_buys;
drop policy if exists currency_buys_select_readonly on currency_buys;
create policy currency_buys_select_own on currency_buys
  for select using (owner_id = (select coalesce(effective_admin_id(), _readonly_admin_id())));`;
  const visible = async () => ({
    admin: (await A(`select count(*)::int n, md5(string_agg(id::text, ',' order by id)) h from (select id from transfers union all select id from currency_buys) x`))[0],
    employee: (await E(`select count(*)::int n, md5(string_agg(id::text, ',' order by id)) h from (select id from transfers union all select id from currency_buys) x`))[0],
  });
  log('— scratch fix H. transfers + currency_buys: one permissive read policy (one owner value) instead of two OR-ed');
  const vb = await visible();
  await db.exec(H_SQL);
  const va = await visible();
  const sameH = JSON.stringify(vb) === JSON.stringify(va);
  log(`   same rows visible to the administrator and the employee: ${sameH}`);
  if (EXPLAIN) {
    await explainAs('after H: archive sales page, offset 0', ADMIN, `select * from transfers where status = 'archived' order by created_at desc, id limit 1000 offset 0`);
    await explainAs('after H: archive sales page by key (created_at, id) desc', ADMIN,
      `select * from transfers where status = 'archived' and (created_at, id) < ($1::timestamptz, $2::uuid) order by created_at desc, id desc limit 1000`,
      [iso(NOW - 60 * DAY), '00000000-0000-0000-0000-000000000000']);
  }
  for (const n of ['archive sales: first page of 1000', 'archive sales: every page (العمليات tab)', 'archive sales: every page by key (scratch F)',
    'archive purchases: every page', 'today sales list (admin)', 'account statement data (1 month)', 'account statement data (1 year)']) {
    const was = results[n];
    const saved = { ...results };
    const now = await bench(n, CALLS.get(n), { min: 2, max: 5 });
    Object.assign(results, saved);
    scratch[`H. one read policy on transfers / currency_buys :: ${n}`] = { before: was.median, after: now.median, speedup: +(was.median / now.median).toFixed(1), same_result: sameH, sql: H_SQL };
    log(`   ${n}: ${was.median} → ${now.median} ms`);
  }
}

const outFile = path.join(OUT, `bench93-N${N}${UPTO === 93 ? "" : "-m" + UPTO}.json`);
fs.writeFileSync(outFile, JSON.stringify({ N, upTo: UPTO, others: OTHERS, at: new Date().toISOString(),
  rows: Object.fromEntries(sizes.map((r) => [r.relname, r.n])), results, explains, profiles, scratch }, null, 2));
log(`results written to ${outFile}; total ${((performance.now() - T_START) / 1000).toFixed(0)} s`);
