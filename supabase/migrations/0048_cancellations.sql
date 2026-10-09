-- 0048_cancellations.sql
-- Cancelling an exit (خروج) or an entry (دخول) entered by mistake.
--
-- A cancellation never deletes or edits the operation. It posts a reversing
-- entry (قيد عكسي) in the same transaction:
--
--   cancel an exit    balance = balance + amount
--   cancel an entry   balance = balance - usd_amount   (refused if it would go
--                                                       below zero)
--
-- The operation keeps every value it had; only `cancelled_at` is stamped on it.
-- Each cancellation is written to operation_cancellations with the full
-- details (who did the operation, who asked, who cancelled, why, the balance
-- before and after). Nobody can edit or delete that record from the app or the
-- API, not even the admin.
--
-- Rules (all checked here, in the database, not only in the app)
--   * Only the admin cancels, and only after typing their account password.
--     Five wrong passwords in 15 minutes lock cancelling for 15 minutes.
--   * An employee cannot cancel; they send a request (with a reason) for one
--     of their own operations. The admin approves it (password) or rejects it.
--   * Only operations of TODAY can be cancelled, by the calendar date in Libya
--     (Africa/Tripoli): an operation at 23:59 cannot be cancelled at 00:01.
--   * A reason is required. An operation is cancelled at most once.
--
-- Also closed here: until now the admin's session could insert, update or
-- delete operations directly through the API (policies from 0002), which would
-- bypass both the balance and this record. The app never did; from now on
-- operations are written only by the database functions.

begin;

-- -------------------------------------------------------------------------
-- 1) The mark on the operation
-- -------------------------------------------------------------------------
alter table transfers     add column if not exists cancelled_at timestamptz;
alter table currency_buys add column if not exists cancelled_at timestamptz;

-- -------------------------------------------------------------------------
-- 2) Operations are written only through the database functions
-- -------------------------------------------------------------------------
drop policy if exists transfers_insert_own     on transfers;
drop policy if exists transfers_update_own     on transfers;
drop policy if exists transfers_delete_own     on transfers;
drop policy if exists currency_buys_insert_own on currency_buys;
drop policy if exists currency_buys_update_own on currency_buys;
drop policy if exists currency_buys_delete_own on currency_buys;
revoke insert, update, delete on transfers, currency_buys from anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) The calendar day an operation belongs to (Libya time)
-- -------------------------------------------------------------------------
create or replace function _ops_day(p_at timestamptz)
returns date
language sql
immutable
as $$ select (p_at at time zone 'Africa/Tripoli')::date $$;

-- -------------------------------------------------------------------------
-- 4) The record of cancellations (append-only)
-- -------------------------------------------------------------------------
create table if not exists operation_cancellations (
  id                       uuid primary key default gen_random_uuid(),
  owner_id                 uuid not null references auth.users (id) on delete cascade,
  kind                     text not null check (kind in ('transfer', 'buy')),
  operation_id             uuid not null unique,
  company_id               uuid,
  exchange_id              uuid,
  company_name             text,
  exchange_name            text,
  exchange_code            text,
  amount                   numeric(14, 2) not null,
  reference                text,
  party_name               text,
  operation_created_at     timestamptz not null,
  operation_employee_id    uuid,
  operation_employee_name  text not null,
  request_id               uuid,
  requested_by_name        text,
  reason                   text not null,
  balance_before           numeric(14, 2) not null,
  balance_after            numeric(14, 2) not null,
  cancelled_by             uuid not null,
  cancelled_by_name        text not null,
  cancelled_at             timestamptz not null default now()
);

create index if not exists operation_cancellations_owner_recent_idx
  on operation_cancellations (owner_id, cancelled_at desc);

alter table operation_cancellations enable row level security;

-- Read: the admin only. No insert / update / delete policy at all.
drop policy if exists operation_cancellations_select_admin on operation_cancellations;
create policy operation_cancellations_select_admin on operation_cancellations
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    and (select current_employee_id()) is null
  );

drop policy if exists license_gate on operation_cancellations;
create policy license_gate on operation_cancellations
  as restrictive for all to authenticated using ((select license_ok()));

revoke all on operation_cancellations from anon;
revoke insert, update, delete on operation_cancellations from authenticated;

