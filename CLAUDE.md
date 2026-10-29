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
- Database: `supabase db reset` (local) or `supabase db push` (linked) applies all migrations (0001–0094) in order.

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
supabase/migrations/0001..0094    # schema, RLS, RPC functions, auth, licence, employees + permissions, notifications, backups, post-on-save, cancellations
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

### Balance adjustments and the dinar treasury (migration 0086)

A dollar balance moves only inside the database's functions: a trigger refuses a direct `update exchanges set balance` from the app (`balance_direct_edit`), and `ExchangesRepository.update` no longer sends the balance (it used to send back the value read when the dialog opened, undoing any operation saved meanwhile). The administrator corrects a balance with `admin_adjust_balance(account, new balance, reason, password)` (same 5-tries lock as cancellations); `balance_adjustments` is append-only, shown in the account statement (`buildAccountStatement` / `openingBalanceAt` take `adjustments`), and leaves the cost alone. Every rated exit / entry stores `lyd_method` ('cash' / 'bank'; an older build = cash). The dinar treasury (`lyd_treasury`, `lyd_movements`, `lyd_counts`; `lyd_open`, `lyd_add_movement`, `lyd_record_count`, `lyd_summary`) is computed from the opening: box/bank + exits − entries by method ± movements; the end-of-day count may post the difference. UI: «الخزينة» → «خزينة الدينار», «تسوية الرصيد» per account, the cash/bank selector under the rate. PDFs: rate and dinar columns + a dinar total in the daily and period entry/exit reports; `pdf_export_treasury.dart` (part of `pdf_export.dart`) has the profit report and the treasury report. The WhatsApp messages never change.

### Operations integrity (0087, fixed by 0089) and one-subscriber restore (0088)

Phase 1 of `docs/accounting-audit-and-plan.md` (the audit of 2026-10-29). `record_transfer` / `record_currency_buy` take `p_request_id` (the app sends `newRequestId()` from `lib/shared/request_id.dart`, kept while the form is unchanged): the same request again returns the saved row instead of saving and moving the balance twice (unique `(owner_id, request_id)`). The transfer reference is given inside `record_transfer` under `pg_advisory_xact_lock('eshary.ref:'||admin)` and an active reference is unique (`transfers_owner_ref_active_uq`). An employee allowed to type a rate is refused beyond 15 % of the administrator's last rate (`rate_unusual`). An account is opened only through `admin_open_account(company, name, balance, code, country, cost)` — its balance, a `balance_adjustments` row with `kind='opening'` («رصيد افتتاحي» in the statement) and the opening cost in one transaction (a balance above 0 needs a cost); a direct insert with a balance, a negative balance, and deleting an account/company with a balance or history (`account_has_history`) are refused. Dinar movements and counts lock `lyd_treasury`; dinar-paid saves take it `for share`. `owner_wipe_operations(p_password)` needs the password, clears costs, adjustments and the dinar treasury too, and moves each company's `start_ref` to the next number so no reference is ever given twice. `record_pending_buy` is revoked. 0088: `admin_backup_owners(backup)` / `admin_restore_owner(backup, owner)` restore ONE subscriber from a stored backup; the backup screen asks «مشترك واحد» or «المنصة كلها» first. 0089 (review fixes): the wipe takes its safety copy before moving `start_ref` and locks the accounts first; a one-subscriber restore refuses a backup without that subscriber (`owner_not_in_backup`) and never lets a company's numbering go back; an account already below zero may come back up; `next_reference` (now via `_next_reference_for`) grows a digit past 9999 instead of cutting it (lpad). 0086–0088 refuse to run again once a later file is applied. Client side: the archive lists, expenses and adjustments are fetched page by page (no silent 1000-row cut), the 5 s full re-download is gone (realtime filtered by owner; a poll every 15 s only while realtime is down, else every 60 s), day and period limits are Libya days (`libyaToday` / `libyaDayStart` in `lib/shared/libya_time.dart`), the movement report counts commissions and adjustments, PDFs allow 1000 pages with «صفحة س من ص» and the amount in words includes the cents.

