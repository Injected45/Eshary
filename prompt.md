You are a senior Flutter + Supabase engineer migrating an existing single-file HTML/JS app to a production-grade Flutter app with Supabase backend. You prioritize correctness, exact feature parity, and clean separation over cleverness.

## Source artifact
File: `project_web.html` — a single-file Arabic/RTL financial operations app for "شركة الرحالة" with three tabs:
1. إدارة الحوالات (Transfer Management) — outgoing USD transfers from "my company → exchange office → beneficiary", auto-generated reference numbers, balance deduction
2. شراء عملة (Currency Buy) — buying USD from clients, LYD calculation by exchange rate, pending vs completed states, balance addition
3. الأرشيف العام (Global Archive) — totals of sold and bought USD after daily closure
Persistence: localStorage key `rahala_db_v21`. Schema entities: companies (with nested exchanges), clients, dailyTransfers, dailyBuy, currencyPending, globalSold, globalBought.

## Target state
- Flutter 3.x app, Material 3, RTL-first, Arabic locale (`ar`) as default
- Supabase backend: Postgres schema + Row Level Security + Auth (email/password)
- State management: Riverpod 2.x (`flutter_riverpod` + `riverpod_annotation`)
- Supabase client: `supabase_flutter` ^2.x
- Folder structure: `lib/{core,features,shared}` with `features/{transfers,currency_buy,archive,companies,clients,auth}` each containing `data/` `domain/` `presentation/`
- Mobile-first, also runs on web

## Phase 1 deliverables (this prompt only)
You will produce ONLY the following in this run. Do NOT scaffold the Flutter app yet.

1. **`supabase/migrations/0001_initial_schema.sql`** — full Postgres schema:
   - `profiles` (id uuid PK → auth.users, created_at)
   - `companies` (id, owner_id → profiles, name, start_ref, created_at)
   - `exchanges` (id, company_id → companies CASCADE, name, balance numeric(14,2), our_code, created_at)
   - `clients` (id, owner_id → profiles, name, company, code, created_at)
   - `transfers` (id, owner_id, company_id, exchange_id, beneficiary_name, beneficiary_account_company, beneficiary_code, amount numeric(14,2), reference, status enum: 'daily'|'archived', created_at, archived_at nullable)
   - `currency_buys` (id, owner_id, my_company_id, exchange_id, client_id nullable, client_from_account, usd_amount numeric(14,2), rate numeric(10,4), lyd_amount numeric(14,2), status enum: 'pending'|'daily'|'archived', created_at, archived_at nullable)
   - Indexes on owner_id and status for the two transactional tables
   - Enums declared at the top
2. **`supabase/migrations/0002_rls_policies.sql`** — RLS enabled on every table; users see/modify only rows where `owner_id = auth.uid()`. Cascade ownership for nested rows (exchange ownership derived via company.owner_id).
3. **`supabase/migrations/0003_functions.sql`** — Postgres functions:
   - `archive_daily_transfers(p_owner uuid)` → flips all `status='daily'` to `'archived'`, sets `archived_at = now()`, returns count
   - `archive_daily_buys(p_owner uuid)` → same for currency_buys
   - `next_reference(p_company_id uuid)` → returns `{start_ref}-{N}` where N = (count of all transfers for company) + 101 — match current JS logic at line 711
   - All functions are SECURITY INVOKER and check `owner_id` against `auth.uid()`
4. **`docs/migration-mapping.md`** — table mapping the original JS data structure to the new Postgres schema, plus a checklist of every JS function in the source file and which Phase (1-4) implements it.
5. **`docs/phase-plan.md`** — the 4-phase plan:
   - Phase 1: schema + RLS + functions (this prompt)
   - Phase 2: Flutter scaffold + Supabase client + Auth + Riverpod providers + repositories
   - Phase 3: UI screens for the three tabs with exact feature parity
   - Phase 4: polish — Arabic number formatting, share sheet, PDF export (jsPDF was loaded in source; replace with `pdf` package), offline cache

## Hard constraints
- MUST preserve exact business rules from source: balance is decremented on transfer save, incremented on currency buy save, reference number formula matches line 711, pending currency buys block archival (currently shown but unenforced — make it enforced via a check in the archive function)
- MUST use `numeric(14,2)` for all money — never `float`/`double` in DB
- MUST NOT scaffold Flutter code, install packages, or create `pubspec.yaml` in this phase
- MUST NOT add features not present in source (no dark mode, no notifications, no multi-currency beyond USD/LYD)
- All SQL identifiers in snake_case English; user-facing UI strings stay Arabic in later phases
- Wrap each migration file in a single transaction (`begin; ... commit;`)

## Stop conditions
Stop and ask before:
- Adding any column not derivable from the source HTML
- Choosing a different state management library
- Renaming any business concept (e.g., "exchange" → "broker")

## Output protocol
After each file is written, output: `✅ created <path> (<line count> lines)`
At the end: a summary listing all files created and a one-paragraph readiness check for Phase 2.

➡️ Run this first. When Phase 1 is approved, ask for Prompt 2 (Flutter scaffold + Auth + Repositories).
