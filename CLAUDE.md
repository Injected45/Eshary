# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Eshary (شركة الرحالة) — a Flutter + Supabase Arabic financial-operations app. It is a port of `project_web.html` (a single-file localStorage app keyed `rahala_db_v21`); that file is preserved at the repo root as the source of truth for legacy behaviour. Three workflows: outgoing USD transfers, USD purchases from clients, and a per-period archive of both.

## Common commands

The `.bat` files at the repo root bake in the developer Supabase URL / anon key as `--dart-define`s — running `flutter run` without those defines launches `_MissingConfigApp` (see `lib/main.dart`) instead of the real app.

- `run-android.bat` — auto-boots `Medium_Phone_API_36` emulator if no device is connected, then `flutter run` in debug.
- `run-web.bat` — `flutter run -d chrome --web-port=3001`. Hot reload (`r`) is unsupported on Flutter web; use `R` for hot restart.
- `build-apk.bat` — builds the 64-bit and 32-bit release APKs into `APK/`. Release builds are signed with the app's permanent keystore, which lives **outside the repo** in `D:\ai\Eshary-keystore\` (`android/key.properties` points at it; both are gitignored and must never be committed). Without `key.properties` the release build fails on purpose instead of falling back to the debug key.
- `build-aab.bat` — builds the **Google Play bundle** (`APK/Eshary-play.aab`). It sets `ESHARY_PLAY=1` (Gradle then uses `android/app/src/play/AndroidManifest.xml`: no foreground service, no battery-optimisation exemption, no boot receiver) and `--dart-define=PLAY_BUILD=true` (`lib/core/build_flavor.dart`). Set `SUPPORT_EMAIL` inside it before the first upload. See `docs/play-store-readiness.md`.
- `build-aab.bat` — builds the **Google Play bundle** (`APK/Eshary-play.aab`). It sets `ESHARY_PLAY=1` (Gradle then uses `android/app/src/play/AndroidManifest.xml`: no foreground service, no battery-optimisation exemption, no boot receiver) and `--dart-define=PLAY_BUILD=true` (`lib/core/build_flavor.dart`). Set `SUPPORT_EMAIL` inside it before the first upload. See `docs/play-store-readiness.md`.
- `flutter pub get` — install deps.
- `flutter analyze` — lint (config in `analysis_options.yaml`: `flutter_lints` + `strict-casts` / `strict-inference` / `strict-raw-types`, plus `prefer_const_constructors`, `avoid_print`, `require_trailing_commas`).
- `flutter test` — runs the suite (currently `test/formatters_test.dart`). A single test: `flutter test test/formatters_test.dart --plain-name "<name>"`.
- Database: `supabase db reset` (local) or `supabase db push` (linked) applies all migrations (0001–0085) in order.

## In-app update (direct APK only)

`build-apk.bat` raises the build number (pubspec `version: x.y.N+N`), passes `--dart-define=APP_BUILD=N` and writes `APK/build.json`; `publish-update.bat` uploads both APKs to the public Storage bucket `app-releases`, re-downloads them to check the SHA-256, then inserts the row in `app_releases` (migration 0079). The app (`lib/features/app_update`, mounted in `main.dart` as `UpdateGate`) asks `latest_app_release()` on start and on resume and shows a blocking update screen. Never in the Play build (`kPlayBuild`) or a debug run (`APP_BUILD` = 0). `REQUEST_INSTALL_PACKAGES` and the FileProvider are only in the main manifest, never `src/play`. Withdraw a bad release with `withdraw-update.bat` or from the platform. See `docs/app-updates.md`. The first APK that contains the updater must still be sent by hand.

## Admin platform (admin-web/)

A separate Next.js + TypeScript web app ("ESHARI Admin") that administers the SAME Supabase project: staff sign in with password + a WhatsApp code, and the code step is enforced in the database (migration 0077: `platform_staff`, `platform_sessions`, `_platform_role()`; `is_caller_admin()` also answers true for a verified super_admin/admin). See `admin-web/README.md`. Commands: `cd admin-web && npm test`, `npx tsc --noEmit`, `npx next build`; DB test: `cd supabase/tests && node platform77_test.mjs`. Never commit `.env*` or the service-role key. When a migration re-creates a CHECK constraint (e.g. `wa_challenges_purpose_check`) keep every value earlier migrations added.

## Architecture

### Layered, feature-sliced

```
lib/
  main.dart                       # bootstraps Supabase, prefs, logger, RTL MaterialApp.router
  core/                           # env, theme, router, supabase_provider
  shared/                         # cache, formatters, share, pdf_export, logger, glass, audio_feedback, liquid_background
  features/<feature>/{data,domain,presentation}
supabase/migrations/0001..0085    # schema, RLS, RPC functions, auth, licence, employees + permissions, notifications, backups, post-on-save, cancellations
```