### Selling and buying on credit (0091)

Phase 2, part 1. A sale names the customer who pays the dinars (`transfers.customer_id`, picked from the saved customers) and `lyd_paid` (what was paid now; the database treats a missing `p_lyd_paid` as "all of it", so older builds stay paid in full); a purchase has `lyd_paid` too and its sender is the creditor. The unpaid part goes to the append-only `customer_lyd_entries` (+ the customer owes us; kinds sale / buy / sale_cancel / buy_cancel / collect / pay / opening); a cancel trigger reverses it. `clients.credit_limit` (null = no credit) changes only via `set_customer_credit_limit`; an employee's sale over it is refused (`credit_limit_exceeded`, without the amounts), the administrator is asked and resends with `p_over_limit`. `customer_add_entry` (collect / pay with a pocket, opening signed), `customer_balances()`, `customer_statement(client, from, to)` are administrator only. The dinar treasury counts `lyd_paid` plus collections and payments. Lock order: exchanges → clients → lyd_treasury everywhere. Restores fill `lyd_paid = lyd_amount` for backups made before 0091; backups, restores, the redaction, the wipe and `delete_party` know the new table. UI: the payment selector (`lyd_method_selector.dart`: نقدًا / مصرفي / آجل / جزئي, `CreditCustomerField`, `confirmOverCreditLimit`), `lib/features/customers` («ذمم العملاء» from «الخزينة», the statement with collect / pay / opening / limit and its PDF `buildCustomerStatement`). 0089 refuses to run again after 0091.

### The general ledger (0092)

Phase 2, part 2. A double-entry journal in dinars is DERIVED, never stored: `_journal(owner)` (internal) turns the append-only records (transfers, currency_buys, operation_costs, account_cost_events, balance_adjustments, account_expenses, customer_lyd_entries, lyd_treasury, lyd_movements) into lines (+ debit, − credit) that sum to zero per source; the save functions are untouched. Chart: 1100 box, 1110 bank, 1200 customers (net), 1300 dollars at cost, 1390 dollars without a cost (released into 1300 by the account's 'opening' cost event), 3100 capital and openings (dinar deposits / withdrawals too), 3150 cost corrections, 3200 cash outside the dinar treasury (before it opened, rate-less operations), 4100 result of selling currency, 4200 count over, 4300 adjustment gains, 5100 adjustment losses, 5200 count short, 5300 commissions, 5900 rounding. Cancels value the dollars at the cost of that moment (`_cost_at`), as the cost logic does. Invariants (tested in `supabase/tests/ledger92_test.mjs` and `ledger92_cases_test.mjs`): 1100/1110 = `_lyd_position`, 1200 per client = its `customer_lyd_entries`, 1300 per account = balance × cost (cents). Administrator RPCs: `ledger_trial_balance`, `ledger_income_statement`, `ledger_balance_sheet`, `ledger_journal` (≤ 3000 lines), `close_period(end ≤ now − 5 min)` / `ledger_closes()` (the trial balance sealed with `_trial_seal`: md5 of account:debit:credit, names excluded; `intact` = the books up to that moment are unchanged), `reconcile_account` / `account_reconciliations_list` (`_balance_at` = the dollar balance at a moment). UI: `lib/features/ledger` («الحسابات الختامية» and «مطابقة الكشف» per account in «الخزينة»), PDFs `buildIncomeStatement` / `buildBalanceSheet` / `buildTrialBalance`. 0091 refuses to run again after 0092.

### Cash and bank books (0093)

In Libya the dollar is priced differently in cash dinars and in bank dinars (cheques), so every account's dollars live in two BOOKS: `account_books(exchange_id, book 'cash'|'bank', balance, cost_rate)`; cash + bank = `exchanges.balance` always (every function moves the book with the account; a trigger keeps platform edits in step; a book never goes below zero). Each book has its own weighted-average cost, rates (`last_exchange_rates` kinds sell_cash / sell_bank / buy_cash / buy_bank; `current_exchange_rates()` returns the four plus `sell`/`buy` = cash for old builds), customer debts (`customer_lyd_entries.book`), pocket (cash = the box, bank = the bank) and ledger lines (`_journal` lines carry `book`). Operations carry `book` (`record_transfer` / `record_currency_buy` `p_book`; an old build's `p_lyd_method` stands for it; rows before 0093 count as bank for dollars). A sale above its book's dollars is refused (`book_insufficient`); the administrator moves dollars with `move_between_books(account, from, usd, price)` (result 4500, clearing 3300). Dinar conversions have two amounts (`lyd_add_movement(..., p_amount_in)`, result 4400). At migration every account's dollars went to the bank book; `set_account_books(account, cash_qty, cash_cost, bank_cost)` splits them ONCE (refused after the cash book was used; `books_split_at` is protected). Statements take `p_book` (null = combined, bank × `p_bank_factor`). `account_books_list()`, `set_account_cost(..., p_book)`, `admin_adjust_balance(..., p_book)`, `record_account_expense(..., p_book)`, `admin_open_account(..., p_book)`, `customer_add_entry(..., p_book)`, `customer_statement(..., p_book)`. UI: the selector (نقدًا = cash book, مصرفي = bank book; آجل / جزئي ask the book), `BooksSection` in «الخزينة» (split, move), «المبلغ الواصل» in the dinar conversion, per-book customers, the ledger's book chips + factor. Go-live: back up, apply 0093 at the end of the day, publish the APK right after (the new build fails against 0092), split every account, save one sale and one purchase per book so the four rates are real. 0086 and 0090–0092 refuse to run again after 0093. Tests: `supabase/tests/books93_test.mjs`.

