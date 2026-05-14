-- 0020_branches.sql
-- Branches CRUD module. Introduces a per-admin `branches` table and
-- converts the previously free-text sub_users.branch_id column into a
-- proper UUID foreign key with ON DELETE SET NULL semantics.
--
-- Pre-feature `sub_users.branch_id` values were free-typed strings; they
-- cannot be reliably mapped to UUIDs and the data is test-only, so the
-- migration clears them before changing the column type.

begin;

create table branches (
  id              uuid primary key default gen_random_uuid(),
  parent_admin_id uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint branches_name_unique unique (parent_admin_id, name)
);

create index branches_parent_admin_idx on branches(parent_admin_id);

alter table branches enable row level security;

create policy branches_select_own on branches
  for select to authenticated
  using (parent_admin_id = auth.uid());

create policy branches_insert_own on branches
  for insert to authenticated
  with check (parent_admin_id = auth.uid());

create policy branches_update_own on branches
  for update to authenticated
  using (parent_admin_id = auth.uid())
  with check (parent_admin_id = auth.uid());

create policy branches_delete_own on branches
  for delete to authenticated
  using (parent_admin_id = auth.uid());

create or replace function branches_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger branches_set_updated_at_trg
  before update on branches
  for each row execute function branches_set_updated_at();

-- Clear pre-feature free-typed branch names; they cannot be cast to uuid
-- and the data so far is test-only.
update sub_users set branch_id = null;

alter table sub_users
  alter column branch_id type uuid using branch_id::uuid;

alter table sub_users
  add constraint sub_users_branch_id_fkey
  foreign key (branch_id) references branches(id) on delete set null;

commit;
