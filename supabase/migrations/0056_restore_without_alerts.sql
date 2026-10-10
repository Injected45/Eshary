-- 0056_restore_without_alerts.sql
-- Restoring a backup re-inserts every operation, and the "new operation from
-- an employee" triggers (0045) fired for each re-inserted row: after every
-- restore the admin got a burst of duplicate alerts (and the sound). The
-- triggers now stay quiet while a restore runs (transaction-local flag
-- eshary.restoring, set by admin_restore_backup). Nothing else changes.

begin;

create or replace function _alert_on_employee_transfer()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name text;
begin
  -- A restore puts rows back; they are not new operations.
  if coalesce(current_setting('eshary.restoring', true), '') = 'on' then
    return new;
  end if;
  select employee_name into v_name from sub_users where id = new.created_by_employee_id;
  insert into admin_alerts (
    owner_id, sub_user_id, employee_name, kind, operation_id, amount, party_name
  ) values (
    new.owner_id, new.created_by_employee_id, coalesce(v_name, '—'),
    'transfer', new.id, new.amount, new.beneficiary_name
  );
  return new;
end;
$$;
revoke all on function _alert_on_employee_transfer() from public, anon, authenticated;

create or replace function _alert_on_employee_buy()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name   text;
  v_client text;
begin
  if coalesce(current_setting('eshary.restoring', true), '') = 'on' then
    return new;
  end if;
  select employee_name into v_name from sub_users where id = new.created_by_employee_id;
  select name into v_client from clients where id = new.client_id;
  insert into admin_alerts (
    owner_id, sub_user_id, employee_name, kind, operation_id, amount, party_name
  ) values (
    new.owner_id, new.created_by_employee_id, coalesce(v_name, '—'),
    case when new.status = 'pending' then 'pending_buy' else 'buy' end,
    new.id, new.usd_amount, v_client
  );
  return new;
end;
$$;
revoke all on function _alert_on_employee_buy() from public, anon, authenticated;

-- Same as 0048 plus the eshary.restoring flag.
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

commit;
