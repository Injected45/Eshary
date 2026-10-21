-- 0072_account_expenses.sql
-- A one-sided deduction from an account: the commission an exchange company
-- charges for managing the account (or any other expense of that account).
-- There is no other party and no message: the amount leaves the account's
-- balance and stays on record with its code and what it was for.
--
--   record_account_expense(exchange, amount, code, note)
--       the administrator only; the amount must be > 0 and must NOT exceed the
--       account's balance (it never goes below zero); the balance moves in the
--       same transaction, like an exit.
--   admin_cancel_expense(id, reason, password)
--       a mistake is cancelled the SAME Libya day, with the administrator's
--       password (five wrong tries lock it for 15 minutes, shared with the
--       operations). The money returns by a reversing entry; the record keeps
--       every value, nothing is edited or deleted.
--
-- Backups, restores and the "delete my data" / "delete entries" functions now
-- know the new table. Safe to run more than once.

begin;

create table if not exists account_expenses (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references auth.users (id) on delete cascade,
  exchange_id        uuid not null references exchanges (id) on delete cascade,
  amount             numeric(14, 2) not null check (amount > 0),
  code               text check (code is null or char_length(code) between 1 and 60),
  note               text not null check (char_length(note) between 1 and 300),
  balance_before     numeric(14, 2) not null,
  balance_after      numeric(14, 2) not null,
  created_at         timestamptz not null default now(),
  created_by_name    text not null,
  cancelled_at       timestamptz,
  cancelled_by_name  text,
  cancel_reason      text
);

create index if not exists account_expenses_exchange_idx
  on account_expenses (exchange_id, created_at desc);
create index if not exists account_expenses_owner_idx
  on account_expenses (owner_id, created_at desc);

alter table account_expenses enable row level security;

-- Read: the administrator only. No insert / update / delete from the API.
drop policy if exists account_expenses_select_admin on account_expenses;
create policy account_expenses_select_admin on account_expenses
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    and (select current_employee_id()) is null
  );

drop policy if exists license_gate on account_expenses;
create policy license_gate on account_expenses
  as restrictive for all to authenticated using ((select license_ok()));

revoke all on account_expenses from anon;
revoke insert, update, delete on account_expenses from authenticated;

-- -------------------------------------------------------------------------
-- Record an expense
-- -------------------------------------------------------------------------
create or replace function record_account_expense(
  p_exchange_id uuid,
  p_amount      numeric,
  p_code        text,
  p_note        text
) returns account_expenses
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin      uuid := auth.uid();
  v_amount     numeric := round(coalesce(p_amount, 0), 2);
  v_code       text := nullif(btrim(coalesce(p_code, '')), '');
  v_note       text := btrim(coalesce(p_note, ''));
  v_before     numeric;
  v_admin_name text;
  v_row        account_expenses;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if v_amount <= 0 or v_amount > 999999999999.99 then
    raise exception 'expense_amount_invalid' using errcode = 'P0001';
  end if;
  if char_length(v_note) < 1 then
    raise exception 'expense_note_required' using errcode = 'P0001';
  end if;
  if char_length(v_note) > 300 or char_length(coalesce(v_code, '')) > 60 then
    raise exception 'expense_text_too_long' using errcode = 'P0001';
  end if;

  -- the account, locked, and only one of this administrator's
  select e.balance into v_before
    from exchanges e
    join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'expense_account_not_found' using errcode = 'P0001';
  end if;
  if v_before < v_amount then
    raise exception 'insufficient_balance' using errcode = 'P0001',
      detail = format('balance %s, expense %s', v_before, v_amount);
  end if;

  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_admin_name
    from auth.users u where u.id = v_admin;

  update exchanges set balance = v_before - v_amount where id = p_exchange_id;

  insert into account_expenses (
    owner_id, exchange_id, amount, code, note,
    balance_before, balance_after, created_by_name
  ) values (
    v_admin, p_exchange_id, v_amount, v_code, v_note,
    v_before, v_before - v_amount, coalesce(v_admin_name, 'المدير')
  )
  returning * into v_row;

  return v_row;
end;
$$;
revoke all on function record_account_expense(uuid, numeric, text, text) from public, anon;
grant execute on function record_account_expense(uuid, numeric, text, text) to authenticated;

