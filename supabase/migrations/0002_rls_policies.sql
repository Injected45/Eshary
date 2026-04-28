-- 0002_rls_policies.sql
-- Row Level Security: each authenticated user sees and mutates only their
-- own rows. Exchange ownership is derived via companies.owner_id (no direct
-- owner_id column on exchanges).

begin;

-- =========================================================================
-- profiles
-- =========================================================================

alter table profiles enable row level security;

create policy profiles_select_own on profiles
  for select using (id = auth.uid());

create policy profiles_insert_own on profiles
  for insert with check (id = auth.uid());

create policy profiles_update_own on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy profiles_delete_own on profiles
  for delete using (id = auth.uid());

-- =========================================================================
-- companies
-- =========================================================================

alter table companies enable row level security;

create policy companies_select_own on companies
  for select using (owner_id = auth.uid());

create policy companies_insert_own on companies
  for insert with check (owner_id = auth.uid());

create policy companies_update_own on companies
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy companies_delete_own on companies
  for delete using (owner_id = auth.uid());

-- =========================================================================
-- exchanges (ownership cascades via companies.owner_id)
-- =========================================================================

alter table exchanges enable row level security;

create policy exchanges_select_own on exchanges
  for select using (
    exists (
      select 1 from companies c
      where c.id = exchanges.company_id and c.owner_id = auth.uid()
    )
  );

create policy exchanges_insert_own on exchanges
  for insert with check (
    exists (
      select 1 from companies c
      where c.id = exchanges.company_id and c.owner_id = auth.uid()
    )
  );

create policy exchanges_update_own on exchanges
  for update using (
    exists (
      select 1 from companies c
      where c.id = exchanges.company_id and c.owner_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from companies c
      where c.id = exchanges.company_id and c.owner_id = auth.uid()
    )
  );

create policy exchanges_delete_own on exchanges
  for delete using (
    exists (
      select 1 from companies c
      where c.id = exchanges.company_id and c.owner_id = auth.uid()
    )
  );

-- =========================================================================
-- clients
-- =========================================================================

alter table clients enable row level security;

create policy clients_select_own on clients
  for select using (owner_id = auth.uid());

create policy clients_insert_own on clients
  for insert with check (owner_id = auth.uid());

create policy clients_update_own on clients
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy clients_delete_own on clients
  for delete using (owner_id = auth.uid());

-- =========================================================================
-- transfers
-- =========================================================================

alter table transfers enable row level security;

create policy transfers_select_own on transfers
  for select using (owner_id = auth.uid());

create policy transfers_insert_own on transfers
  for insert with check (owner_id = auth.uid());

create policy transfers_update_own on transfers
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy transfers_delete_own on transfers
  for delete using (owner_id = auth.uid());

-- =========================================================================
-- currency_buys
-- =========================================================================

alter table currency_buys enable row level security;

create policy currency_buys_select_own on currency_buys
  for select using (owner_id = auth.uid());

create policy currency_buys_insert_own on currency_buys
  for insert with check (owner_id = auth.uid());

create policy currency_buys_update_own on currency_buys
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy currency_buys_delete_own on currency_buys
  for delete using (owner_id = auth.uid());

commit;
