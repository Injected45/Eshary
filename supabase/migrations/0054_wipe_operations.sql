-- 0054_wipe_operations.sql
-- "حذف المدخلات" (Settings) deletes ALL the account's financial operations.
--
-- Since 0048 the API no longer accepts a direct delete on `transfers` /
-- `currency_buys`, so the old screen (which deleted them row by row) failed
-- with "حُذفت جزئيًا. أخطاء: 2". The deletion now goes through one function:
--
--   owner_wipe_operations()
--     * the shop owner only (an employee can never call it);
--     * first saves a full backup of kind 'pre_wipe', so a wipe can be undone
--       from the backups screen;
--     * deletes every exit and entry, their cancellations and cancellation
--       requests, and the alerts about them;
--     * puts every account balance back to 0 (as before);
--     * writes one row to `wiped_operations` (who, when, how many) -- readable
--       only from SQL, never editable.
-- Everything happens in one transaction: all of it or nothing.

begin;

alter table backups drop constraint if exists backups_kind_check;
alter table backups add constraint backups_kind_check
  check (kind in ('auto', 'manual', 'pre_restore', 'pre_wipe'));

create table if not exists wiped_operations (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null,
  owner_email   text,
  transfers     integer not null default 0,
  currency_buys integer not null default 0,
  cancellations integer not null default 0,
  balances_reset integer not null default 0,
  backup_id     uuid,
  wiped_at      timestamptz not null default now()
);
alter table wiped_operations enable row level security;
revoke all on wiped_operations from anon, authenticated;

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
revoke all on function owner_wipe_operations() from public, anon;
grant execute on function owner_wipe_operations() to authenticated;

-- The daily job keeps the newest 20 manual / safety snapshots, pre_wipe included.
create or replace function public.backup_daily()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._save_backup('auto');

  delete from public.backups
   where kind = 'auto'
     and created_at < now() - interval '30 days'
     and id not in (
       select id from public.backups order by created_at desc limit 1
     );

  delete from public.backups
   where kind in ('manual', 'pre_restore', 'pre_wipe')
     and id not in (
       select id from public.backups
        where kind in ('manual', 'pre_restore', 'pre_wipe')
        order by created_at desc
        limit 20
     );
end;
$$;
revoke all on function public.backup_daily() from public, anon, authenticated;

commit;
