-- 0088_restore_one_subscriber.sql
-- Phase 1 of docs/accounting-audit-and-plan.md (gap ث1): restoring a backup
-- for ONE subscriber.
--
-- Until now the only restore (admin_restore_backup) replaced the whole
-- database with the backup: undoing one subscriber's mistake (a wrong wipe,
-- say) also took every other subscriber back to the moment of the backup and
-- lost all their operations since. Now the platform restores one subscriber:
--
--   admin_backup_owners(backup_id)        who is in a stored backup (name,
--                                         e-mail, operations), to choose from
--   admin_restore_owner(backup_id, owner) that subscriber's rows only, from a
--                                         backup stored on the server (never a
--                                         file sent by the phone); everyone
--                                         else is untouched
--
-- A safety snapshot (kind 'pre_restore') is taken first, as for the full
-- restore. The full restore stays for a real disaster only. Needs 0087. Safe
-- to run more than once.

begin;

do $$
begin
  if to_regprocedure('public.admin_open_account(uuid, text, numeric, text, text, numeric)') is null then
    raise exception 'شغّل الترحيل 0087 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
  -- run again after 0089 it would bring back what 0089 fixed
  if to_regprocedure('public._next_reference_for(uuid, uuid)') is not null then
    raise exception 'هذا الملف (0088) طُبِّق سابقًا وصحّحه 0089. لا تشغّله مرة أخرى. لم يتغير شيء.';
  end if;
end $$;

-- who is in a stored backup -------------------------------------------------------
create or replace function public.admin_backup_owners(p_backup_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tables jsonb;
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  select data -> 'tables' into v_tables from public.backups where id = p_backup_id;
  if v_tables is null then
    raise exception 'backup_not_found' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'owner_id', o.owner_id,
             'email', u.email,
             'name', coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                              nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                              u.email),
             'exists', u.id is not null,
             'transfers', (select count(*) from jsonb_array_elements(coalesce(v_tables -> 'transfers', '[]'::jsonb)) t
                            where t ->> 'owner_id' = o.owner_id::text),
             'currency_buys', (select count(*) from jsonb_array_elements(coalesce(v_tables -> 'currency_buys', '[]'::jsonb)) b
                                where b ->> 'owner_id' = o.owner_id::text))
           order by u.email nulls last)
      from (select distinct (c ->> 'owner_id')::uuid as owner_id
              from jsonb_array_elements(coalesce(v_tables -> 'companies', '[]'::jsonb)) c) o
      left join auth.users u on u.id = o.owner_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_backup_owners(uuid) from public, anon;
grant execute on function public.admin_backup_owners(uuid) to authenticated;

-- restore one subscriber ----------------------------------------------------------
create or replace function public.admin_restore_owner(p_backup_id uuid, p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tables jsonb;
  v_rows   jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_n      integer;
  t        text;
  v_filter text;
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  select data -> 'tables' into v_tables from public.backups where id = p_backup_id;
  if v_tables is null then
    raise exception 'backup_not_found' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = p_owner) then
    raise exception 'owner_not_found' using errcode = 'P0001';
  end if;

  perform set_config('eshary.skip_balance_check', 'on', true);
  perform set_config('eshary.restoring', 'on', true);
  -- no exit of this subscriber is saved while the restore runs
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || p_owner::text, 0));

  -- Safety net: snapshot the current state first.
  perform public._save_backup('pre_restore');

  -- this subscriber's rows only, children first
  delete from public.lyd_counts where owner_id = p_owner;
  delete from public.lyd_movements where owner_id = p_owner;
  delete from public.lyd_treasury where owner_id = p_owner;
  delete from public.balance_adjustments where owner_id = p_owner;
  delete from public.operation_costs where owner_id = p_owner;
  delete from public.account_cost_events where owner_id = p_owner;
  delete from public.account_costs where owner_id = p_owner;
  delete from public.last_exchange_rates where owner_id = p_owner;
  delete from public.operation_cancellations where owner_id = p_owner;
  delete from public.cancellation_requests where owner_id = p_owner;
  delete from public.account_expenses where owner_id = p_owner;
  delete from public.employee_activity_logs where parent_admin_id = p_owner;
  delete from public.transfers where owner_id = p_owner;
  delete from public.currency_buys where owner_id = p_owner;
  delete from public.exchanges
   where company_id in (select id from public.companies where owner_id = p_owner);
  delete from public.clients where owner_id = p_owner;
  delete from public.beneficiaries where owner_id = p_owner;
  delete from public.countries where owner_id = p_owner;
  delete from public.exchange_companies where owner_id = p_owner;
  delete from public.companies where owner_id = p_owner;
  delete from public.sub_users where parent_admin_id = p_owner;
  delete from public.branches where parent_admin_id = p_owner;

  -- parents first, as the full restore
  foreach t in array array[
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs',
    'cancellation_requests', 'operation_cancellations',
    'account_expenses',
    'last_exchange_rates', 'account_costs', 'account_cost_events',
    'operation_costs',
    'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts'
  ] loop
    v_rows := coalesce(v_tables -> t, '[]'::jsonb);

    if t = 'employee_activity_logs' then
      select coalesce(jsonb_agg(elem - 'session_id'), '[]'::jsonb)
        into v_rows
        from jsonb_array_elements(v_rows) elem;
    end if;

    v_filter := case t
      when 'branches'               then 'r.parent_admin_id = $2'
      when 'sub_users'              then 'r.parent_admin_id = $2'
      when 'employee_activity_logs' then 'r.parent_admin_id = $2'
      when 'exchanges'              then 'r.company_id in (select id from public.companies where owner_id = $2)'
      else                               'r.owner_id = $2'
    end;

    execute format(
      'insert into public.%1$I select r.* from jsonb_populate_recordset(null::public.%1$I, $1) r where %2$s',
      t, v_filter
    ) using v_rows, p_owner;
    get diagnostics v_n = row_count;
    v_counts := v_counts || jsonb_build_object(t, v_n);
  end loop;

  return v_counts;
end;
$$;
revoke all on function public.admin_restore_owner(uuid, uuid) from public, anon;
grant execute on function public.admin_restore_owner(uuid, uuid) to authenticated;

commit;