Features: `auth`, `companies`, `clients`, `transfers`, `currency_buy`, `archive`, `home`, `splash`, `onboarding`, `profile`, `settings`, `logs`, `countries`, `exchange_companies`. Each follows the `data` (repository) / `domain` (immutable Dart model with `fromJson`) / `presentation` (Riverpod providers + screens) split.

### State and data flow

- Riverpod 2.x, plain providers — **no codegen** (`riverpod_annotation` + `freezed` were intentionally dropped per `docs/phase-plan.md` Phase 2). Models are hand-written immutable Dart with `fromJson`.
- `core/supabase_provider.dart` exposes `supabaseClientProvider`, `authStateChangesProvider`, `currentSessionProvider`, `currentUserIdProvider`. UI **must not** touch `SupabaseClient` directly — go through repositories.
- Repositories live in `features/<feature>/data/` and inject `SupabaseClient` + `JsonCache`. They wrap reads in a try/cache fallback (write to `JsonCache` on success, serve `JsonCache` on error). Writes are live-only — no offline write queue exists.
- `JsonCache` (`lib/shared/cache.dart`) is a thin `SharedPreferences` JSON store. Keys are scoped per signed-in user (`cache:<table>:<uid>:<status>`). The `sharedPreferencesProvider` is overridden in `main.dart` after `SharedPreferences.getInstance()`.
- Routing: `go_router` in `core/router.dart`. Auth gate redirects unauthed users to `/sign-in`. `_StreamRefresh` bridges `SupabaseClient.auth.onAuthStateChange` into GoRouter's `refreshListenable` so session changes re-evaluate redirects.

### Balance moves at save (critical — changed by migration 0047)

There is **no manual daily close**. `record_transfer` and `record_currency_buy` store the row as `status='archived'` (with `archived_at`) and move `exchanges.balance` in the same transaction: an exit subtracts, an entry adds. So `exchanges.balance` is always the real balance and an employee and the admin see the same figure. (Before 0047 the balance was deferred to `archive_daily_*`; `0017_defer_balance_update.sql` and the `archive_daily_*` functions are kept only for older app builds and now do nothing.)

An exit above the balance is refused by a trigger on `transfers` (`_check_transfer_balance`, 0046/0047): it locks the account row and raises `insufficient_balance`. `admin_restore_backup` sets `eshary.skip_balance_check` so a restore never moves or checks balances. Never write a two-step `insert` + `update balance` from Dart; always go through the RPCs. `record_pending_buy` (legacy) still creates a `pending` row that does not touch the balance.

### Cancellations (migration 0048)

An operation is never deleted or edited. `admin_cancel_operation(kind, id, reason, password, request_id)` checks the admin's password server-side (`crypt` against `auth.users`), the same Libya calendar day, and (for an entry) that the balance covers it; then it moves the balance back, stamps `cancelled_at` and appends a row to `operation_cancellations`. Employees only call `employee_request_cancellation`. `transfers` / `currency_buys` accept no direct insert/update/delete from the API any more. In Dart, `Transfer.netAmount` / `CurrencyBuy.netAmount` (0 once cancelled) feed every total; ledger reports (account statement, movement report) add a reversing line instead.

The exit/entry screens show **today's** executed rows (`todayTransfersProvider` / `todayBuysProvider`: archived rows created today by the phone's local date), so the lists start empty every new day. The "العمليات" tab (formerly "الإقفالات") is the permanent record. The permissions `archive_transfers` / `archive_buys` / `archive_all` are retired.

### The Libyan dinar (migration 0081)