### Phase 3: load review and opening balances (0094, 2026-10-29)

A review committee (DB concurrency, DB speed, client bugs, client speed/size) and a load test.

0094:
- «رصيد أول المدة»: `admin_set_opening(account, book, usd, cost)` gives a book that never moved its first dollars at cost. It writes a balance_adjustments 'opening' line plus the 'opening' cost event, like `admin_open_account`. It is once per book (`opening_already_set`), and an unsplit account holding dollars is refused (`books_not_split`). Screen: `lib/features/treasury/presentation/opening_balances_screen.dart`, opened from «إعدادات الحوالات»; it also opens the dinar treasury.
- The cancellations use `_admin_password_error`, because parallel guesses beat the old inline limit.
- A cancellation locks the customer and `lyd_treasury` the way the saves do.
- `record_currency_buy` answers a retried request before checking the rate.
- `_next_reference_for` reads the highest number from `transfers_owner_refnum_idx`.
- `lyd_add_movement` / `move_between_books` / `record_account_expense` take `p_request_id`. The app keeps one id per set of form values with `RequestIdKeeper` (`lib/shared/request_id.dart`).
- Owner indexes.
- The credit limit is ONE limit over both books (`record_transfer` checks `_customer_balance(customer)`, both books). The owner decided this on 2026-10-29; under 0093 it was per book, so a customer could owe the limit twice.
- 0093 refuses to run after 0094, and the app needs 0094 because it sends `p_request_id`.
- Tests: `supabase/tests/opening94_test.mjs`.

The load test runs on a SEPARATE Supabase project only: `supabase/tests/load/load93.mjs`. It refuses the production ref and any non-empty database without its marker. Dry run: `load/local-server.mjs`.

Client (data, battery, speed):
- The history providers (`archived*`, `daily*`, `pendingBuys`) are autoDispose, and the shells build a non-form tab only while it is shown; the sale/purchase forms stay alive. The full history is no longer re-downloaded every minute.
- The employee's row filter is watched through `currentEmployeeProvider.select(ownRowsOf)`, so the 45 s identity check re-reads nothing.
- Realtime is the main signal. The safety poll runs every 5 min while connected (15 s while not), and the clients list refreshes every 5 min.
- Info logs are not persisted in release.
- The splash waits 0.7 s and no longer awaits the profile upsert.
- `LiquidBackground` is painted once (no animation, no full-screen blur), and `GlassCard` / `GlassPanel` have no backdrop blur.
- PDF fonts are loaded once, and the statement's four reads run together.
- Sale/purchase:
  - the form is locked while saving;
  - a locked rate is re-read at save, and an employee is told when the administrator changed it;
  - `Client` compares by id;
  - the sale screen checks the book's dollars (administrator).

