-- 0041_employee_permissions.sql
-- Per-employee permissions, replacing the old three-way role (entry / exit /
-- both). A NEW employee has NO permissions and sees an empty app until the admin
-- grants some from the employee's card (button "صلاحيات"). Grants and revokes
-- take effect at once and are enforced HERE, in the database, not only in the UI.
--
-- Permissions (sub_users.permissions text[]):
--   transfers_create   تنفيذ خروج حوالة
--   buys_create        تنفيذ دخول حوالة
--   view_own           عرض عملياتي
--   view_all_daily     عرض عمليات اليوم لكل الموظفين
--   archive_transfers  الإقفال اليومي للخروج
--   archive_buys       الإقفال اليومي للدخول
--
-- Enforcement:
--   * record_transfer / record_currency_buy / record_pending_buy check the key.
--   * archive_daily_transfers / archive_daily_buys check the key (now
--     security-definer, with an explicit owner check).
--   * Row-level security: an employee reads the lookup tables (companies,
--     accounts, parties, ...) only with a creation permission, and reads
--     transfers / currency_buys only as view_all_daily (today's rows) or
--     view_own (rows they created). Admins are unaffected.
--   * current_employee_session() also reports the permissions and ends the
--     session when the owning company's licence is no longer valid.
--
-- Also fixed here (found while auditing the whole sign-in surface):
--   * the temporary login code and its regeneration used random(), which is
--     not cryptographically secure -> now gen_random_bytes();
--   * phone + code login had NO attempt limit (a 6-digit code could be
--     brute-forced) -> 5 failures per phone in 15 minutes locks it.
--
-- admin_set_employee_permissions(sub_user_id, permissions[]) is the only way to
-- change them, and only the owning admin may call it.

begin;

alter table sub_users
  add column if not exists permissions text[] not null default '{}';

alter table employee_activity_logs
  drop constraint if exists employee_activity_logs_event_type_check;
alter table employee_activity_logs
  add constraint employee_activity_logs_event_type_check check (
    event_type in (
      'login', 'logout', 'transfer_created', 'currency_buy_created',
      'pending_buy_created', 'device_reset', 'qr_issued', 'permissions_changed'
    )
  );

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------
create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own',
               'view_all_daily', 'archive_transfers', 'archive_buys']
$$;

