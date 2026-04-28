-- 0009_exchange_companies.sql
-- Per-user list of exchange-office company names (e.g., "بهاروز قار").
-- Reusable across the user's accounts and beneficiaries.

begin;

create table exchange_companies (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create index exchange_companies_owner_id_idx on exchange_companies (owner_id);

alter table exchange_companies enable row level security;

create policy ec_select_own on exchange_companies
  for select using (owner_id = auth.uid());

create policy ec_insert_own on exchange_companies
  for insert with check (owner_id = auth.uid());

create policy ec_update_own on exchange_companies
  for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy ec_delete_own on exchange_companies
  for delete using (owner_id = auth.uid());

commit;
