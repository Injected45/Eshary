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

- **Pending buys block archive** — `archive_daily_buys` raises if any `currency_buys.status = 'pending'` rows still exist for the caller. The source UI showed pending rows but never blocked archival.
- **Atomic balance mutations** — every insert + balance update happens in one Postgres transaction (`record_*` RPCs).
- **Per-user RLS isolation** — each user only sees their own rows.
- **Offline read cache** — recent list responses are cached in `SharedPreferences` and served when the live call fails.

## Phases

See `docs/phase-plan.md` for the full 4-phase roadmap and what's deferred. All four phases (schema, scaffold, UI parity, polish) are complete; the deferred items are launcher icon, write-side offline queue, and accessibility audit.
