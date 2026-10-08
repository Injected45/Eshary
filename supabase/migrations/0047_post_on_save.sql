-- 0047_post_on_save.sql
-- No more manual daily close. An exit or an entry is posted the moment it is
-- saved: the row is stored as 'archived' (closed, posted) and the account
-- balance moves in the same transaction.
--
--   exit   (record_transfer)       balance = balance - amount
--   entry  (record_currency_buy)   balance = balance + usd_amount
--
-- Consequences
--   * exchanges.balance is always the real balance; nothing is "open" or
--     "waiting for the close" any more, so an employee and the admin always
--     see the same figure.
--   * An exit above the balance is refused (trigger from 0046, now applied to
--     the posted rows too; it locks the account row so two exits cannot both
--     pass).
--   * The permissions archive_transfers / archive_buys / archive_all are
--     retired. They are dropped silently when an employee's permissions are
--     saved; old values still stored are ignored.
--   * An employee who may execute exits / entries can read their own rows of
--     the last two days (the app shows today's); before, the policy only let
--     them read rows still 'daily'.
--   * One time: the rows still 'daily' right now are posted (balances move by
--     their total), exactly what the old close did. 'pending' entries are left
--     as they are.
--
-- The old archive_daily_* functions stay (an older app build may still call
-- them); with nothing left 'daily' they do nothing.

begin;

-- -------------------------------------------------------------------------
-- 1) Post what is open today (the old close, once)
-- -------------------------------------------------------------------------
with s as (
  select exchange_id, sum(amount) as a
    from transfers where status = 'daily' group by exchange_id
)
update exchanges e set balance = e.balance - s.a
  from s where e.id = s.exchange_id;

update transfers set status = 'archived', archived_at = now()
 where status = 'daily';

with b as (
  select exchange_id, sum(usd_amount) as a
    from currency_buys where status = 'daily' group by exchange_id
)
update exchanges e set balance = e.balance + b.a
  from b where e.id = b.exchange_id;

update currency_buys set status = 'archived', archived_at = now()
 where status = 'daily';

-- -------------------------------------------------------------------------
-- 2) Refuse an exit above the balance for posted rows too
-- -------------------------------------------------------------------------
drop trigger if exists trg_check_transfer_balance on transfers;
create trigger trg_check_transfer_balance
  before insert on transfers
  for each row
  when (new.status in ('daily', 'archived'))
  execute function _check_transfer_balance();

-- -------------------------------------------------------------------------
-- 3) Save = post
-- -------------------------------------------------------------------------
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
  v_inserted    transfers;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_employee_id is not null and not employee_has_perm('transfers_create') then
    raise exception 'permission_denied' using errcode = 'P0001';
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

  -- The trigger checks the balance (and locks the account) before the insert.
  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, archived_at, created_by_employee_id
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'archived', now(), v_employee_id
  )
  returning * into v_inserted;

  update exchanges set balance = balance - p_amount where id = p_exchange_id;

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
  v_inserted    currency_buys;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_employee_id is not null and not employee_has_perm('buys_create') then
    raise exception 'permission_denied' using errcode = 'P0001';
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
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id
  ) values (
    v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, p_rate, p_lyd_amount, 'archived', now(), p_reference,
    v_employee_id
  )
  returning * into v_inserted;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

-- -------------------------------------------------------------------------
-- 4) Permissions: the three close permissions are retired
-- -------------------------------------------------------------------------
create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all']
$$;

create or replace function admin_set_employee_permissions(
  p_sub_user_id uuid,
  p_permissions text[]
) returns text[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_perms text[];
begin
  -- Retired keys sent by an older screen are ignored, not an error.
  select coalesce(array_agg(distinct k order by k), '{}')
    into v_perms
    from unnest(coalesce(p_permissions, '{}')) as k
   where k not in ('archive_transfers', 'archive_buys', 'archive_all');

  if exists (select 1 from unnest(v_perms) k where k <> all (_employee_permission_keys())) then
    raise exception 'invalid_permission' using errcode = 'P0001';
  end if;

  update sub_users s
     set permissions = v_perms,
         updated_at  = now()
   where s.id = p_sub_user_id
     and s.parent_admin_id = auth.uid();
  if not found then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  insert into employee_activity_logs (parent_admin_id, sub_user_id, event_type)
  values (auth.uid(), p_sub_user_id, 'permissions_changed');

  return v_perms;
end;
$$;
revoke all on function admin_set_employee_permissions(uuid, text[]) from public, anon;
grant execute on function admin_set_employee_permissions(uuid, text[]) to authenticated;

-- -------------------------------------------------------------------------
-- 5) Reading: an employee who executes sees their own rows of the last 2 days
-- -------------------------------------------------------------------------
drop policy if exists emp_perm_gate on transfers;
create policy emp_perm_gate on transfers
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or (select employee_has_perm('view_all'))
    or ((select employee_has_perm('closings_all')) and status = 'archived')
    or (
      created_by_employee_id = (select current_employee_id())
      and (
        (select employee_has_perm('view_own'))
        or (select employee_has_perm('accounts_own'))
        or ((select employee_has_perm('closings_own')) and status = 'archived')
        or (
          (select employee_has_perm('transfers_create'))
          and (status = 'daily' or created_at >= now() - interval '2 days')
        )
      )
    )
  );

drop policy if exists emp_perm_gate on currency_buys;
create policy emp_perm_gate on currency_buys
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or (select employee_has_perm('view_all'))
    or ((select employee_has_perm('closings_all')) and status = 'archived')
    or (
      created_by_employee_id = (select current_employee_id())
      and (
        (select employee_has_perm('view_own'))
        or (select employee_has_perm('accounts_own'))
        or ((select employee_has_perm('closings_own')) and status = 'archived')
        or (
          (select employee_has_perm('buys_create'))
          and (status in ('daily', 'pending')
               or created_at >= now() - interval '2 days')
        )
      )
    )
  );

commit;
