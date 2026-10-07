-- 0028_backups.sql
-- Hourly automatic snapshots + admin export / restore.
--
--   public.backups                      snapshots (JSON), no direct client access
--   _build_backup()                     builds a JSON snapshot of every app table
--   _save_backup(kind)                  stores a snapshot, returns its id
--   backup_hourly()                     called by pg_cron: snapshot + retention
--   admin_backup_now()                  admin: store a manual snapshot
--   admin_list_backups()                admin: list stored snapshots
--   admin_get_backup(id)                admin: fetch one stored snapshot (JSON)
--   admin_export_backup()               admin: live snapshot, for download
--   admin_restore_backup(json)          admin: full replace of operational data
--
-- Restore replaces the operational tables only (companies, exchanges,
-- clients, beneficiaries, countries, exchange_companies, transfers,
-- currency_buys, branches, sub_users, employee_activity_logs). It never
-- touches auth.users, profiles, account_licenses or employee_sessions, so
-- accounts, licences and sign-ins stay exactly as they are. A safety
-- snapshot (kind = 'pre_restore') is stored first.

begin;

create table if not exists public.backups (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('auto', 'manual', 'pre_restore')),
  created_at  timestamptz not null default now(),
  size_bytes  integer not null default 0,
  data        jsonb not null
);

create index if not exists backups_created_at_idx
  on public.backups (created_at desc);

alter table public.backups enable row level security;
-- No policies on purpose: only the security-definer functions below touch it.
revoke all on public.backups from anon, authenticated;

-- -------------------------------------------------------------------------
-- Snapshot builder: every table that exists, as an array of row objects.
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
    'employee_activity_logs', 'notifications'
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

create or replace function public._save_backup(p_kind text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb := public._build_backup();
  v_id   uuid;
begin
  insert into public.backups (kind, size_bytes, data)
  values (p_kind, octet_length(v_data::text), v_data)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public._build_backup() from public, anon, authenticated;
revoke all on function public._save_backup(text) from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- Hourly job body: snapshot, then keep the newest 168 auto snapshots (7 days)
-- and the newest 20 manual / pre_restore ones.
-- -------------------------------------------------------------------------
create or replace function public.backup_hourly()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._save_backup('auto');

  delete from public.backups
   where kind = 'auto'
     and id not in (
       select id from public.backups
        where kind = 'auto'
        order by created_at desc
        limit 168
     );

  delete from public.backups
   where kind in ('manual', 'pre_restore')
     and id not in (
       select id from public.backups
        where kind in ('manual', 'pre_restore')
        order by created_at desc
        limit 20
     );
end;
$$;

revoke all on function public.backup_hourly() from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- Admin RPCs
-- -------------------------------------------------------------------------
create or replace function public.admin_backup_now()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  return public._save_backup('manual');
end;
$$;

create or replace function public.admin_list_backups()
returns table (id uuid, kind text, created_at timestamptz, size_bytes integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  return query
    select b.id, b.kind, b.created_at, b.size_bytes
      from public.backups b
     order by b.created_at desc
     limit 200;
end;
$$;

create or replace function public.admin_get_backup(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  select data into v from public.backups where id = p_id;
  if v is null then
    raise exception 'backup not found';
  end if;
  return v;
end;
$$;

create or replace function public.admin_export_backup()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  return public._build_backup();
end;
$$;

-- -------------------------------------------------------------------------
-- Restore (full replace of operational data). One transaction: any error
-- rolls everything back, including the delete step.
-- -------------------------------------------------------------------------
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

revoke all on function public.admin_backup_now()              from public, anon;
revoke all on function public.admin_list_backups()            from public, anon;
revoke all on function public.admin_get_backup(uuid)          from public, anon;
revoke all on function public.admin_export_backup()           from public, anon;
revoke all on function public.admin_restore_backup(jsonb)     from public, anon;

grant execute on function public.admin_backup_now()           to authenticated;
grant execute on function public.admin_list_backups()         to authenticated;
grant execute on function public.admin_get_backup(uuid)       to authenticated;
grant execute on function public.admin_export_backup()        to authenticated;
grant execute on function public.admin_restore_backup(jsonb)  to authenticated;

-- -------------------------------------------------------------------------
-- Hourly schedule. Needs the pg_cron extension; if it is not available the
-- migration still succeeds and prints a notice (enable it in Dashboard ->
-- Database -> Extensions, then run the select cron.schedule(...) line).
-- -------------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule(
    'eshary-hourly-backup',
    '0 * * * *',
    'select public.backup_hourly()'
  );
exception when others then
  raise notice 'pg_cron not scheduled: %', sqlerrm;
end;
$$;

commit;
