-- 0025_employee_writes.sql
-- Phase 3b of the Employee Management module: allow employees to actually
-- write transfers / currency_buys, with parent-admin attribution and role
-- enforcement.
--
-- Changes:
--   1. Add `created_by_employee_id` to transfers + currency_buys.
--   2. Add helper `current_employee_id()` (companion to effective_admin_id).
--   3. Switch record_transfer / record_currency_buy / record_pending_buy
--      to security definer and:
--        - owner_id is now effective_admin_id() (parent admin for an
--          employee, or auth.uid() for an admin).
--        - created_by_employee_id is stamped if the caller is an employee.
--        - Roles enforced: transfers require 'exit' or 'both';
--          currency_buys require 'entry' or 'both'.
--   4. next_reference accepts employee callers via effective_admin_id().
--   5. archive_daily_* are left admin-only by adding a guard.

begin;

-- =============================================================================
-- 1) Attribution columns. Nullable: admin-authored rows stay null.
-- =============================================================================
alter table transfers
  add column if not exists created_by_employee_id uuid
    references sub_users(id) on delete set null;

alter table currency_buys
  add column if not exists created_by_employee_id uuid
    references sub_users(id) on delete set null;

create index if not exists transfers_created_by_employee_idx
  on transfers(created_by_employee_id)
  where created_by_employee_id is not null;

create index if not exists currency_buys_created_by_employee_idx
  on currency_buys(created_by_employee_id)
  where created_by_employee_id is not null;

-- =============================================================================
-- 2) current_employee_id() — null for admins, sub_user.id for employees.
-- =============================================================================
create or replace function current_employee_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare v_id uuid;
begin
  if auth.uid() is null then return null; end if;
  select es.sub_user_id into v_id
    from employee_sessions es
    join sub_users su on su.id = es.sub_user_id
   where es.anonymous_user_id = auth.uid()
     and es.is_active = true
     and su.status = 'active'
   limit 1;
  return v_id;
end;
$$;

grant execute on function current_employee_id() to authenticated;

-- =============================================================================
-- 3) record_transfer — exits (خروج). Requires role in ('exit', 'both').
-- =============================================================================
create or replace function record_transfer(
  p_company_id                    uuid,
  p_exchange_id                   uuid,
  p_beneficiary_name              text,
  p_beneficiary_account_company   text,
  p_beneficiary_code              text,
  p_amount                        numeric,
  p_reference                     text
)
returns transfers
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_role        sub_user_role;
  v_inserted    transfers;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  -- Role enforcement for employee callers.
  if v_employee_id is not null then
    select su.role into v_role from sub_users su where su.id = v_employee_id;
    if v_role not in ('exit', 'both') then
      raise exception 'role_forbidden_for_exit' using errcode = 'P0001';
    end if;
  end if;

  -- Ownership verification against the admin's data (replaces the
  -- previous auth.uid() check now that owner_id is parent-admin-derived).
  if not exists (
    select 1 from companies
     where id = p_company_id and owner_id = v_admin_id
  ) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from exchanges
     where id = p_exchange_id and company_id = p_company_id
  ) then
    raise exception 'exchange_does_not_belong_to_company' using errcode = 'P0001';
  end if;

  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, created_by_employee_id
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'daily', v_employee_id
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

