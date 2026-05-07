# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Eshary (شركة الرحالة) — a Flutter + Supabase Arabic financial-operations app. It is a port of `project_web.html` (a single-file localStorage app keyed `rahala_db_v21`); that file is preserved at the repo root as the source of truth for legacy behaviour. Three workflows: outgoing USD transfers, USD purchases from clients, and a per-period archive of both.

## Common commands

The `.bat` files at the repo root bake in the developer Supabase URL / anon key as `--dart-define`s — running `flutter run` without those defines launches `_MissingConfigApp` (see `lib/main.dart`) instead of the real app.

- `run-android.bat` — auto-boots `Medium_Phone_API_36` emulator if no device is connected, then `flutter run` in debug.
- `run-web.bat` — `flutter run -d chrome --web-port=3001`. Hot reload (`r`) is unsupported on Flutter web; use `R` for hot restart.
- `build-apk.bat` — `flutter build apk --release` then copies the universal APK to `Eshary.apk` at the repo root.
- `flutter pub get` — install deps.
- `flutter analyze` — lint (config in `analysis_options.yaml`: `flutter_lints` + `strict-casts` / `strict-inference` / `strict-raw-types`, plus `prefer_const_constructors`, `avoid_print`, `require_trailing_commas`).
- `flutter test` — runs the suite (currently `test/formatters_test.dart`). A single test: `flutter test test/formatters_test.dart --plain-name "<name>"`.
- Database: `supabase db reset` (local) or `supabase db push` (linked) applies migrations 0001–0017 in order.

## Architecture

### Layered, feature-sliced

```
lib/
  main.dart                       # bootstraps Supabase, prefs, logger, RTL MaterialApp.router
  core/                           # env, theme, router, supabase_provider
  shared/                         # cache, formatters, share, pdf_export, logger, glass, audio_feedback, liquid_background
  features/<feature>/{data,domain,presentation}
supabase/migrations/0001..0017    # schema, RLS, RPC functions, auth trigger, beneficiaries, exchange-companies, countries, deferred-balance
```

Features: `auth`, `companies`, `clients`, `transfers`, `currency_buy`, `archive`, `home`, `splash`, `onboarding`, `profile`, `settings`, `logs`, `countries`, `exchange_companies`. Each follows the `data` (repository) / `domain` (immutable Dart model with `fromJson`) / `presentation` (Riverpod providers + screens) split.

### State and data flow

- Riverpod 2.x, plain providers — **no codegen** (`riverpod_annotation` + `freezed` were intentionally dropped per `docs/phase-plan.md` Phase 2). Models are hand-written immutable Dart with `fromJson`.
- `core/supabase_provider.dart` exposes `supabaseClientProvider`, `authStateChangesProvider`, `currentSessionProvider`, `currentUserIdProvider`. UI **must not** touch `SupabaseClient` directly — go through repositories.
- Repositories live in `features/<feature>/data/` and inject `SupabaseClient` + `JsonCache`. They wrap reads in a try/cache fallback (write to `JsonCache` on success, serve `JsonCache` on error). Writes are live-only — no offline write queue exists.
- `JsonCache` (`lib/shared/cache.dart`) is a thin `SharedPreferences` JSON store. Keys are scoped per signed-in user (`cache:<table>:<uid>:<status>`). The `sharedPreferencesProvider` is overridden in `main.dart` after `SharedPreferences.getInstance()`.
- Routing: `go_router` in `core/router.dart`. Auth gate redirects unauthed users to `/sign-in`. `_StreamRefresh` bridges `SupabaseClient.auth.onAuthStateChange` into GoRouter's `refreshListenable` so session changes re-evaluate redirects.

### Deferred balance mutations (critical)

Balance updates are **deferred to archival**. Per-row insert RPCs (`record_transfer`, `record_currency_buy`, `record_pending_buy` — defined in `0004_record_functions.sql`, redefined by `0017_defer_balance_update.sql`) write the row only and do **not** touch `exchanges.balance`. The two `archive_*` functions in `0017_defer_balance_update.sql` aggregate the daily rows per exchange, apply the summed delta to `exchanges.balance`, and flip status — all inside one Postgres transaction. Repositories call all five RPCs via `client.rpc(...)`; never write a two-step `insert` + `update balance` from Dart, and never bypass these RPCs. They are `security invoker` and verify `auth.uid()` ownership.

This means: during the day, `exchanges.balance` does not move when transfers/buys are entered. The balance jumps once when the user runs the close-and-archive action.

### Database

All currency columns are `numeric(14,2)`; `rate` is `numeric(10,4)`. Per-row RLS on every table; `exchanges` has no `owner_id` and derives ownership by joining through `companies.owner_id`. Profile rows are auto-created by the `on_auth_user_created` trigger in `0005_auth_triggers.sql` — no client-side profile upsert.

Server-side functions:
- `next_reference(company_id)` — generates the transfer reference. Format updated by `0006_next_reference_format.sql`: parses user-typed `start_ref` as `(prefix)(digits)` and increments. **Counts every transfer the user owns across all companies**, matching `project_web.html:711` bug-for-bug. See `docs/migration-mapping.md` §2 — do not change to per-company counting without explicit confirmation.
- `archive_daily_transfers(p_owner)` / `archive_daily_buys(p_owner)` — flip `status='daily'` rows to `'archived'` and stamp `archived_at`. `archive_daily_buys` **raises** if any `status='pending'` rows exist for the caller (enforcement added beyond the source).

### UI conventions

- Default locale `Locale('ar')`, `Directionality.rtl` wraps the whole tree, `ThemeMode.dark`. Two registered font families: `Almarai` (4 weights) and `NotoArabic` (Noto Naskh Arabic, 4 weights). `NotoArabic` is the theme default.
- The PDF exporter in `lib/shared/pdf_export.dart` requires the Noto Naskh Arabic TTFs in `assets/fonts/` — without them PDF export crashes at font load time.
- A `LiquidBackground` wraps the app in `main.dart`; screens use `Scaffold(backgroundColor: Colors.transparent, extendBodyBehindAppBar: true)` with frosted-glass app bars / nav.
- User-facing strings are Arabic; SQL identifiers and Dart code are English `snake_case` / `camelCase`.
- `friendlyError(Object e)` in `lib/shared/logger.dart` maps backend errors (RLS, FK, pending-buy block, network, auth) to short Arabic messages — use it for any user-visible error display rather than raw exception strings.

## Hard rules from `docs/phase-plan.md`

- Money columns stay `numeric(14,2)`. Never use `float`/`double` for amounts.
- The reference-number formula stays bug-for-bug compatible with `project_web.html:711` unless explicitly renegotiated.
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
