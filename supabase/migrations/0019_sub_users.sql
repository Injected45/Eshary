-- 0019_sub_users.sql
-- Phase 1 of the Employee Management module. Introduces a flat sub_users
-- table tying operational employees to their parent admin (the existing
-- auth user). This migration only supports admin-side CRUD via the UI:
-- listing, adding, regenerating the login code, and enabling/disabling.
--
-- Phase 2 will add the actual employee login flow + device binding using
-- the login_code_hash + device_id columns already present here. Until
-- Phase 2 ships, login_code_used stays false and device_id stays null.

begin;

create extension if not exists pgcrypto;

create type sub_user_role as enum ('entry', 'exit', 'both');
create type sub_user_status as enum ('active', 'disabled');

create table sub_users (
  id                 uuid primary key default gen_random_uuid(),
  parent_admin_id    uuid not null references auth.users(id) on delete cascade,
  employee_name      text not null,
  phone_number       text not null,
  login_code_hash    text not null,
  login_code_used    boolean not null default false,
  login_code_used_at timestamptz,
  device_id          text,
  role               sub_user_role not null default 'both',
  branch_id          text,
  status             sub_user_status not null default 'active',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  last_login_at      timestamptz,
  disabled_at        timestamptz,
  -- Libyan mobile format: exactly 10 digits starting with 09.
  constraint sub_users_phone_format check (phone_number ~ '^09[0-9]{8}$'),
  -- Each admin owns a disjoint phone space; different admins may share
  -- the same employee phone (unlikely in practice but harmless here).
  constraint sub_users_phone_unique unique (parent_admin_id, phone_number)
);

create index sub_users_parent_admin_idx on sub_users(parent_admin_id);

alter table sub_users enable row level security;

-- Admins manage only their own staff. Same shape as the other per-row
-- ownership policies in this project (companies, clients, ...).
create policy sub_users_select_own on sub_users
  for select to authenticated
  using (parent_admin_id = auth.uid());

create policy sub_users_insert_own on sub_users
  for insert to authenticated
  with check (parent_admin_id = auth.uid());

create policy sub_users_update_own on sub_users
  for update to authenticated
  using (parent_admin_id = auth.uid())
  with check (parent_admin_id = auth.uid());

create policy sub_users_delete_own on sub_users
  for delete to authenticated
  using (parent_admin_id = auth.uid());

create or replace function sub_users_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger sub_users_set_updated_at_trg
  before update on sub_users
  for each row execute function sub_users_set_updated_at();

-- create_sub_user(name, phone, role, branch) → (id, plain_code).
-- Generates a 6-digit login code, stores its bcrypt hash, and returns the
-- plain code ONCE so the UI can display it to the admin. The plain code
-- is never persisted. Phase 2 verifies via `crypt(input, login_code_hash)`.
create or replace function create_sub_user(
  p_employee_name text,
  p_phone_number  text,
  p_role          sub_user_role default 'both',
  p_branch_id     text default null
) returns table (
  id         uuid,
  plain_code text
) language plpgsql security invoker as $$
declare
  v_code text;
  v_id   uuid;
begin
  -- 6-digit zero-padded; random() is sufficient for a one-time bootstrap
  -- code that the admin hands over out-of-band. Phase 2 will rate-limit
  -- login attempts to defend against brute force.
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  insert into sub_users (
    parent_admin_id,
    employee_name,
    phone_number,
    login_code_hash,
    role,
    branch_id
  ) values (
    auth.uid(),
    trim(p_employee_name),
    trim(p_phone_number),
    crypt(v_code, gen_salt('bf')),
    p_role,
    nullif(trim(coalesce(p_branch_id, '')), '')
  )
  returning sub_users.id into v_id;

  return query select v_id, v_code;
end;
$$;

-- regenerate_sub_user_code(id) → new plain code. Used when the admin
-- lost the original code or wants to rebind a lost device. Resets
-- login_code_used + device_id so the employee can authenticate fresh.
create or replace function regenerate_sub_user_code(p_id uuid)
returns text language plpgsql security invoker as $$
declare
  v_code text;
  v_rows int;
begin
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  update sub_users set
    login_code_hash    = crypt(v_code, gen_salt('bf')),
    login_code_used    = false,
    login_code_used_at = null,
    device_id          = null,
    updated_at         = now()
  where id = p_id
    and parent_admin_id = auth.uid();

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  return v_code;
end;
$$;

commit;
