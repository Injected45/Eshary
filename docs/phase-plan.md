# Phase plan — `project_web.html` → Flutter + Supabase

Four-phase migration of the single-file Arabic financial operations app for
شركة الرحالة. Each phase has explicit deliverables and exit criteria so the
next phase can start cold.

---

## Phase 1 — Database foundation *(this prompt)*

**Deliverables**
- `supabase/migrations/0001_initial_schema.sql` — enums, tables, indexes.
- `supabase/migrations/0002_rls_policies.sql` — RLS on every table; nested
  ownership for `exchanges` derived through `companies.owner_id`.
- `supabase/migrations/0003_functions.sql` — `archive_daily_transfers`,
  `archive_daily_buys` (with pending-blocks-archive check), `next_reference`.
- `docs/migration-mapping.md` — JS shape → Postgres shape, function
  inventory, behavioral quirks called out.
- `docs/phase-plan.md` — this file.

**Out of scope (do NOT do in Phase 1)**
- Flutter scaffold, `pubspec.yaml`, package installs.
- Any Dart code.
- Auth UI / email templates.

**Exit criteria**
- Migrations apply cleanly on a fresh Supabase project (`supabase db reset`).
- RLS verified by smoke test: a second user cannot see the first user's rows.
- `next_reference` and the two archive RPCs invokable with `auth.uid()`-scoped
  calls and refuse cross-tenant calls.

---

## Phase 2 — Flutter scaffold, Supabase client, Auth, providers, repositories

**Deliverables**
- `pubspec.yaml` with: `flutter_riverpod`, `supabase_flutter`, `intl`,
  `go_router`, `flutter_localizations`.
  *Deviation from Phase 1 target-state*: `riverpod_annotation` and
  `freezed` were dropped to skip codegen, keeping the project runnable
  without `build_runner`. Riverpod is still 2.x; data classes are plain
  immutable Dart. Revisit if generated providers/models become valuable.
- Folder layout:
  ```
  lib/
    core/        # supabase client init, theming, routing, error types
    features/
      auth/{data,domain,presentation}
      companies/{data,domain,presentation}
      clients/{data,domain,presentation}
      transfers/{data,domain,presentation}
      currency_buy/{data,domain,presentation}
      archive/{data,domain,presentation}
    shared/      # widgets, formatters
  ```
- `core/supabase.dart`: `Supabase.initialize(...)`, `supabaseProvider`.
- `core/router.dart`: `go_router` with auth gate.
- `MaterialApp.router` set to RTL + Arabic locale (`Locale('ar')`) as default
  with `Directionality.rtl`.
- Auth: email/password sign-in/sign-up. Profile rows are auto-created
  by the `on_auth_user_created` trigger in
  `supabase/migrations/0005_auth_triggers.sql` — no client-side upsert.
- Domain models (`freezed`): `Company`, `Exchange`, `Client`, `Transfer`,
  `CurrencyBuy` matching the SQL schema.
- Repositories (one per feature) wrapping the Supabase client; no UI code
  may touch `SupabaseClient` directly.
- Riverpod providers for: current session, profile, companies+exchanges
  list, clients list, daily transfers, archived transfers, daily buys,
  pending buys, archived buys.
- An `archiveTransfersProvider` / `archiveBuysProvider` action wrapping the
  two RPCs, plus a `nextReferenceProvider(companyId)` wrapping
  `next_reference`.

**Exit criteria**
- `flutter analyze` clean; build_runner generates without errors.
- App launches to a login screen on web + Android + iOS (smoke).
- Logged-in user can `select` their (empty) collections via providers.
- Repositories have integration tests against a local Supabase instance for
  the happy path of each table.

---

## Phase 3 — UI screens with exact feature parity *(this prompt)*

Three tabs from the source, ported screen-for-screen. Arabic strings are
preserved verbatim. Atomicity for balance mutations is now in
`supabase/migrations/0004_record_functions.sql`
(`record_transfer`, `record_currency_buy`, `record_pending_buy`).