Every exit (we sell dollars) and entry (we buy dollars) carries `rate` (`numeric(10,4)`, dinars per dollar) and `lyd_amount` (`numeric(14,2)`). The database computes `lyd_amount = round(round(usd, 2) × rate, 2)` inside `record_transfer` (new optional `p_rate`) / `record_currency_buy` (its `p_lyd_amount` is ignored); the app only previews it with `lydFor()` in `lib/shared/formatters.dart`, which rounds from decimal digits to match. Balances stay in dollars. The new app requires a rate; an older build that sends none (or the old hidden placeholder rate 1 on an entry) is saved with both columns empty, and such rows show "—" and stay out of dinar totals (`netLyd`). An employee without the permission of that kind (`rate_edit_sell` for an exit, `rate_edit_buy` for an entry; migration 0083 split 0081's single `rate_edit` and gave both to whoever had it) always gets the administrator's last rate of that kind (`last_exchange_rates`, read through `current_exchange_rates()`), whatever the phone sent. WhatsApp messages do not mention the dinar. UI: `lib/features/exchange_rates` (`RateFields`, the 15 % "are you sure" check). The PDF reports do not show the dinar yet.

### Cost price of the dollar (migration 0082)

Weighted average cost **per account** (`account_costs`, `numeric(16,6)`), administrator only (`treasury_positions()`, `set_account_cost()`; screen `lib/features/treasury`, opened from «حساباتي»). Only an entry with a rate moves it, inside `record_currency_buy` with the account row locked: `C' = (B×C + q×r) ÷ (B+q)`, B = the balance before; an empty account restarts at r; an account holding dollars with no opening cost is not costed until the administrator sets one. Exits, commissions, balances edited by hand and rate-less entries go in/out at cost (no change). Cancelling an entry (trigger `trg_cost_on_buy_cancel`, which relies on `admin_cancel_operation` moving the balance BEFORE stamping `cancelled_at`) removes its value at its own price. Every change is appended to `account_cost_events`. The cost of each operation lives in `operation_costs` (kind sell/buy; RLS on, no grant) — never on `transfers` / `currency_buys`, which employees can read (0084 moved and dropped the 0082 columns). Cancelling an exit (`trg_cost_on_sell_cancel`) brings its dollars back at that exit's cost; a cancelled entry that was never costed, or that an opening/correction followed, leaves the cost alone. Rates must be in (1, 100] (`rate_out_of_range`; the app parses a comma as the decimal point with `parseRate`). Backups, restores and the redaction include `last_exchange_rates`, `account_costs`, `account_cost_events`, `operation_costs`. 0081–0083 refuse to run again once a later one is applied (re-running them would undo the fixes).

### Profit and loss (migration 0085)

Administrator only: `profit_report(from, to)` per account — realized profit = sell dinars − round(amount × cost at that exit, 2), exits without a rate or a cost counted apart; `treasury_positions()` adds `market_rate` (the last sell rate) and `unrealized` = balance × (market − cost); `account_cost_history()`. UI: «الخزينة» shows the period's profit (`profit_section.dart`), the break-even and unrealized per account and the cost history; the exit screen warns and asks before selling below the account's cost, the entry screen shows the cost after the buy (both admin only, via `accountCostsProvider`).

### Database

All currency columns are `numeric(14,2)`; `rate` is `numeric(10,4)`. Per-row RLS on every table; `exchanges` has no `owner_id` and derives ownership by joining through `companies.owner_id`. Profile rows are auto-created by the `on_auth_user_created` trigger in `0005_auth_triggers.sql` — no client-side profile upsert.

Server-side functions:
- `next_reference(company_id)` — generates the transfer reference. Format updated by `0006_next_reference_format.sql`: parses user-typed `start_ref` as `(prefix)(digits)` and increments. **Counts every active transfer the user owns across all companies**, matching `project_web.html:711`, except that since `0080_reference_skips_cancelled.sql` (asked for by the user on 2026-10-28) a cancelled transfer does not count: if the last transfer is cancelled the next one reuses its number, and the result is never below the highest active number + 1 (no going back, no repeat of an active number). See `docs/migration-mapping.md` §2 — do not change to per-company counting without explicit confirmation.
- `archive_daily_transfers(p_owner)` / `archive_daily_buys(p_owner)` — legacy; since 0047 nothing is left in `status='daily'`, so they do nothing.

### UI conventions

- Default locale `Locale('ar')`, `Directionality.rtl` wraps the whole tree, `ThemeMode.dark`. Two registered font families: `Almarai` (4 weights) and `NotoArabic` (Noto Naskh Arabic, 4 weights). `NotoArabic` is the theme default.
- The PDF exporter in `lib/shared/pdf_export.dart` requires the Noto Naskh Arabic TTFs in `assets/fonts/` — without them PDF export crashes at font load time.
- A `LiquidBackground` wraps the app in `main.dart`; screens use `Scaffold(backgroundColor: Colors.transparent, extendBodyBehindAppBar: true)` with frosted-glass app bars / nav.
- User-facing strings are Arabic; SQL identifiers and Dart code are English `snake_case` / `camelCase`.
- `friendlyError(Object e)` in `lib/shared/logger.dart` maps backend errors (RLS, FK, pending-buy block, network, auth) to short Arabic messages — use it for any user-visible error display rather than raw exception strings.

## Hard rules from `docs/phase-plan.md`

- Money columns stay `numeric(14,2)`. Never use `float`/`double` for amounts.
- The reference-number formula stays compatible with `project_web.html:711` unless explicitly renegotiated (renegotiated once: 0080, cancelled transfers give their number back).
- Arabic transfer/buy message strings are preserved verbatim from the source HTML (`generateAllMessages` line 722 / buy variant).
- Reference field is read-only in the UI; values come from `next_reference(company_id)` only.
- New behaviour beyond the source must be flagged and confirmed before implementation. The intentional additions are listed in the README's "Behavior added beyond source" section (pending blocks archive, atomic RPCs, per-user RLS, offline read cache).

## Configuration

Supabase credentials are passed as `--dart-define`:

```
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

`Env.isConfigured` (`lib/core/env.dart`) is checked at startup; missing values render `_MissingConfigApp` instead of crashing.