-- true for anyone who is not an employee (they act as their own admin), and for
-- an employee only when the key is in their list.
create or replace function employee_has_perm(p_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_emp uuid := current_employee_id();
  v_ok  boolean;
begin
  if v_emp is null then
    return true;
  end if;
  select (p_key = any (su.permissions)) into v_ok
    from sub_users su
   where su.id = v_emp;
  return coalesce(v_ok, false);
end;
$$;

create or replace function employee_has_any_perm(p_keys text[])
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_emp uuid := current_employee_id();
  v_ok  boolean;
begin
  if v_emp is null then
    return true;
  end if;
  select (su.permissions && p_keys) into v_ok
    from sub_users su
   where su.id = v_emp;
  return coalesce(v_ok, false);
end;
$$;

revoke all on function employee_has_perm(text), employee_has_any_perm(text[])
  from public, anon;
grant execute on function employee_has_perm(text), employee_has_any_perm(text[])
  to authenticated;

-- Cryptographically secure 6-digit code (zero-padded).
create or replace function _new_otp6()
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  v_bytes bytea := gen_random_bytes(4);
begin
  return lpad(((
      (get_byte(v_bytes, 0)::bigint * 16777216)
    + (get_byte(v_bytes, 1) * 65536)
    + (get_byte(v_bytes, 2) * 256)
    +  get_byte(v_bytes, 3)
  ) % 1000000)::text, 6, '0');
end;
$$;
revoke all on function _new_otp6() from public, anon;
grant execute on function _new_otp6() to authenticated;

-- -------------------------------------------------------------------------
-- Admin: set an employee's permissions
-- -------------------------------------------------------------------------
create or replace function admin_set_employee_permissions(
  p_sub_user_id uuid,
  p_permissions text[]
) returns text[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_perms text[];
begin
  select coalesce(array_agg(distinct k order by k), '{}')
    into v_perms
    from unnest(coalesce(p_permissions, '{}')) as k;

  if exists (select 1 from unnest(v_perms) k where k <> all (_employee_permission_keys())) then
    raise exception 'invalid_permission' using errcode = 'P0001';
  end if;

  update sub_users s
     set permissions = v_perms,
         updated_at  = now()
   where s.id = p_sub_user_id
     and s.parent_admin_id = auth.uid();
  if not found then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  insert into employee_activity_logs (parent_admin_id, sub_user_id, event_type)
  values (auth.uid(), p_sub_user_id, 'permissions_changed');

  return v_perms;
end;
$$;
revoke all on function admin_set_employee_permissions(uuid, text[]) from public, anon;
grant execute on function admin_set_employee_permissions(uuid, text[]) to authenticated;

-- -------------------------------------------------------------------------
-- current_employee_session: permissions instead of role; ends with the licence
-- -------------------------------------------------------------------------
drop function if exists current_employee_session();

create or replace function current_employee_session()
returns table (
  session_id      uuid,
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  branch_id       uuid,
  permissions     text[]
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return query
  select es.id, su.id, su.parent_admin_id, su.employee_name, su.branch_id, su.permissions
    from employee_sessions es
    join sub_users su on su.id = es.sub_user_id
   where es.anonymous_user_id = auth.uid()
     and es.is_active = true
     and su.status = 'active'
     and _admin_license_valid(su.parent_admin_id)
   limit 1;
end;
$$;
grant execute on function current_employee_session() to authenticated;

-- -------------------------------------------------------------------------
-- Row-level security for employees (restrictive: only ever removes access)
-- -------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'companies', 'exchanges', 'clients', 'beneficiaries',
    'exchange_companies', 'countries', 'branches'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format('drop policy if exists emp_perm_gate on public.%I', t);
      execute format(
        'create policy emp_perm_gate on public.%I as restrictive for select to authenticated '
        'using ((select current_employee_id()) is null '
        'or (select employee_has_any_perm(array[''transfers_create'',''buys_create''])))',
        t);
    end if;
  end loop;
end;
$$;

drop policy if exists emp_perm_gate on transfers;
create policy emp_perm_gate on transfers
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or ((select employee_has_perm('view_all_daily')) and status = 'daily')
    or ((select employee_has_perm('view_own'))
        and created_by_employee_id = (select current_employee_id()))
  );

drop policy if exists emp_perm_gate on currency_buys;
create policy emp_perm_gate on currency_buys
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or ((select employee_has_perm('view_all_daily')) and status in ('daily', 'pending'))
    or ((select employee_has_perm('view_own'))
        and created_by_employee_id = (select current_employee_id()))
  );

-- -------------------------------------------------------------------------
-- record_* : permission instead of role
-- -------------------------------------------------------------------------
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
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_inserted    transfers;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_employee_id is not null and not employee_has_perm('transfers_create') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from companies where id = p_company_id and owner_id = v_admin_id
  ) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from exchanges where id = p_exchange_id and company_id = p_company_id
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

  perform log_employee_activity('transfer_created', v_inserted.id, p_amount);
  return v_inserted;
end;
$$;

create or replace function record_currency_buy(
  p_my_company_id uuid, p_exchange_id uuid, p_client_id uuid,
  p_client_from_account text, p_usd_amount numeric, p_rate numeric,
  p_lyd_amount numeric, p_reference text default ''
)
returns currency_buys
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_inserted    currency_buys;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_employee_id is not null and not employee_has_perm('buys_create') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from companies where id = p_my_company_id and owner_id = v_admin_id
  ) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from exchanges where id = p_exchange_id and company_id = p_my_company_id
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

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

