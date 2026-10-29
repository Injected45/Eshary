-- 0089_integrity_review_fixes.sql
-- Fixes from the independent review of 0087 / 0088 (2026-10-29). Each was
-- reproduced on a test database before being fixed:
--
--  1) Wiping, then restoring the wipe's own safety copy, made the numbering
--     jump (RH0102 → RH0106): the copy was taken AFTER the starting reference
--     had been moved. The copy is now taken first.
--  2) Restoring a subscriber from a backup that does not contain them
--     (taken before they signed up) deleted all their data and put nothing
--     back. Refused now: owner_not_in_backup.
--  3) Restoring an OLDER backup of a subscriber made the numbering go back:
--     numbers already sent to the partner companies after that backup would
--     be given again. Each company now goes on from at least the number it
--     would have given before the restore.
--  4) An account already below zero (from an old build) could not even take
--     an entry that brings it closer to zero. A balance may still never GO
--     below zero or move further down while below it.
--  5) A wipe at the very moment an entry is saved could leave that entry
--     behind, or fail one of the two: the wipe now locks the accounts first,
--     in the same order as the save functions.
--  6) Past the last number of its width (Rh9999) the next reference was cut
--     to Rh1000 instead of growing to Rh10000 as in project_web.html.
--
-- Needs 0088. Safe to run more than once.

begin;

do $$
begin
  if to_regprocedure('public.admin_restore_owner(uuid, uuid)') is null then
    raise exception 'شغّل الترحيل 0088 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
  -- run again after 0091 it would drop the customers' accounts from the wipe
  -- and the restore
  if to_regclass('public.customer_lyd_entries') is not null then
    raise exception 'هذا الملف (0089) طُبِّق سابقًا وتبعه 0091. لا تشغّله مرة أخرى. لم يتغير شيء.';
  end if;
end $$;

-- a number padded with zeros to [p_width] digits, never cut (lpad cuts)
create or replace function _ref_pad(p_n numeric, p_width integer)
returns text
language sql
immutable
as $$ select lpad(p_n::text, greatest(p_width, length(p_n::text)), '0') $$;

-- the next reference of a company, for the database's own use (next_reference
-- without the caller check: the platform restoring a subscriber is not them)
create or replace function _next_reference_for(p_owner uuid, p_company_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_start_ref text;
  v_count     integer;
  v_match     text[];
  v_prefix    text;
  v_first     numeric;
  v_pad_width integer;
  v_max       numeric;
begin
  select start_ref into v_start_ref
    from companies where id = p_company_id and owner_id = p_owner;
  if not found then
    return null;
  end if;
  select count(*) into v_count
    from transfers where owner_id = p_owner and cancelled_at is null;
  v_match := regexp_match(coalesce(v_start_ref, ''), '^([^0-9]*)([0-9]+)$');
  if v_match is not null then
    v_prefix := v_match[1]; v_first := v_match[2]::numeric; v_pad_width := length(v_match[2]);
  else
    v_prefix := coalesce(v_start_ref, ''); v_first := 1; v_pad_width := 3;
  end if;
  select max(substr(reference, length(v_prefix) + 1)::numeric)
    into v_max
    from transfers
   where owner_id = p_owner
     and cancelled_at is null
     and left(reference, length(v_prefix)) = v_prefix
     and substr(reference, length(v_prefix) + 1) ~ '^[0-9]{1,30}$';
  return v_prefix || _ref_pad(greatest(v_first + v_count, coalesce(v_max + 1, 0)), v_pad_width);
end;
$$;
revoke all on function _next_reference_for(uuid, uuid) from public, anon, authenticated;

-- 6) next_reference: past the last number of its width the number grows a
-- digit (Rh9999 → Rh10000), as padStart does in project_web.html; lpad cut it
-- to Rh1000 — a number already given. Otherwise unchanged (0080).
create or replace function next_reference(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_id uuid := effective_admin_id();
  v_owner    uuid;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  select owner_id into v_owner from companies where id = p_company_id;
  if v_owner is null then
    raise exception 'company % not found', p_company_id;
  end if;
  if v_owner <> v_admin_id then
    raise exception 'not_authorized: company does not belong to caller';
  end if;
  return _next_reference_for(v_owner, p_company_id);
end;
$$;

-- 4) never below zero, but an account already below it may come back up --------
create or replace function _block_direct_balance_edit()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' and new.balance <> 0 then
      raise exception 'balance_direct_edit' using errcode = 'P0001';
    end if;
    if tg_op = 'UPDATE' and new.balance is distinct from old.balance then
      raise exception 'balance_direct_edit' using errcode = 'P0001';
    end if;
  end if;
  if new.balance < 0
     and (tg_op = 'INSERT' or new.balance < old.balance)
     and coalesce(current_setting('eshary.restoring', true), '') <> 'on' then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- 1 + 5) the wipe: the accounts locked first, the safety copy before anything --
