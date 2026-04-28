-- 0007_beneficiaries.sql
-- Saved beneficiaries — quick-fill source for the transfers form. One row
-- per (owner, beneficiary) entry. Free text only — NOT linked to any other
-- table by FK on the beneficiary side.

begin;

create table beneficiaries (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  name        text not null,
  account     text,
  code        text,
  created_at  timestamptz not null default now()
);

create index beneficiaries_owner_id_idx on beneficiaries (owner_id);

alter table beneficiaries enable row level security;

create policy beneficiaries_select_own on beneficiaries
  for select using (owner_id = auth.uid());

create policy beneficiaries_insert_own on beneficiaries
  for insert with check (owner_id = auth.uid());

create policy beneficiaries_update_own on beneficiaries
  for update using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy beneficiaries_delete_own on beneficiaries
  for delete using (owner_id = auth.uid());

commit;
