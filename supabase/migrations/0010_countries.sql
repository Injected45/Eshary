-- 0010_countries.sql
-- Per-user list of country names used by the AddCompanyDialog country picker.

begin;

create table countries (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create index countries_owner_id_idx on countries (owner_id);

alter table countries enable row level security;

create policy countries_select_own on countries
  for select using (owner_id = auth.uid());

create policy countries_insert_own on countries
  for insert with check (owner_id = auth.uid());

create policy countries_update_own on countries
  for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy countries_delete_own on countries
  for delete using (owner_id = auth.uid());

commit;