create or replace function owner_wipe_operations(p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner  uuid := auth.uid();
  v_err    jsonb;
  v_backup uuid;
  v_t      integer;
  v_b      integer;
  v_c      integer;
  v_x      integer;
  r        record;
begin
  if v_owner is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  v_err := _admin_password_error(v_owner, p_password);
  if v_err is not null then
    return v_err;
  end if;

  -- no exit of this administrator meanwhile (the reference lock), and every
  -- account locked before anything else, in the order the saves lock them:
  -- an entry saved at this moment either finishes first or waits for the wipe
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || v_owner::text, 0));
  perform 1 from exchanges e join companies c on c.id = e.company_id
   where c.owner_id = v_owner
   order by e.id
     for update of e;

  -- A way back: a full snapshot before anything changes (the numbering too).
  v_backup := public._save_backup('pre_wipe');

  -- the numbering goes on after the last number used: every company starts
  -- again from the number it would have given next
  for r in select id from companies where owner_id = v_owner loop
    update companies set start_ref = _next_reference_for(v_owner, r.id) where id = r.id;
  end loop;

  delete from lyd_counts where owner_id = v_owner;
  delete from lyd_movements where owner_id = v_owner;
  delete from lyd_treasury where owner_id = v_owner;
  delete from operation_costs where owner_id = v_owner;
  delete from account_cost_events where owner_id = v_owner;
  delete from account_costs where owner_id = v_owner;
  delete from balance_adjustments where owner_id = v_owner;

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
revoke all on function owner_wipe_operations(text) from public, anon;
grant execute on function owner_wipe_operations(text) to authenticated;

-- 2 + 3) restoring one subscriber -------------------------------------------------
create or replace function public.admin_restore_owner(p_backup_id uuid, p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tables jsonb;
  v_rows   jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_n      integer;
  t        text;
  v_filter text;
  v_before jsonb := '{}'::jsonb;
  r        record;
  v_old    text[];
  v_new    text[];
  v_now    text;
  v_active integer;
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
  -- a backup without this subscriber would only delete them
  if not exists (
    select 1 from jsonb_array_elements(coalesce(v_tables -> 'companies', '[]'::jsonb)) c
     where c ->> 'owner_id' = p_owner::text
  ) then
    raise exception 'owner_not_in_backup' using errcode = 'P0001';
  end if;

  perform set_config('eshary.skip_balance_check', 'on', true);
  perform set_config('eshary.restoring', 'on', true);
  -- no exit of this subscriber is saved while the restore runs
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || p_owner::text, 0));

  -- the number each company would give next NOW: never given again
  for r in select id from public.companies where owner_id = p_owner loop
    v_before := v_before || jsonb_build_object(r.id::text, _next_reference_for(p_owner, r.id));
  end loop;

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

  -- the numbering never goes back: a company now behind the number it would
  -- have given before the restore starts again from that number
  select count(*) into v_active
    from public.transfers where owner_id = p_owner and cancelled_at is null;
  for r in select id from public.companies where owner_id = p_owner loop
    v_now := v_before ->> r.id::text;
    continue when v_now is null;
    v_old := regexp_match(v_now, '^([^0-9]*)([0-9]+)$');
    v_new := regexp_match(coalesce(_next_reference_for(p_owner, r.id), ''), '^([^0-9]*)([0-9]+)$');
    if v_old is not null and v_new is not null and v_old[1] = v_new[1]
       and v_new[2]::numeric < v_old[2]::numeric
       and v_old[2]::numeric - v_active >= 0 then
      update public.companies
         set start_ref = v_old[1] || _ref_pad(v_old[2]::numeric - v_active, length(v_old[2]))
       where id = r.id;
    end if;
  end loop;

  return v_counts;
end;
$$;
revoke all on function public.admin_restore_owner(uuid, uuid) from public, anon;
grant execute on function public.admin_restore_owner(uuid, uuid) to authenticated;

commit;