-- -------------------------------------------------------------------------
-- 5) Requests from employees
-- -------------------------------------------------------------------------
create table if not exists cancellation_requests (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references auth.users (id) on delete cascade,
  sub_user_id    uuid references sub_users (id) on delete set null,
  employee_name  text not null,
  kind           text not null check (kind in ('transfer', 'buy')),
  operation_id   uuid not null,
  amount         numeric(14, 2) not null,
  party_name     text,
  reason         text not null,
  status         text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected')),
  created_at     timestamptz not null default now(),
  decided_at     timestamptz,
  decision_note  text
);

-- One open request per operation.
create unique index if not exists cancellation_requests_one_pending_idx
  on cancellation_requests (operation_id) where status = 'pending';
create index if not exists cancellation_requests_owner_recent_idx
  on cancellation_requests (owner_id, created_at desc);

alter table cancellation_requests enable row level security;

drop policy if exists cancellation_requests_select_admin on cancellation_requests;
create policy cancellation_requests_select_admin on cancellation_requests
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    and (select current_employee_id()) is null
  );

drop policy if exists cancellation_requests_select_employee on cancellation_requests;
create policy cancellation_requests_select_employee on cancellation_requests
  for select to authenticated
  using (
    sub_user_id = (select current_employee_id())
    and owner_id = (select effective_admin_id())
  );

drop policy if exists license_gate on cancellation_requests;
create policy license_gate on cancellation_requests
  as restrictive for all to authenticated using ((select license_ok()));

revoke all on cancellation_requests from anon;
revoke insert, update, delete on cancellation_requests from authenticated;

-- -------------------------------------------------------------------------
-- 6) Wrong passwords (for the lock); never readable from the app
-- -------------------------------------------------------------------------
create table if not exists cancel_auth_failures (
  id          bigserial primary key,
  user_id     uuid not null,
  created_at  timestamptz not null default now()
);
create index if not exists cancel_auth_failures_user_recent_idx
  on cancel_auth_failures (user_id, created_at desc);
alter table cancel_auth_failures enable row level security;
revoke all on cancel_auth_failures from anon, authenticated;

-- -------------------------------------------------------------------------
-- 7) Alerts: the admin is told about each request
-- -------------------------------------------------------------------------
alter table admin_alerts drop constraint if exists admin_alerts_kind_check;
alter table admin_alerts add constraint admin_alerts_kind_check check (
  kind in ('transfer', 'buy', 'pending_buy',
           'cancel_request_transfer', 'cancel_request_buy')
);

-- -------------------------------------------------------------------------
-- 8) Employee: ask for a cancellation of one of their own operations of today
-- -------------------------------------------------------------------------
create or replace function employee_request_cancellation(
  p_kind         text,
  p_operation_id uuid,
  p_reason       text
) returns cancellation_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_emp     uuid := current_employee_id();
  v_admin   uuid := effective_admin_id();
  v_reason  text := btrim(coalesce(p_reason, ''));
  v_name    text;
  v_at      timestamptz;
  v_by      uuid;
  v_status  text;
  v_cancel  timestamptz;
  v_amount  numeric;
  v_party   text;
  v_row     cancellation_requests;