**Deliverables**
- `features/transfers/presentation/transfers_screen.dart`
  - Setup panel (`toggleSetupPanel`): add new "my company + exchange + start
    ref + initial balance + our code".
  - Pair selector → live populates exchange, balance, sender code, and the
    auto-generated reference (calls `next_reference`).
  - Form: amount, beneficiary name, beneficiary account/company, beneficiary
    code; submit composes the Arabic transfer message (matching
    `generateAllMessages` line 722 verbatim) and shows it in an "output"
    card with copy/share.
  - "Save to daily list" persists the transfer **and** decrements
    `exchanges.balance` in the same transaction (Supabase RPC or
    repository-level transaction).
  - Daily-transfers table + "إقفال وترحيل…" button calling
    `archive_daily_transfers`.

- `features/currency_buy/presentation/currency_buy_screen.dart`
  - Client panel (`toggleClientPanel`): add new client.
  - Pair selector + client selector + USD amount + rate → live LYD compute
    (`calculateBuyLocal`).
  - Two actions: "قيد التنفيذ" → insert with `status='pending'`;
    "تأكيد الشراء" → insert with `status='daily'` and increment
    `exchanges.balance` by `usd_amount` in the same transaction.
  - Tables: pending list + daily-buys list + archive button calling
    `archive_daily_buys`.

- `features/archive/presentation/archive_screen.dart`
  - Two read-only tables: archived transfers (red, prefixed `-`) and
    archived buys (green, prefixed `+`), each with a totals row.

- Companies and Clients management surfaced as bottom-sheet/setup panels
  inside the relevant tabs (matches source).

**Hard rules**
- No new business rules; no new fields. Anything not in source ⇒ stop and
  ask.
- Balance mutations and the matching insert MUST happen atomically.
  Recommend a Postgres function `record_transfer(...)` /
  `record_currency_buy(...)` (added in a Phase 3 migration `0004_*.sql`),
  rather than client-side two-step writes.
- Reference field is read-only in the UI; it comes from
  `next_reference(company_id)` only.

**Exit criteria**
- A user can complete each of the three workflows end-to-end against a
  shared Supabase project, see the same Arabic UI, and produce the same
  message strings as the HTML version.
- Side-by-side test against `project_web.html` for: balance after a
  transfer, balance after a buy, pending buy that blocks archival, archive
  totals.

---

## Phase 4 — Polish *(this prompt)*

**Deliverables (done)**
- `lib/shared/formatters.dart` — `formatMoney` (Latin, source-parity) and
  `formatMoneyArabic` (Arabic-Indic). `parseMoney` accepts both digit
  systems plus the Arabic decimal/thousands separators.
- `lib/shared/share.dart` — `shareText` uses `share_plus` with a
  clipboard fallback that mirrors the source `alert("تم النسخ!")`.
- `lib/shared/pdf_export.dart` — `pdf` + `printing` based exporter with
  RTL layout and a bundled Arabic font (Noto Naskh Arabic). Used by the
  daily-transfers, daily-buys, and both archive sections.
- `lib/shared/cache.dart` + `SharedPreferences` override in `main.dart`
  — disk-backed read cache. Repositories serve cached rows when the
  Supabase call throws (offline / network error). Writes still go live;
  no queue-and-replay yet.

**In-app icons** — `font_awesome_flutter` provides the bottom-nav and
appbar icons (`paperPlane`, `moneyBillTransfer`, `boxArchive`,
`rightFromBracket`). No designed image assets required for now.
Material icons remain the default everywhere else.

**App theme font** — `NotoArabic` is registered as a 4-weight family
(400/500/600/700) and set as the default `fontFamily` in
`buildAppTheme()`.

**Deliverables (deferred per user request)**
- Launcher icon + splash screen (would use `flutter_launcher_icons`).
- Write-side offline queue. Today's cache only protects reads.
- Accessibility audit (contrast / font sizes / screen reader labels).

**Exit criteria**
- App store-ready build for Android + iOS, plus a deployable web build.
- Basic e2e test on a CI runner exercising one transfer + one buy +
  archival.

---

## Cross-phase guardrails

- All money in DB stays `numeric(14,2)`. No `float`/`double` for amounts.
- All SQL identifiers in `snake_case` English; user-facing strings stay
  Arabic.
- New behaviour beyond the source must be flagged and confirmed before
  implementation.
- Reference-number formula stays bug-for-bug compatible with line 711
  unless explicitly renegotiated (see `migration-mapping.md` §2).