-- -------------------------------------------------------------------------
-- Cancel an expense (same day, with the password)
-- Returns {"ok": true, "balance_after": ...}; a wrong password returns
-- {"ok": false, "error": "wrong_password", "remaining": n} (kept for the lock).
-- -------------------------------------------------------------------------
create or replace function admin_cancel_expense(
  p_expense_id uuid,
  p_reason     text,
  p_password   text
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
  v_x          account_expenses;
  v_before     numeric;
  v_after      numeric;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception 'cancel_reason_required' using errcode = 'P0001';
  end if;

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
    from auth.users u where u.id = v_admin;

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

  select * into v_x from account_expenses
   where id = p_expense_id and owner_id = v_admin
     for update;
  if not found then
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;
  if v_x.cancelled_at is not null then
    raise exception 'cancel_already' using errcode = 'P0001';
  end if;
  if _ops_day(v_x.created_at) <> _ops_day(now()) then
    raise exception 'cancel_day_passed' using errcode = 'P0001';
  end if;

  select balance into v_before from exchanges where id = v_x.exchange_id for update;
  v_after := v_before + v_x.amount;
  update exchanges set balance = v_after where id = v_x.exchange_id;

  update account_expenses
     set cancelled_at = now(),
         cancelled_by_name = coalesce(v_admin_name, 'المدير'),
         cancel_reason = v_reason
   where id = p_expense_id;

  return jsonb_build_object('ok', true, 'id', p_expense_id, 'balance_after', v_after);
end;
$$;
revoke all on function admin_cancel_expense(uuid, text, text) from public, anon;
grant execute on function admin_cancel_expense(uuid, text, text) to authenticated;

-- -------------------------------------------------------------------------
-- The new table in backups, restores, "delete entries" and account deletion
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
    'cancellation_requests', 'operation_cancellations',
    'account_expenses'
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
  perform set_config('eshary.restoring', 'on', true);

  -- Safety net: snapshot the current state first.
  perform public._save_backup('pre_restore');

  -- Children first.
  delete from public.operation_cancellations where true;
  delete from public.cancellation_requests where true;
  delete from public.account_expenses where true;
  delete from public.employee_activity_logs where true;
  delete from public.transfers where true;
  delete from public.currency_buys where true;
  delete from public.exchanges where true;
  delete from public.clients where true;
  delete from public.beneficiaries where true;
  delete from public.countries where true;
  delete from public.exchange_companies where true;
  delete from public.companies where true;
  delete from public.sub_users where true;
  delete from public.branches where true;

  -- Parents first. Rows whose owning account no longer exists are skipped.
  foreach t in array array[
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs',
    'cancellation_requests', 'operation_cancellations',
    'account_expenses'
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
      when 'account_expenses'       then 'r.exchange_id in (select id from public.exchanges)'
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

create or replace function _redact_owner_from_backups(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.backups b
     set data = jsonb_set(
       b.data,
       '{tables}',
       (
         select coalesce(jsonb_object_agg(e.k, case
           when e.k = 'profiles' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'id' is distinct from p_uid::text)
           when e.k = 'account_licenses' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'user_id' is distinct from p_uid::text)
           when e.k in ('branches', 'sub_users', 'employee_activity_logs') then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'parent_admin_id' is distinct from p_uid::text)
           when e.k = 'exchanges' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where (r ->> 'company_id') not in (
                 select c ->> 'id'
                   from jsonb_array_elements(coalesce(b.data -> 'tables' -> 'companies', '[]'::jsonb)) c
                  where c ->> 'owner_id' = p_uid::text))
           when e.k in ('companies', 'clients', 'beneficiaries', 'countries',
                        'exchange_companies', 'transfers', 'currency_buys',
                        'cancellation_requests', 'operation_cancellations',
                        'account_expenses') then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'owner_id' is distinct from p_uid::text)
           else e.v
         end), '{}'::jsonb)
         from jsonb_each(b.data -> 'tables') as e(k, v)
       )
     )
   where jsonb_typeof(b.data -> 'tables') = 'object';
  update public.backups set size_bytes = octet_length(data::text) where true;
end;
$$;

create or replace function owner_wipe_operations()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner  uuid := auth.uid();
  v_backup uuid;
  v_t      integer;
  v_b      integer;
  v_c      integer;
  v_x      integer;
begin
  if v_owner is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;

  -- A way back: a full snapshot before anything is deleted.
  v_backup := public._save_backup('pre_wipe');

  delete from operation_cancellations where owner_id = v_owner;
  get diagnostics v_c = row_count;
  delete from cancellation_requests where owner_id = v_owner;
  delete from account_expenses where owner_id = v_owner;
  delete from admin_alerts
   where owner_id = v_owner
     and kind in ('transfer', 'buy', 'pending_buy',
                  'cancel_request_transfer', 'cancel_request_buy');

  delete from transfers where owner_id = v_owner;
  get diagnostics v_t = row_count;
  delete from currency_buys where owner_id = v_owner;
  get diagnostics v_b = row_count;

  update exchanges e set balance = 0
    from companies c
   where e.company_id = c.id and c.owner_id = v_owner and e.balance <> 0;
  get diagnostics v_x = row_count;

  insert into wiped_operations (
    owner_id, owner_email, transfers, currency_buys, cancellations,
    balances_reset, backup_id
  ) values (
    v_owner, (select u.email from auth.users u where u.id = v_owner),
    v_t, v_b, v_c, v_x, v_backup
  );

  return jsonb_build_object(
    'ok', true, 'transfers', v_t, 'currency_buys', v_b,
    'cancellations', v_c, 'balances_reset', v_x, 'backup_id', v_backup
  );
end;
$$;

commit;