begin
  if v_emp is null or v_admin is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception 'cancel_reason_required' using errcode = 'P0001';
  end if;

  if p_kind = 'transfer' then
    select t.created_at, t.created_by_employee_id, t.status, t.cancelled_at,
           t.amount, t.beneficiary_name
      into v_at, v_by, v_status, v_cancel, v_amount, v_party
      from transfers t
     where t.id = p_operation_id and t.owner_id = v_admin;
  elsif p_kind = 'buy' then
    select b.created_at, b.created_by_employee_id, b.status, b.cancelled_at,
           b.usd_amount, coalesce(c.name, b.client_from_account)
      into v_at, v_by, v_status, v_cancel, v_amount, v_party
      from currency_buys b
      left join clients c on c.id = b.client_id
     where b.id = p_operation_id and b.owner_id = v_admin;
  else
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;

  -- Only their own operations.
  if v_at is null or v_by is distinct from v_emp then
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;
  if v_status <> 'archived' then
    raise exception 'cancel_not_cancellable' using errcode = 'P0001';
  end if;
  if v_cancel is not null then
    raise exception 'cancel_already' using errcode = 'P0001';
  end if;
  if _ops_day(v_at) <> _ops_day(now()) then
    raise exception 'cancel_day_passed' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from cancellation_requests
     where operation_id = p_operation_id and status = 'pending'
  ) then
    raise exception 'cancel_request_exists' using errcode = 'P0001';
  end if;

  select employee_name into v_name from sub_users where id = v_emp;

  insert into cancellation_requests (
    owner_id, sub_user_id, employee_name, kind, operation_id, amount,
    party_name, reason
  ) values (
    v_admin, v_emp, coalesce(v_name, '—'), p_kind, p_operation_id, v_amount,
    v_party, v_reason
  )
  returning * into v_row;

  insert into admin_alerts (
    owner_id, sub_user_id, employee_name, kind, operation_id, amount, party_name
  ) values (
    v_admin, v_emp, coalesce(v_name, '—'),
    'cancel_request_' || p_kind, p_operation_id, v_amount, v_party
  );

  return v_row;
end;
$$;
revoke all on function employee_request_cancellation(text, uuid, text) from public, anon;
grant execute on function employee_request_cancellation(text, uuid, text) to authenticated;

-- -------------------------------------------------------------------------
-- 9) Admin: reject a request
-- -------------------------------------------------------------------------
create or replace function admin_reject_cancellation(
  p_request_id uuid,
  p_note       text default null
) returns cancellation_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_row   cancellation_requests;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;

  update cancellation_requests
     set status = 'rejected',
         decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_request_id and owner_id = v_admin and status = 'pending'
  returning * into v_row;
  if not found then
    raise exception 'cancel_request_not_found' using errcode = 'P0001';
  end if;

  if v_row.sub_user_id is not null then
    insert into employee_messages (owner_id, sub_user_id, broadcast_id, title, body)
    values (
      v_admin, v_row.sub_user_id, gen_random_uuid(), 'طلب إلغاء مرفوض',
      format('تم رفض طلب إلغاء عملية "%s" بقيمة %s$%s',
             case v_row.kind when 'transfer' then 'خروج' else 'دخول' end,
             to_char(v_row.amount, 'FM999G999G990D00'),
             coalesce(E'\nالملاحظة: ' || v_row.decision_note, ''))
    );
  end if;

  return v_row;
end;
$$;
revoke all on function admin_reject_cancellation(uuid, text) from public, anon;
grant execute on function admin_reject_cancellation(uuid, text) to authenticated;