create or replace function record_pending_buy(
  p_my_company_id uuid, p_exchange_id uuid, p_client_id uuid,
  p_client_from_account text, p_usd_amount numeric, p_rate numeric,
  p_lyd_amount numeric, p_reference text default ''
)
returns currency_buys
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_inserted    currency_buys;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_employee_id is not null and not employee_has_perm('buys_create') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from companies where id = p_my_company_id and owner_id = v_admin_id
  ) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from exchanges where id = p_exchange_id and company_id = p_my_company_id
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

  perform log_employee_activity('pending_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

-- -------------------------------------------------------------------------
-- Daily close: admin, or an employee holding the specific permission.
-- Security-definer with an explicit owner check (an employee cannot update
-- these tables directly).
-- -------------------------------------------------------------------------
create or replace function archive_daily_transfers(p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_count integer;
begin
  if v_admin is null or p_owner is distinct from v_admin then
    raise exception 'not_authorized';
  end if;
  if current_employee_id() is not null and not employee_has_perm('archive_transfers') then
    raise exception 'permission_denied' using errcode = 'P0001';
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
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_pending_count integer;
  v_count integer;
begin
  if v_admin is null or p_owner is distinct from v_admin then
    raise exception 'not_authorized';
  end if;
  if current_employee_id() is not null and not employee_has_perm('archive_buys') then
    raise exception 'permission_denied' using errcode = 'P0001';
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

-- -------------------------------------------------------------------------
-- Secure temporary login code (create / regenerate)
-- -------------------------------------------------------------------------
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
  v_code := _new_otp6();

  -- permissions start EMPTY: the new employee sees an empty app until the
  -- admin grants some. (role is kept only for backwards compatibility.)
  insert into sub_users (
    parent_admin_id, employee_name, phone_number, login_code_hash,
    role, branch_id, permissions
  ) values (
    auth.uid(),
    trim(p_employee_name),
    trim(p_phone_number),
    crypt(v_code, gen_salt('bf')),
    p_role,
    nullif(trim(coalesce(p_branch_id, '')), '')::uuid,
    '{}'
  )
  returning sub_users.id into v_id;

  return query select v_id, v_code;
end;
$$;

create or replace function regenerate_sub_user_code(p_id uuid)
returns text language plpgsql security invoker as $$
declare
  v_code text;
  v_rows int;
begin
  v_code := _new_otp6();

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

-- -------------------------------------------------------------------------
-- Phone + code login: lock a phone after 5 failures in 15 minutes
-- -------------------------------------------------------------------------
create table if not exists employee_login_failures (
  id    bigserial primary key,
  phone text not null,
  at    timestamptz not null default now()
);
create index if not exists employee_login_failures_idx
  on employee_login_failures (phone, at desc);
alter table employee_login_failures enable row level security;
revoke all on employee_login_failures from anon, authenticated;

create or replace function employee_login(
  p_phone     text,
  p_code      text,
  p_device_id text
) returns table (
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  session_id      uuid
) language plpgsql security definer set search_path = public, extensions as $$
declare
  v_sub_user   sub_users;
  v_session_id uuid;
  v_phone      text := trim(coalesce(p_phone, ''));
  v_fails      integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'device_id_required' using errcode = 'P0001';
  end if;

  select count(*) into v_fails
    from employee_login_failures f
   where f.phone = v_phone and f.at > now() - interval '15 minutes';
  if v_fails >= 5 then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;

  for v_sub_user in
    select * from sub_users
    where phone_number = v_phone
      and status = 'active'
  loop
    if v_sub_user.login_code_hash = crypt(p_code, v_sub_user.login_code_hash) then
      if v_sub_user.device_id is null then
        update sub_users set
          device_id = p_device_id,
          login_code_used = true,
          login_code_used_at = now(),
          last_login_at = now(),
          updated_at = now()
        where id = v_sub_user.id;
      elsif v_sub_user.device_id = p_device_id then
        update sub_users set
          last_login_at = now(),
          updated_at = now()
        where id = v_sub_user.id;
      else
        raise exception 'device_mismatch' using errcode = 'P0001';
      end if;

      update employee_sessions es set
        is_active = false,
        ended_at = now()
      where es.sub_user_id = v_sub_user.id and es.is_active;

      insert into employee_sessions (
        sub_user_id, anonymous_user_id, device_id
      ) values (
        v_sub_user.id, auth.uid(), p_device_id
      ) returning id into v_session_id;

      insert into employee_activity_logs (
        parent_admin_id, sub_user_id, session_id, event_type, device_id
      ) values (
        v_sub_user.parent_admin_id, v_sub_user.id, v_session_id, 'login', p_device_id
      );

      delete from employee_login_failures f where f.phone = v_phone;

      return query select
        v_sub_user.id,
        v_sub_user.parent_admin_id,
        v_sub_user.employee_name,
        v_session_id;
      return;
    end if;
  end loop;

  -- Wrong phone or code: count it (a raise would roll the count back) and
  -- return no rows; the app reports "invalid credentials".
  insert into employee_login_failures (phone) values (v_phone);
  delete from employee_login_failures f where f.at < now() - interval '1 day';
  return;
end;
$$;

commit;
