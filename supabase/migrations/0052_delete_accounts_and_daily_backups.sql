-- 0052_delete_accounts_and_daily_backups.sql
-- Two administrator tools.
--
-- A) admin_delete_user(user_id): delete an account that applied (a sign-up that
--    will never be activated, a test account). Safe by construction:
--      * platform admins only; never yourself, never another admin;
--      * refused when the account already has financial operations (exits or
--        entries) -- those are records that must not disappear; block it instead;
--      * what is removed with it: its sign-in, licence, phone, setup data
--        (companies, accounts, clients, employees) -- everything that hangs on
--        the sign-in;
--      * written to `deleted_accounts` first (e-mail, phone, who deleted, when,
--        how much setup data went) so a deletion can always be traced.
--
-- B) Backups: one automatic snapshot every 24 hours (00:00 Libya time) instead
--    of every hour, kept for 30 days; and admin_delete_backups(ids) so old
--    snapshots can be removed to free space. At least one snapshot always stays.
--    Existing hourly snapshots stay until deleted or 30 days old.

begin;

-- -------------------------------------------------------------------------
-- A) Delete an account
-- -------------------------------------------------------------------------
create table if not exists deleted_accounts (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null,
  email            text,
  phone            text,
  license_status   text,
  account_created  timestamptz,
  companies        integer not null default 0,
  clients          integer not null default 0,
  employees        integer not null default 0,
  deleted_by       uuid not null,
  deleted_by_email text,
  deleted_at       timestamptz not null default now()
);
create index if not exists deleted_accounts_recent_idx
  on deleted_accounts (deleted_at desc);
alter table deleted_accounts enable row level security;
revoke all on deleted_accounts from anon, authenticated;

create or replace function admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin   uuid := auth.uid();
  v_email   text;
  v_created timestamptz;
  v_phone   text;
  v_status  text;
  v_ops     integer;
  v_co      integer;
  v_cl      integer;
  v_emp     integer;
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  if p_user_id is null or p_user_id = v_admin then
    raise exception 'cannot_delete_self' using errcode = 'P0001';
  end if;

  select u.email, u.created_at into v_email, v_created
    from auth.users u where u.id = p_user_id;
  if not found then
    raise exception 'user_not_found' using errcode = 'P0001';
  end if;

  if coalesce((select l.is_admin from account_licenses l where l.user_id = p_user_id), false) then
    raise exception 'cannot_delete_admin' using errcode = 'P0001';
  end if;

  select (select count(*) from transfers where owner_id = p_user_id)
       + (select count(*) from currency_buys where owner_id = p_user_id)
    into v_ops;
  if v_ops > 0 then
    raise exception 'user_has_operations' using errcode = 'P0001',
      detail = format('%s operations', v_ops);
  end if;

  select mp.phone into v_phone from member_phones mp where mp.user_id = p_user_id;
  select l.status into v_status from account_licenses l where l.user_id = p_user_id;
  select count(*) into v_co  from companies where owner_id = p_user_id;
  select count(*) into v_cl  from clients where owner_id = p_user_id;
  select count(*) into v_emp from sub_users where parent_admin_id = p_user_id;

  insert into deleted_accounts (
    user_id, email, phone, license_status, account_created,
    companies, clients, employees, deleted_by, deleted_by_email
  ) values (
    p_user_id, v_email, v_phone, coalesce(v_status, 'pending'), v_created,
    v_co, v_cl, v_emp, v_admin, (select u.email from auth.users u where u.id = v_admin)
  );

  -- A former admin may have activated others: that reference has no cascade.
  update account_licenses set activated_by = null where activated_by = p_user_id;
  delete from member_otps where email = lower(v_email);

  delete from auth.users where id = p_user_id;

  return jsonb_build_object('ok', true, 'email', v_email, 'phone', v_phone);
end;
$$;
revoke all on function admin_delete_user(uuid) from public, anon;
grant execute on function admin_delete_user(uuid) to authenticated;

-- -------------------------------------------------------------------------
-- B) Backups: daily, kept 30 days, deletable
-- -------------------------------------------------------------------------
create or replace function public.backup_daily()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._save_backup('auto');

  -- automatic snapshots older than 30 days
  delete from public.backups
   where kind = 'auto'
     and created_at < now() - interval '30 days'
     and id not in (
       select id from public.backups order by created_at desc limit 1
     );

  -- manual / pre-restore snapshots: the newest 20
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
revoke all on function public.backup_daily() from public, anon, authenticated;

-- A job still pointing at the old name keeps working (and now only keeps the
-- 30-day rule).
create or replace function public.backup_hourly()
returns void
language sql
security definer
set search_path = public
as $$ select public.backup_daily() $$;
revoke all on function public.backup_hourly() from public, anon, authenticated;

create or replace function public.admin_delete_backups(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
  v_gone  integer;
  v_n     integer;
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then
    return 0;
  end if;

  select count(*) into v_total from public.backups;
  select count(*) into v_gone from public.backups where id = any (p_ids);
  -- Never delete the last snapshot.
  if v_gone >= v_total then
    raise exception 'keep_one_backup' using errcode = 'P0001';
  end if;

  delete from public.backups where id = any (p_ids);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.admin_delete_backups(uuid[]) from public, anon;
grant execute on function public.admin_delete_backups(uuid[]) to authenticated;

-- Schedule: every day at 22:00 UTC = 00:00 in Libya. Replaces the hourly job.
-- Needs pg_cron; without it the migration still succeeds and prints a notice.
do $$
begin
  create extension if not exists pg_cron;
  begin
    perform cron.unschedule('eshary-hourly-backup');
  exception when others then
    null; -- it was never scheduled
  end;
  perform cron.schedule(
    'eshary-daily-backup',
    '0 22 * * *',
    'select public.backup_daily()'
  );
exception when others then
  raise notice 'pg_cron not scheduled: %', sqlerrm;
end;
$$;

commit;