-- -------------------------------------------------------------------------
-- 10) Admin: cancel an operation (password required)
--
-- Returns {"ok": true, "id": ..., "balance_after": ...} on success.
-- A wrong password returns {"ok": false, "error": "wrong_password",
-- "remaining": n} instead of raising, so the failed attempt is kept for the
-- lock. Every other refusal raises (nothing is changed).
-- -------------------------------------------------------------------------
create or replace function admin_cancel_operation(
  p_kind         text,
  p_operation_id uuid,
  p_reason       text,
  p_password     text,
  p_request_id   uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin      uuid := auth.uid();
  v_reason     text := btrim(coalesce(p_reason, ''));
  v_hash       text;
  v_admin_name text;
  v_fails      integer;
  v_t          transfers;
  v_b          currency_buys;
  v_company    uuid;
  v_exchange   uuid;
  v_amount     numeric;
  v_ref        text;
  v_party      text;
  v_at         timestamptz;
  v_emp        uuid;
  v_emp_name   text;
  v_before     numeric;
  v_after      numeric;
  v_req_id     uuid;
  v_req_name   text;
  v_req_emp    uuid;
  v_id         uuid;
  v_ex_name    text;
  v_ex_code    text;
  v_co_name    text;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_kind not in ('transfer', 'buy') then
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;
  if length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception 'cancel_reason_required' using errcode = 'P0001';
  end if;

  -- Lock after 5 wrong passwords in 15 minutes.
  select count(*) into v_fails
    from cancel_auth_failures
   where user_id = v_admin and created_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;

  select u.encrypted_password,
         coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_hash, v_admin_name
    from auth.users u
   where u.id = v_admin;

  if v_hash is null or v_hash = '' then
    return jsonb_build_object('ok', false, 'error', 'password_not_set');
  end if;
  if p_password is null or crypt(p_password, v_hash) <> v_hash then
    insert into cancel_auth_failures (user_id) values (v_admin);
    return jsonb_build_object(
      'ok', false, 'error', 'wrong_password', 'remaining', greatest(0, 4 - v_fails)
    );
  end if;
  delete from cancel_auth_failures where user_id = v_admin;

  -- The operation, locked.
  if p_kind = 'transfer' then
    select * into v_t from transfers
     where id = p_operation_id and owner_id = v_admin
       for update;
    if not found then
      raise exception 'cancel_not_found' using errcode = 'P0001';
    end if;
    if v_t.status <> 'archived' then
      raise exception 'cancel_not_cancellable' using errcode = 'P0001';
    end if;
    if v_t.cancelled_at is not null then
      raise exception 'cancel_already' using errcode = 'P0001';
    end if;
    v_company := v_t.company_id;  v_exchange := v_t.exchange_id;
    v_amount  := v_t.amount;      v_ref      := v_t.reference;
    v_party   := v_t.beneficiary_name;
    v_at      := v_t.created_at;  v_emp      := v_t.created_by_employee_id;
  else
    select * into v_b from currency_buys
     where id = p_operation_id and owner_id = v_admin
       for update;
    if not found then
      raise exception 'cancel_not_found' using errcode = 'P0001';
    end if;
    if v_b.status <> 'archived' then
      raise exception 'cancel_not_cancellable' using errcode = 'P0001';
    end if;
    if v_b.cancelled_at is not null then
      raise exception 'cancel_already' using errcode = 'P0001';
    end if;
    v_company := v_b.my_company_id;  v_exchange := v_b.exchange_id;
    v_amount  := v_b.usd_amount;     v_ref      := v_b.reference;
    select coalesce(c.name, v_b.client_from_account) into v_party
      from (select 1) x left join clients c on c.id = v_b.client_id;
    v_at      := v_b.created_at;     v_emp      := v_b.created_by_employee_id;
  end if;

  if _ops_day(v_at) <> _ops_day(now()) then
    raise exception 'cancel_day_passed' using errcode = 'P0001';
  end if;

  -- The reversing entry, on the locked account.
  select balance, name, our_code into v_before, v_ex_name, v_ex_code
    from exchanges where id = v_exchange for update;
  if p_kind = 'transfer' then
    v_after := v_before + v_amount;
  else
    v_after := v_before - v_amount;
    if v_after < 0 then
      raise exception 'cancel_insufficient_balance' using errcode = 'P0001',
        detail = format('balance %s, entry %s', v_before, v_amount);
    end if;
  end if;
  update exchanges set balance = v_after where id = v_exchange;

  if p_kind = 'transfer' then
    update transfers set cancelled_at = now() where id = p_operation_id;
  else
    update currency_buys set cancelled_at = now() where id = p_operation_id;
  end if;

  -- The request(s) for it, approved.
  if p_request_id is not null and not exists (
    select 1 from cancellation_requests
     where id = p_request_id and owner_id = v_admin
       and operation_id = p_operation_id and status = 'pending'
  ) then
    raise exception 'cancel_request_not_found' using errcode = 'P0001';
  end if;
  update cancellation_requests
     set status = 'approved', decided_at = now()
   where operation_id = p_operation_id and status = 'pending'
  returning id, employee_name, sub_user_id into v_req_id, v_req_name, v_req_emp;

  select name into v_co_name from companies where id = v_company;
  if v_emp is not null then
    select employee_name into v_emp_name from sub_users where id = v_emp;
  end if;

  insert into operation_cancellations (
    owner_id, kind, operation_id, company_id, exchange_id, company_name,
    exchange_name, exchange_code, amount, reference, party_name,
    operation_created_at, operation_employee_id, operation_employee_name,
    request_id, requested_by_name, reason, balance_before, balance_after,
    cancelled_by, cancelled_by_name
  ) values (
    v_admin, p_kind, p_operation_id, v_company, v_exchange, v_co_name,
    v_ex_name, v_ex_code, v_amount, v_ref, v_party,
    v_at, v_emp, case when v_emp is null then 'المدير' else coalesce(v_emp_name, '—') end,
    v_req_id, v_req_name, v_reason, v_before, v_after,
    v_admin, v_admin_name
  )
  returning id into v_id;

  -- Tell the employee whose operation it was.
  if v_emp is not null then
    insert into employee_messages (owner_id, sub_user_id, broadcast_id, title, body)
    values (
      v_admin, v_emp, gen_random_uuid(), 'تم إلغاء عملية',
      format(E'تم إلغاء عملية "%s" بقيمة %s$\nالسبب: %s',
             case p_kind when 'transfer' then 'خروج' else 'دخول' end,
             to_char(v_amount, 'FM999G999G990D00'), v_reason)
    );
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'balance_after', v_after);
end;
$$;
revoke all on function admin_cancel_operation(text, uuid, text, text, uuid) from public, anon;
grant execute on function admin_cancel_operation(text, uuid, text, text, uuid) to authenticated;