-- =============================================================================
-- 4) record_currency_buy — daily entry (دخول). Role in ('entry', 'both').
-- =============================================================================
create or replace function record_currency_buy(
  p_my_company_id        uuid,
  p_exchange_id          uuid,
  p_client_id            uuid,
  p_client_from_account  text,
  p_usd_amount           numeric,
  p_rate                 numeric,
  p_lyd_amount           numeric,
  p_reference            text default ''
)
returns currency_buys
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_role        sub_user_role;
  v_inserted    currency_buys;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  if v_employee_id is not null then
    select su.role into v_role from sub_users su where su.id = v_employee_id;
    if v_role not in ('entry', 'both') then
      raise exception 'role_forbidden_for_entry' using errcode = 'P0001';
    end if;
  end if;

  if not exists (
    select 1 from companies
     where id = p_my_company_id and owner_id = v_admin_id
  ) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from exchanges
     where id = p_exchange_id and company_id = p_my_company_id
  ) then
    raise exception 'exchange_does_not_belong_to_company' using errcode = 'P0001';
  end if;

  insert into currency_buys (
    owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, reference, created_by_employee_id
  ) values (
    v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, p_rate, p_lyd_amount, 'daily', p_reference, v_employee_id
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

-- =============================================================================
-- 5) record_pending_buy — قيد التنفيذ. Same role rules as record_currency_buy.
-- =============================================================================
create or replace function record_pending_buy(
  p_my_company_id        uuid,
  p_exchange_id          uuid,
  p_client_id            uuid,
  p_client_from_account  text,
  p_usd_amount           numeric,
  p_rate                 numeric,
  p_lyd_amount           numeric,
  p_reference            text default ''
)
returns currency_buys
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_role        sub_user_role;
  v_inserted    currency_buys;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  if v_employee_id is not null then
    select su.role into v_role from sub_users su where su.id = v_employee_id;
    if v_role not in ('entry', 'both') then
      raise exception 'role_forbidden_for_entry' using errcode = 'P0001';
    end if;
  end if;

  if not exists (
    select 1 from companies
     where id = p_my_company_id and owner_id = v_admin_id
  ) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from exchanges
     where id = p_exchange_id and company_id = p_my_company_id
  ) then
    raise exception 'exchange_does_not_belong_to_company' using errcode = 'P0001';
  end if;

  insert into currency_buys (
    owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, reference, created_by_employee_id
  ) values (
    v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, p_rate, p_lyd_amount, 'pending', p_reference, v_employee_id
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

-- =============================================================================
-- 6) next_reference — employees calling for transfer reference must resolve
--    to their parent admin's counter.
-- =============================================================================
create or replace function next_reference(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_owner       uuid;
  v_start_ref   text;
  v_count       integer;
  v_match       text[];
  v_prefix      text;
  v_seed_text   text;
  v_seed_num    integer;
  v_pad_width   integer;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select owner_id, start_ref
    into v_owner, v_start_ref
    from companies
   where id = p_company_id;

  if v_owner is null then
    raise exception 'company % not found', p_company_id;
  end if;
  if v_owner <> v_admin_id then
    raise exception 'not_authorized: company does not belong to caller';
  end if;

  -- Counts every transfer the admin owns across all their companies,
  -- matching project_web.html:711 bug-for-bug.
  select count(*) into v_count from transfers where owner_id = v_owner;

  v_match := regexp_match(coalesce(v_start_ref, ''), '^([^0-9]*)([0-9]+)$');
  if v_match is not null then
    v_prefix    := v_match[1];
    v_seed_text := v_match[2];
    v_seed_num  := v_seed_text::integer;
    v_pad_width := length(v_seed_text);
    return v_prefix
           || lpad((v_seed_num + v_count)::text, v_pad_width, '0');
  else
    return coalesce(v_start_ref, '')
           || lpad((v_count + 1)::text, 3, '0');
  end if;
end;
$$;

-- =============================================================================
-- 7) archive_daily_transfers / archive_daily_buys — keep admin-only.
--    Employees attempting to archive get a clear error.
-- =============================================================================
create or replace function archive_daily_transfers(p_owner uuid)
returns integer
language plpgsql
security invoker
as $$
declare
  v_count integer;
begin
  if current_employee_id() is not null then
    raise exception 'archive_admin_only' using errcode = 'P0001';
  end if;
  if auth.uid() is null or auth.uid() <> p_owner then
    raise exception 'not_authorized';
  end if;

  with t_sums as (
    select exchange_id, sum(amount) as s
      from transfers
     where status = 'daily' and owner_id = p_owner
     group by exchange_id
  )
  update exchanges e
     set balance = e.balance - t_sums.s
    from t_sums
   where e.id = t_sums.exchange_id;

  update transfers
     set status = 'archived', archived_at = now()
   where status = 'daily' and owner_id = p_owner;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function archive_daily_buys(p_owner uuid)
returns integer
language plpgsql
security invoker
as $$
declare
  v_pending_count integer;
  v_count integer;
begin
  if current_employee_id() is not null then
    raise exception 'archive_admin_only' using errcode = 'P0001';
  end if;
  if auth.uid() is null or auth.uid() <> p_owner then
    raise exception 'not_authorized';
  end if;

  select count(*) into v_pending_count
    from currency_buys
   where status = 'pending' and owner_id = p_owner;
  if v_pending_count > 0 then
    raise exception 'pending currency buy rows exist for owner: %',
      v_pending_count;
  end if;

  with b_sums as (
    select exchange_id, sum(usd_amount) as s
      from currency_buys
     where status = 'daily' and owner_id = p_owner
     group by exchange_id
  )
  update exchanges e
     set balance = e.balance + b_sums.s
    from b_sums
   where e.id = b_sums.exchange_id;

  update currency_buys
     set status = 'archived', archived_at = now()
   where status = 'daily' and owner_id = p_owner;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

commit;
