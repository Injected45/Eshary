-- 0046_available_balance.sql
-- An exit may not exceed the account's AVAILABLE balance.
--
--   available = exchanges.balance - the exits of the day not yet closed
--
-- exchanges.balance only moves when the day is closed (migration 0017), so the
-- balance alone lets several exits each pass while their total does not fit.
-- Before this, the limit also lived only in the app; calling the API directly
-- skipped it.
--
--   * trigger on transfers: every new daily exit (the admin's, an employee's,
--     or a direct insert) is refused with 'insufficient_balance' when the
--     amount is more than the available balance. The exchange row is locked
--     meanwhile, so two simultaneous exits cannot both pass.
--   * exchange_balances(): balance, open exits and available per account, for
--     the exit screen. The open exits include other employees', as a total
--     only, so an employee sees the true figure without seeing their rows.
--   * admin_restore_backup skips the check, so restoring an old backup that
--     was already overdrawn still works. It also no longer fails when an
--     employee has ever logged in (their activity log pointed at login
--     sessions that a restore deletes).
--
-- Entries (دخول) do not add to the available balance until they are closed,
-- like the balance itself.

begin;

create or replace function exchange_balances()
returns table (
  exchange_id uuid,
  balance     numeric,
  open_out    numeric,
  available   numeric
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
begin
  if v_admin is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if current_employee_id() is not null
     and not employee_has_perm('transfers_create') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;

  return query
  select e.id,
         e.balance,
         coalesce(o.s, 0),
         e.balance - coalesce(o.s, 0)
    from exchanges e
    join companies c on c.id = e.company_id and c.owner_id = v_admin
    left join lateral (
      select sum(t.amount) as s
        from transfers t
       where t.exchange_id = e.id and t.status = 'daily'
    ) o on true;
end;
$$;
revoke all on function exchange_balances() from public, anon;
grant execute on function exchange_balances() to authenticated;

create or replace function _check_transfer_balance()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_balance numeric;
  v_open    numeric;
begin
  if coalesce(current_setting('eshary.skip_balance_check', true), '') = 'on' then
    return new;
  end if;

  -- Lock the account so concurrent exits are checked one after the other.
  select balance into v_balance from exchanges where id = new.exchange_id for update;
  if not found then
    return new; -- the foreign key reports the missing account
  end if;

  select coalesce(sum(amount), 0) into v_open
    from transfers
   where exchange_id = new.exchange_id and status = 'daily';

  if new.amount > v_balance - v_open then
    raise exception 'insufficient_balance' using errcode = 'P0001',
      detail = format('balance %s, open exits %s, requested %s',
                      v_balance, v_open, new.amount);
  end if;
  return new;
end;
$$;
revoke all on function _check_transfer_balance() from public, anon, authenticated;

drop trigger if exists trg_check_transfer_balance on transfers;
create trigger trg_check_transfer_balance
  before insert on transfers
  for each row
  when (new.status = 'daily')
  execute function _check_transfer_balance();

-- Same function as 0028 plus the line that skips the balance check for the
-- rows it puts back (the flag lasts only for this transaction).
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
    'employee_activity_logs'
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