### Wording: بيع / شراء (2026-10-29)

The owner renamed the operations everywhere the app shows them: an exit («خروج») is «بيع» and an entry («دخول») is «شراء» — screens, totals («إجمالي البيع / الشراء»), PDF reports, permissions, alerts, and the two employee messages sent by the database (0090). Code identifiers stay transfer / buy / exit / entry. NOT renamed: the sign-in wording («تسجيل الدخول», «تسجيل الخروج», «كود الدخول», «دخول حسابي») and the WhatsApp messages (`_composeMessages` / `_composeBuyMessages`), which never change.

### Database

All currency columns are `numeric(14,2)`; `rate` is `numeric(10,4)`. Per-row RLS on every table; `exchanges` has no `owner_id` and derives ownership by joining through `companies.owner_id`. Profile rows are auto-created by the `on_auth_user_created` trigger in `0005_auth_triggers.sql` — no client-side profile upsert.

Server-side functions:
- `next_reference(company_id)` — generates the transfer reference. Format updated by `0006_next_reference_format.sql`: parses user-typed `start_ref` as `(prefix)(digits)` and increments. **Counts every active transfer the user owns across all companies**, matching `project_web.html:711`, except that since `0080_reference_skips_cancelled.sql` (asked for by the user on 2026-10-28) a cancelled transfer does not count: if the last transfer is cancelled the next one reuses its number, and the result is never below the highest active number + 1 (no going back, no repeat of an active number). See `docs/migration-mapping.md` §2 — do not change to per-company counting without explicit confirmation.
- `archive_daily_transfers(p_owner)` / `archive_daily_buys(p_owner)` — legacy; since 0047 nothing is left in `status='daily'`, so they do nothing.

### UI conventions

- Default locale `Locale('ar')`, `Directionality.rtl` wraps the whole tree, `ThemeMode.dark`. The screens use `Almarai` (Regular, Bold, ExtraBold; the theme's family). `NotoNaskhArabic-Regular/Bold.ttf` stay in `assets/fonts/` for the PDF reports only (loaded by path; the Light, Medium and SemiBold files were removed in phase 3).
- The PDF exporter in `lib/shared/pdf_export.dart` requires the Noto Naskh Arabic TTFs in `assets/fonts/` — without them PDF export crashes at font load time.
- A `LiquidBackground` wraps the app in `main.dart`; screens use `Scaffold(backgroundColor: Colors.transparent, extendBodyBehindAppBar: true)` with frosted-glass app bars / nav.
- User-facing strings are Arabic; SQL identifiers and Dart code are English `snake_case` / `camelCase`.
- `friendlyError(Object e)` in `lib/shared/logger.dart` maps backend errors (RLS, FK, pending-buy block, network, auth) to short Arabic messages — use it for any user-visible error display rather than raw exception strings.

## Hard rules from `docs/phase-plan.md`

- Money columns stay `numeric(14,2)`. Never use `float`/`double` for amounts.
- The reference-number formula stays compatible with `project_web.html:711` unless explicitly renegotiated (renegotiated once: 0080, cancelled transfers give their number back).
- Arabic transfer/buy message strings are preserved verbatim from the source HTML (`generateAllMessages` line 722 / buy variant).
- Reference field is read-only in the UI; values come from `next_reference(company_id)` only. Since 0087 `record_transfer` calls it itself at save time under a per-administrator lock (the number the phone sends is ignored) and the app shows the saved `reference` in the messages.
- New behaviour beyond the source must be flagged and confirmed before implementation. The intentional additions are listed in the README's "Behavior added beyond source" section (pending blocks archive, atomic RPCs, per-user RLS, offline read cache).

## Configuration

Supabase credentials are passed as `--dart-define`:

```
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

`Env.isConfigured` (`lib/core/env.dart`) is checked at startup; missing values render `_MissingConfigApp` instead of crashing.
