# Migration mapping — `rahala_db_v21` → Postgres

Source: `project_web.html` (single-file localStorage app, key `rahala_db_v21`).
Target: Supabase Postgres (migrations `0001`–`0003`).

## 1. Data structure mapping

| JS path (in `db`) | Shape in source | Postgres target | Notes |
|---|---|---|---|
| `db.companies[]` | `{ name, startRef, exchanges: [...] }` | `companies` | Flattened: `exchanges` becomes its own table. Add `owner_id`, `id`, `created_at`. |
| `db.companies[].exchanges[]` | `{ name, balance, ourCode }` | `exchanges` | `balance` → `numeric(14,2)`. Ownership derived through `companies.owner_id` (no direct `owner_id` column). |
| `db.clients[]` | `{ name, company, code }` | `clients` | `company` (string, free text from source) preserved as `company` column. |
| `db.dailyTransfers[]` | `{ date, ref, beneficiary, amount }` | `transfers` where `status = 'daily'` | `date` (display string in source) → `created_at timestamptz`. `ref` → `reference`. `beneficiary` → `beneficiary_name`. Source loses the link back to company/exchange — we recover it by storing `company_id` + `exchange_id` at write time (the UI already has them via `senderCompany` / `displayExchangeCo`). `beneficiary_account_company` and `beneficiary_code` are captured from the existing form fields (`beneficiaryAccountCompany`, sender/beneficiary codes used to compose the message at line 722). |
| `db.globalSold[]` | same shape as `dailyTransfers` (the source uses `concat`) | `transfers` where `status = 'archived'` | `archive_daily_transfers()` flips status and stamps `archived_at`. |
| `db.dailyBuy[]` | `{ date, usd, account }` | `currency_buys` where `status = 'daily'` | `account` is a composed string `"${myCoName} / ${exName}"` in source — replaced by FKs `my_company_id` + `exchange_id`. `usd` → `usd_amount`. `rate` and `lyd_amount` (computed in `calculateBuyLocal`) are persisted explicitly. |
| `db.currencyPending[]` | `{ id, client, usd }` | `currency_buys` where `status = 'pending'` | `client` (free-text in source) is matched to `client_id` when possible, else captured in `client_from_account`. |
| `db.globalBought[]` | same shape as `dailyBuy` | `currency_buys` where `status = 'archived'` | `archive_daily_buys()` flips status; refuses when any `pending` rows still exist for the caller. |

### Money & numeric types
All currency columns use `numeric(14,2)`; `rate` uses `numeric(10,4)`. The
source stored money as strings (`toFixed(2)`); we parse on import.

### Identity / ownership
- `auth.users` → `profiles` (1:1) is the root owner.
- `companies`, `clients`, `transfers`, `currency_buys` all carry an
  `owner_id` and are protected by per-row RLS.
- `exchanges` has no `owner_id`; RLS joins through `companies` so a single
  source of truth governs nested ownership.

## 2.1 Reference-number format — updated 2026-04-26

`supabase/migrations/0006_next_reference_format.sql` reformats `next_reference()`. The user-typed `start_ref` is now parsed as `(prefix)(digits)` — first transfer for a company with `start_ref = 'RZ001'` returns `RZ001`, the second `RZ002`, the third `RZ003`. If `start_ref` doesn't end in digits, the function falls back to `start_ref || lpad(count+1, 3, '0')`.

## 2. Reference-number formula — quirk worth flagging

Source (project_web.html:711):

```js
company.startRef + "-" + (db.dailyTransfers.length + db.globalSold.length + 101)
```

This counts **every transfer the user owns** (daily + archived), not just
those belonging to the selected company. The Phase 1 spec also said
"count of all transfers for company"; the hard constraint says "match line
711". I matched the JS verbatim (cross-company count) and used `start_ref`
from the selected company only as the prefix. **Confirm before Phase 2**
whether this should switch to per-company counting; if so, change the
`select count(*)` in `next_reference` to filter by `company_id`.

## 3. Enforcement added beyond source

- `archive_daily_buys` raises if any `pending` currency buys exist for the
  caller. The source UI shows pending rows but never blocks archival; the
  Phase 1 spec asks us to enforce it.
- All money columns carry `check (... > 0)` / `>= 0` constraints. The
  source had no validation beyond `if (usd <= 0) return;` for pending buys.

## 4. JS function inventory and phase ownership

| JS function (project_web.html) | Purpose | Phase that implements it |
|---|---|---|
| `saveDB` / load on line 539 | localStorage persistence | Phase 2 (replaced by Supabase repositories) |
| `formatNumber` / `cleanNumber` / `formatInput` | Number formatting | Phase 4 (Arabic-aware via `intl`) |
| `switchTab` (l. 558) | Tab navigation | Phase 3 |
| `archiveAllDailyTransfers` (l. 588) | Archive daily transfers | Phase 2 (RPC `archive_daily_transfers`) + Phase 3 (button) |
| `archiveAllDailyBuy` (l. 598) | Archive daily buys | Phase 2 (RPC `archive_daily_buys`) + Phase 3 (button) |
| `saveToDailyList` (l. 608) | Save outgoing transfer + decrement balance | Phase 2 (repository) + Phase 3 (form) |
| `processCurrencyBuy` (l. 626) | Save USD buy + increment balance | Phase 2 + Phase 3 |
| `setBuyStatus` (l. 644) | Toggle pending vs immediate buy | Phase 3 |
| `renderTables` (l. 660) | Render daily/archive lists | Phase 3 |
| `toggleSetupPanel` / `toggleClientPanel` (l. 683/689) | UI toggles | Phase 3 |
| `goBack` (l. 695) | Navigation | Phase 3 |
| `syncCurrentData` (l. 700) | Compute balance + reference for selected pair | Phase 2 (RPC `next_reference` + provider) + Phase 3 |
| `generateAllMessages` (l. 716) | Build the Arabic transfer message | Phase 3 |
| `shareMessage` (l. 728) | Copy/share | Phase 4 (`share_plus`) |
| `saveNewRelation` (l. 736) | Add company + exchange | Phase 2 (repository) + Phase 3 |
| `saveNewClient` (l. 747) | Add client | Phase 2 + Phase 3 |
| `initSelectors` (l. 756) | Populate "my company" dropdown | Phase 3 |
| `loadRelatedExchanges` (l. 761) | Cascade exchange dropdown | Phase 3 |
| `initBuySelectors` (l. 766) | Populate buy-tab company dropdown | Phase 3 |
| `loadBuyExchanges` (l. 771) | Buy-tab exchange dropdown | Phase 3 |
| `updateClientsList` (l. 776) | Render clients list | Phase 3 |
| `loadClientAccounts` (l. 781) | Cascade client account select | Phase 3 |
| `autoFillClientCode` (l. 789) | (no-op stub in source) | Skip |
| `calculateBuyLocal` (l. 791) | Compute LYD = USD × rate | Phase 3 (UI), value persisted on save |
| `updateBuyMessages` (l. 797) | Build Arabic buy message | Phase 3 |
| `shareBuyMsg` (l. 805) | Share buy message | Phase 4 |
| `updateDateTime` (l. 813) | Header clock | Phase 3 |
| `autoFillTestData` (l. 819) | Dev seeding | Phase 4 (debug-only) or drop |
| jsPDF (script tag l. 8) | PDF export | Phase 4 (`pdf` package) |
