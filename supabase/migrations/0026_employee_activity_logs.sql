-- 0026_employee_activity_logs.sql
-- Phase 4 of the Employee Management module — activity audit trail.
-- Every employee action (login, logout, create transfer / currency_buy /
-- pending buy) inserts a row here so the admin has a clear chronological
-- record of who did what, when, on which device.
--
-- Logging is automatic: the existing record_* RPCs are updated to call
-- a single internal helper `log_employee_activity()` on success, and
-- employee_login / employee_logout do the same for session events.
--
-- Admin-side reads are scoped by parent_admin_id; employee-side reads
-- (anonymous JWT) are scoped to their own sub_user_id via
-- current_employee_id().

begin;

create table employee_activity_logs (
  id              uuid primary key default gen_random_uuid(),
  parent_admin_id uuid not null references auth.users(id) on delete cascade,
  sub_user_id     uuid not null references sub_users(id) on delete cascade,
  session_id      uuid references employee_sessions(id) on delete set null,
  event_type      text not null,
  operation_id    uuid,
  amount          numeric(14, 2),
  device_id       text,
  created_at      timestamptz not null default now(),
  -- Whitelist of event_type values so a typo from a future RPC is caught
  -- at insertion time rather than corrupting reports.
  constraint employee_activity_logs_event_type_check check (
    event_type in (
      'login',
      'logout',
      'transfer_created',
      'currency_buy_created',
      'pending_buy_created'
    )
  )
);

create index employee_activity_logs_admin_recent_idx
  on employee_activity_logs(parent_admin_id, created_at desc);

create index employee_activity_logs_sub_user_recent_idx
  on employee_activity_logs(sub_user_id, created_at desc);

alter table employee_activity_logs enable row level security;

create policy employee_activity_logs_select_admin on employee_activity_logs
  for select to authenticated
  using (parent_admin_id = auth.uid());

create policy employee_activity_logs_select_self on employee_activity_logs
  for select to authenticated
  using (sub_user_id = current_employee_id());

-- =============================================================================
-- log_employee_activity()
-- Internal helper invoked by record_*/employee_login/employee_logout. No-ops
-- when the caller is not an employee, so it's safe to call unconditionally.
-- =============================================================================
create or replace function log_employee_activity(
  p_event_type   text,
  p_operation_id uuid    default null,
  p_amount       numeric default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_employee_id uuid := current_employee_id();
  v_admin_id    uuid;
  v_session_id  uuid;
  v_device_id   text;
begin
  if v_employee_id is null then
    return;
  end if;

  select su.parent_admin_id
    into v_admin_id
    from sub_users su
   where su.id = v_employee_id;

  select es.id, es.device_id
    into v_session_id, v_device_id
    from employee_sessions es
   where es.anonymous_user_id = auth.uid()
     and es.is_active = true
   limit 1;

  insert into employee_activity_logs (
    parent_admin_id, sub_user_id, session_id, event_type,
    operation_id, amount, device_id
  ) values (
    v_admin_id, v_employee_id, v_session_id, p_event_type,
    p_operation_id, p_amount, v_device_id
  );
end;
$$;

revoke all on function log_employee_activity(text, uuid, numeric) from public;
-- Not granted to authenticated: callers should not invoke this directly,
-- only through the record_* RPCs.

-- =============================================================================
-- Patch the record_* RPCs to emit activity logs after successful insert.
-- Only the tail of each function changes; the guard and insert blocks
-- are identical to 0025_employee_writes.sql.
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
language plpgsql security definer set search_path = public, extensions
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
  if v_employee_id is not null then
    select su.role into v_role from sub_users su where su.id = v_employee_id;
    if v_role not in ('exit', 'both') then
      raise exception 'role_forbidden_for_exit' using errcode = 'P0001';
    end if;
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

-- =============================================================================
-- employee_login → log 'login' after the session row is created.
-- employee_logout → log 'logout' before deactivating the session.
-- =============================================================================
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
  v_sub_user sub_users;
  v_session_id uuid;
  v_matched boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'device_id_required' using errcode = 'P0001';
  end if;

  for v_sub_user in
    select * from sub_users
    where phone_number = trim(p_phone)
      and status = 'active'
  loop
    if v_sub_user.login_code_hash = crypt(p_code, v_sub_user.login_code_hash) then
      v_matched := true;
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

      -- Activity log: 'login'. Done directly here (rather than via
      -- log_employee_activity) because current_employee_id() may not yet
      -- see the session row depending on transaction visibility, and we
      -- already have the values we need locally.
      insert into employee_activity_logs (
        parent_admin_id, sub_user_id, session_id, event_type, device_id
      ) values (
        v_sub_user.parent_admin_id, v_sub_user.id, v_session_id, 'login', p_device_id
      );

      return query select
        v_sub_user.id,
        v_sub_user.parent_admin_id,
        v_sub_user.employee_name,
        v_session_id;
      return;
    end if;
  end loop;

  if not v_matched then
    raise exception 'invalid_credentials' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function employee_logout()
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_session_id uuid;
  v_sub_user_id uuid;
  v_admin_id uuid;
  v_device_id text;
begin
  -- Capture the session being closed so the log row reflects its id.
  select es.id, es.sub_user_id, su.parent_admin_id, es.device_id
    into v_session_id, v_sub_user_id, v_admin_id, v_device_id
    from employee_sessions es
    join sub_users su on su.id = es.sub_user_id
   where es.anonymous_user_id = auth.uid()
     and es.is_active = true
   limit 1;

  if v_session_id is not null then
    insert into employee_activity_logs (
      parent_admin_id, sub_user_id, session_id, event_type, device_id
    ) values (
      v_admin_id, v_sub_user_id, v_session_id, 'logout', v_device_id
    );
  end if;

  update employee_sessions set
    is_active = false,
    ended_at = now()
  where anonymous_user_id = auth.uid() and is_active;
end;
$$;

grant execute on function employee_logout() to authenticated;

commit;
