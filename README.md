# Eshary — شركة الرحالة

Flutter + Supabase port of the single-file Arabic financial-operations app
for شركة الرحالة. Three workflows: outgoing USD transfers, USD purchases
from clients, and a per-period archive of both. Source artifact preserved
at `project_web.html` for reference.

## Stack

- Flutter 3.x (Material 3, RTL, default locale `ar`)
- Riverpod 2.x (`flutter_riverpod`, plain providers — no codegen)
- Supabase Postgres (migrations under `supabase/migrations/`)
- `supabase_flutter` for client + auth + session persistence
- `share_plus`, `pdf` + `printing`, `shared_preferences`, `font_awesome_flutter`

## Layout

```
supabase/migrations/   # 0001 schema → 0005 auth trigger
lib/
  core/                # supabase client, router, theme, env
  shared/              # formatters, share, cache, pdf export
  features/{auth,companies,clients,transfers,currency_buy,archive,home}
                       # each with data/ domain/ presentation/
assets/fonts/          # Noto Naskh Arabic (4 weights)
docs/                  # phase-plan.md, migration-mapping.md
project_web.html       # original single-file app
```

## Database

Five migrations applied in order:

| File | What it does |
|---|---|
| `0001_initial_schema.sql` | Tables, enums, indexes. All money is `numeric(14,2)`. |
| `0002_rls_policies.sql` | RLS on every table. `exchanges` derives ownership through `companies.owner_id`. |
| `0003_functions.sql` | `archive_daily_transfers`, `archive_daily_buys`, `next_reference`. |
| `0004_record_functions.sql` | Atomic insert + balance-mutation RPCs (`record_transfer`, `record_currency_buy`, `record_pending_buy`). |
| `0005_auth_triggers.sql` | Auto-creates `profiles` row on `auth.users` insert. |

Apply with the Supabase CLI: `supabase db reset` (local) or `supabase db push` (linked project).

## Running

1. **Add fonts** — drop Noto Naskh Arabic Regular/Medium/SemiBold/Bold TTFs into `assets/fonts/`. Already there in this repo. Without these, PDF export fails at load time.
2. **Install deps** — `flutter pub get`.
3. **Run** — provide your Supabase project URL and anon key:

   ```sh
   flutter run \
     --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
   ```

   Without these env vars, `main.dart` shows an explanatory screen instead of crashing.

## Behavior preserved verbatim from `project_web.html`

- Reference number formula at line 711: `start_ref + "-" + (count_of_owner_transfers + 101)`. Counts across **all** the user's transfers, not just the selected company's. See `docs/migration-mapping.md` §2 for the open question.
- Arabic transfer message: `السلام عليكم\nيرجى تحويل مبلغ: ...`
- Arabic buy message: `شراء عملة\nتم استلام مبلغ: ...`
- Balance is decremented on transfer save, incremented on currency-buy save.

## Behavior added beyond source

- **Operations are posted when saved** (migration 0047) — there is no manual daily close any more. An exit/entry is stored as closed (`archived`) and the account balance moves in the same transaction; the old "pending buys block the close" rule is therefore moot.
- **Atomic balance mutations** — every insert + balance update happens in one Postgres transaction (`record_*` RPCs).
- **Per-user RLS isolation** — each user only sees their own rows.
- **Offline read cache** — recent list responses are cached in `SharedPreferences` and served when the live call fails.
- **Exits are limited to the account balance** (migrations 0046/0047) — a trigger on `transfers` refuses an exit above `exchanges.balance` (`insufficient_balance`), for the admin, employees and direct API inserts alike, and locks the account row so two exits cannot both pass. Restoring a backup skips the check.
- **Employee permissions, notifications, per-type visibility** (migrations 0039–0045) — see the migration headers.
- **Trial requests, WhatsApp verification and the server-time SubscriptionGuard** (migration 0059) — replaces invitations and e-mail sign-up. A new subscriber asks for a trial (name, business, E.164 phone, consent); the administrator approves 3 days / 1 week, asks for information or rejects; a 6-digit WhatsApp code (5 min, single use, keyed hash, resend after 60 s, 5 attempts per code, 5 sends per phone per hour) proves the phone and **starts the trial the first time it is entered**, in one database transaction. All times come from the database (never the phone); the server clock never goes backwards and a regression stops activation and operations until an administrator decides. After expiry the data stays readable but nothing can be written (enforced by RLS). No SMS anywhere. See docs/trial-onboarding.md.
- **Cancelling an operation entered by mistake** (migration 0048) — never a delete: `admin_cancel_operation` posts a reversing entry (the balance goes back) and stamps `cancelled_at` on the row, which keeps all its values. Admin only, after re-typing the account password (5 wrong tries lock it for 15 minutes), with a reason, and only on the operation's calendar day in Libya (Africa/Tripoli). Employees send a request (`employee_request_cancellation`) that the admin approves or rejects. Every cancellation is kept in the append-only `operation_cancellations` (كشف الإلغاءات). Statements show the cancelled operation and its reversing entry in purple; single-type lists mark it "ملغاة" and leave it out of totals. Direct insert/update/delete on `transfers` / `currency_buys` from the API is closed.

## Phases

See `docs/phase-plan.md` for the full 4-phase roadmap and what's deferred. All four phases (schema, scaffold, UI parity, polish) are complete; the deferred items are launcher icon, write-side offline queue, and accessibility audit.