-- -------------------------------------------------------------------------
-- 11) Backups carry the two new tables
-- -------------------------------------------------------------------------
create or replace function public._build_backup()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t      text;
  v      jsonb;
  result jsonb := '{}'::jsonb;
begin
  foreach t in array array[
    'profiles', 'account_licenses',
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs', 'notifications',
    'cancellation_requests', 'operation_cancellations'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format(
        'select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from public.%I x',
        t
      ) into v;
      result := result || jsonb_build_object(t, v);
    end if;
  end loop;

  return jsonb_build_object(
    'app', 'eshary',
    'version', 1,
    'created_at', now(),
    'tables', result
  );
end;
$$;

-- Same as 0046 plus the two cancellation tables.
create or replace function public.admin_restore_backup(p_backup jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tables jsonb := p_backup -> 'tables';
  v_rows   jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_n      integer;
  t        text;
  v_filter text;
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  if p_backup ->> 'app' is distinct from 'eshary'
     or (p_backup ->> 'version') is distinct from '1'
     or v_tables is null then
    raise exception 'invalid backup file';
  end if;

  perform set_config('eshary.skip_balance_check', 'on', true);

  -- Safety net: snapshot the current state first.
  perform public._save_backup('pre_restore');

  -- Children first.
  delete from public.operation_cancellations;
  delete from public.cancellation_requests;
  delete from public.employee_activity_logs;
  delete from public.transfers;
  delete from public.currency_buys;
  delete from public.exchanges;
  delete from public.clients;
  delete from public.beneficiaries;
  delete from public.countries;
  delete from public.exchange_companies;
  delete from public.companies;
  delete from public.sub_users;
  delete from public.branches;

  -- Parents first. Rows whose owning account no longer exists are skipped.
  foreach t in array array[
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs',
    'cancellation_requests', 'operation_cancellations'
  ] loop
    v_rows := coalesce(v_tables -> t, '[]'::jsonb);

    -- The activity log points at login sessions, which are not part of a
    -- backup and were deleted with the employees. Restoring the log with its
    -- session ids fails on the foreign key, so restore it without them.
    if t = 'employee_activity_logs' then
      select coalesce(jsonb_agg(elem - 'session_id'), '[]'::jsonb)
        into v_rows
        from jsonb_array_elements(v_rows) elem;
    end if;

    v_filter := case t
      when 'branches'               then 'r.parent_admin_id in (select id from auth.users)'
      when 'sub_users'              then 'r.parent_admin_id in (select id from auth.users)'
      when 'employee_activity_logs' then 'r.parent_admin_id in (select id from auth.users)'
      when 'exchanges'              then 'r.company_id in (select id from public.companies)'
      else                               'r.owner_id in (select id from public.profiles)'
    end;

    execute format(
      'insert into public.%1$I select r.* from jsonb_populate_recordset(null::public.%1$I, $1) r where %2$s',
      t, v_filter
    ) using v_rows;
    get diagnostics v_n = row_count;
    v_counts := v_counts || jsonb_build_object(t, v_n);
  end loop;

  return v_counts;
end;
$$;

-- -------------------------------------------------------------------------
-- 12) Live updates for the requests
-- -------------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table cancellation_requests;
exception when duplicate_object then null;
         when undefined_object then null;
end $$;

commit;
