-- 0087_operations_integrity.sql
-- Phase 1 of docs/accounting-audit-and-plan.md: closes the holes the audit of
-- 2026-10-29 found in how operations and accounts are saved.
--
--  A) The reference number is given by the database at save time, under a
--     per-administrator lock, so two employees saving together can never get
--     the same number. The number the phone sends is ignored; the app reads
--     the saved one back (the WhatsApp message text itself does not change).
--     An active reference can no longer repeat (unique index).
--  B) A request id: pressing «حفظ» again after the network dropped returns the
--     operation already saved instead of saving (and debiting) it twice.
--  C) An entry's customer must belong to the same administrator.
--  D) An employee allowed to type a rate cannot type one more than 15 % away
--     from the administrator's last rate of that kind (rate_unusual).
--  E) Accounts: opened only through admin_open_account, which writes the
--     opening line (balance_adjustments, kind 'opening') and the opening cost
--     in the same transaction; a direct insert with a balance, a negative
--     balance, and deleting an account or a company that has a balance or a
--     history are refused.
--  F) The dinar treasury: the deposits/withdrawals and the end-of-day count
--     lock the treasury row; a save paid in dinars waits for a count in
--     progress, so a count can never count an operation twice.
--  G) owner_wipe_operations asks for the password, removes everything that
--     depends on the operations (costs, adjustments, the dinar treasury) and
--     moves each company's starting reference past the last number used, so
--     no number already sent to a partner company is ever given again.
--  H) The legacy record_pending_buy is closed; indexes for the daily lists,
--     the archive, the account statements and the reports.
--
-- Needs 0086. Safe to run more than once. Nothing is deleted from your data.

begin;

do $$
begin
  if to_regclass('public.lyd_treasury') is null then
    raise exception 'شغّل الترحيل 0086 أولًا (خزينة الدينار)، ثم هذا الملف. لم يتغير شيء.';
  end if;
  -- run again after 0089 it would bring back what 0089 fixed
  if to_regprocedure('public._next_reference_for(uuid, uuid)') is not null then
    raise exception 'هذا الملف (0087) طُبِّق سابقًا وصحّحه 0089. لا تشغّله مرة أخرى. لم يتغير شيء.';
  end if;
end $$;

-- =============================================================================
-- shared: the administrator's password, with the cancellations' lock
-- (5 wrong in 15 minutes). Returns null when right, else the error code.
-- =============================================================================
create or replace function _admin_password_error(p_admin uuid, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_fails integer;
  v_hash  text;
begin
  -- one check at a time per administrator, so parallel tries cannot beat the lock
  perform pg_advisory_xact_lock(hashtextextended('eshary.pw:' || p_admin::text, 0));
  select count(*) into v_fails
    from cancel_auth_failures
   where user_id = p_admin and created_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;
  select u.encrypted_password into v_hash from auth.users u where u.id = p_admin;
  if v_hash is null or v_hash = '' then
    return jsonb_build_object('ok', false, 'error', 'password_not_set');
  end if;
  if p_password is null or crypt(p_password, v_hash) <> v_hash then
    insert into cancel_auth_failures (user_id) values (p_admin);
    return jsonb_build_object(
      'ok', false, 'error', 'wrong_password', 'remaining', greatest(0, 4 - v_fails)
    );
  end if;
  delete from cancel_auth_failures where user_id = p_admin;
  return null;
end;
$$;
revoke all on function _admin_password_error(uuid, text) from public, anon, authenticated;

-- =============================================================================
-- A + B) request ids and unique references
-- =============================================================================
alter table transfers add column if not exists request_id uuid;
alter table currency_buys add column if not exists request_id uuid;
create unique index if not exists transfers_owner_request_uq
  on transfers (owner_id, request_id) where request_id is not null;
create unique index if not exists currency_buys_owner_request_uq
  on currency_buys (owner_id, request_id) where request_id is not null;

-- an active reference never repeats. If two active transfers already share a
-- number (possible before this file), the index waits: the lock below already
-- stops new repeats, and the list of repeats is shown so they can be fixed.
do $$
declare
  r record;
  v_dups integer := 0;
begin
  for r in
    select owner_id, reference, count(*) as n
      from transfers
     where cancelled_at is null
     group by owner_id, reference
    having count(*) > 1
  loop
    v_dups := v_dups + 1;
    raise notice 'رقم إشاري مكرر: % (% حوالات فعالة)', r.reference, r.n;
  end loop;
  if v_dups = 0 then
    execute 'create unique index if not exists transfers_owner_ref_active_uq
               on transfers (owner_id, reference) where cancelled_at is null';
  else
    raise notice 'لم يُنشأ قيد منع التكرار لوجود % رقم مكرر. أرسلها للمطور.', v_dups;
  end if;
end $$;

-- =============================================================================
-- D) the rate: an employee's typed rate stays near the administrator's
-- =============================================================================
create or replace function _operation_rate(p_kind text, p_rate numeric)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_last  numeric;
begin
  if p_rate is not null and p_rate <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  if p_rate is not null and (p_rate <= 1 or p_rate > 100) then
    raise exception 'rate_out_of_range' using errcode = 'P0001';
  end if;

  if current_employee_id() is not null then
    select rate into v_last
      from last_exchange_rates
     where owner_id = v_admin and kind = p_kind;
    if not employee_has_perm(
         case p_kind when 'sell' then 'rate_edit_sell' else 'rate_edit_buy' end
       ) then
      if v_last is null and p_rate is not null then
        raise exception 'rate_not_set' using errcode = 'P0001';
      end if;
      return v_last;
    end if;
    -- allowed to type it: not more than 15 % away from the administrator's
    if p_rate is not null and v_last is not null
       and abs(p_rate - v_last) > v_last * 0.15 then
      raise exception 'rate_unusual' using errcode = 'P0001',
        detail = format('last %s, typed %s', v_last, p_rate);
    end if;
    return round(p_rate, 4);
  end if;

  if p_rate is not null then
    insert into last_exchange_rates (owner_id, kind, rate, updated_at)
    values (v_admin, p_kind, p_rate, now())
    on conflict (owner_id, kind)
      do update set rate = excluded.rate, updated_at = excluded.updated_at;
  end if;
  return round(p_rate, 4);
end;
$$;

-- =============================================================================
-- A + B + F) the save functions
-- =============================================================================
drop function if exists record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text);
create or replace function record_transfer(
  p_company_id                    uuid,
  p_exchange_id                   uuid,
  p_beneficiary_name              text,
  p_beneficiary_account_company   text,
  p_beneficiary_code              text,
  p_amount                        numeric,
  p_reference                     text,
  p_rate                          numeric default null,
  p_lyd_method                    text default null,
  p_request_id                    uuid default null
)
returns transfers
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_rate        numeric;
  v_cost        numeric;
  v_ref         text;
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
  if p_lyd_method is not null and p_lyd_method not in ('cash', 'bank') then
    raise exception 'lyd_method_invalid' using errcode = 'P0001';
  end if;

  -- one transfer at a time per administrator: the reference is read and used
  -- inside this lock, so it can never be given twice
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || v_admin_id::text, 0));

  -- the same request again (the network dropped after it was saved)
  if p_request_id is not null then
    select * into v_inserted from transfers
     where owner_id = v_admin_id and request_id = p_request_id;
    if found then
      return v_inserted;
    end if;
  end if;

  p_amount := round(p_amount, 2);
  v_rate := _operation_rate('sell', p_rate);
  v_ref := next_reference(p_company_id);

  perform 1 from exchanges where id = p_exchange_id for update;
  select cost_rate into v_cost from account_costs where exchange_id = p_exchange_id;
  -- a dinar count in progress finishes first (it locks this row for update)
  if v_rate is not null then
    perform 1 from lyd_treasury where owner_id = v_admin_id for share;
  end if;

  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, archived_at, created_by_employee_id,
    rate, lyd_amount, lyd_method, request_id
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, v_ref, 'archived', now(), v_employee_id,
    v_rate, round(p_amount * v_rate, 2),
    case when v_rate is null then null else coalesce(p_lyd_method, 'cash') end,
    p_request_id
  )
  returning * into v_inserted;

  if v_cost is not null then
    insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                                 cost_before, cost_after)
    values (v_inserted.id, 'sell', v_admin_id, p_exchange_id, v_cost, v_cost);
  end if;

  update exchanges set balance = balance - p_amount where id = p_exchange_id;

  perform log_employee_activity('transfer_created', v_inserted.id, p_amount);
  return v_inserted;
end;
$$;
revoke all on function record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid) from public, anon;
grant execute on function record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid) to authenticated;

drop function if exists record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text);
create or replace function record_currency_buy(
  p_my_company_id uuid, p_exchange_id uuid, p_client_id uuid,
  p_client_from_account text, p_usd_amount numeric, p_rate numeric,
  p_lyd_amount numeric, p_reference text default '',
  p_lyd_method text default null,
  p_request_id uuid default null
)
returns currency_buys
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_rate        numeric;
  v_balance     numeric;
  v_id          uuid := gen_random_uuid();
  v_cost_before numeric;
  v_cost_after  numeric;
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
  if p_client_id is not null and not exists (
    select 1 from clients where id = p_client_id and owner_id = v_admin_id
  ) then
    raise exception 'client_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  if p_lyd_method is not null and p_lyd_method not in ('cash', 'bank') then
    raise exception 'lyd_method_invalid' using errcode = 'P0001';
  end if;

  p_usd_amount := round(p_usd_amount, 2);
  v_rate := _operation_rate(
    'buy',
    case when p_rate = 1 and p_lyd_amount is not null
              and abs(p_lyd_amount - p_usd_amount) < 0.01
         then null else p_rate end
  );

  select balance into v_balance from exchanges where id = p_exchange_id for update;

  -- the same request again: the account lock makes a retry wait for the first
  if p_request_id is not null then
    select * into v_inserted from currency_buys
     where owner_id = v_admin_id and request_id = p_request_id;
    if found then
      return v_inserted;
    end if;
  end if;

  if v_rate is not null then
    perform 1 from lyd_treasury where owner_id = v_admin_id for share;
  end if;

  select c.cost_before, c.cost_after into v_cost_before, v_cost_after
    from _apply_buy_cost(v_admin_id, p_exchange_id, v_balance, p_usd_amount,
                         v_rate, v_id) c;

  insert into currency_buys (
    id, owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id, lyd_method, request_id
  ) values (
    v_id, v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, round(p_usd_amount * v_rate, 2), 'archived', now(), p_reference,
    v_employee_id,
    case when v_rate is null then null else coalesce(p_lyd_method, 'cash') end,
    p_request_id
  )
  returning * into v_inserted;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;
revoke all on function record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid) from public, anon;
grant execute on function record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid) to authenticated;

-- =============================================================================
-- E) accounts
-- =============================================================================
alter table balance_adjustments add column if not exists kind text;
alter table balance_adjustments drop constraint if exists balance_adjustments_kind_check;
alter table balance_adjustments add constraint balance_adjustments_kind_check
  check (kind is null or kind in ('adjust', 'opening'));

-- a balance moves only inside the database's own functions; never below zero
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
     and coalesce(current_setting('eshary.restoring', true), '') <> 'on' then
    raise exception 'insufficient_balance' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_block_direct_balance_edit on exchanges;
create trigger trg_block_direct_balance_edit
  before insert or update of balance on exchanges
  for each row execute function _block_direct_balance_edit();

-- an account (or a company) with a balance or any history stays. Not security
-- definer on purpose: current_user must stay the caller's role (inside the
-- platform's own definer functions it is the owner, and they pass).
create or replace function _block_account_delete()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return old; -- the platform's own maintenance (restore, closing an owner)
  end if;
  if tg_table_name = 'companies' then
    if exists (
      select 1 from exchanges e
       where e.company_id = old.id
         and (e.balance <> 0
              or exists (select 1 from account_expenses x where x.exchange_id = e.id)
              or exists (select 1 from balance_adjustments a where a.exchange_id = e.id))
    ) then
      raise exception 'account_has_history' using errcode = 'P0001';
    end if;
    return old;
  end if;
  if old.balance <> 0
     or exists (select 1 from account_expenses x where x.exchange_id = old.id)
     or exists (select 1 from balance_adjustments a where a.exchange_id = old.id) then
    raise exception 'account_has_history' using errcode = 'P0001';
  end if;
  return old;
end;
$$;
drop trigger if exists trg_block_account_delete on exchanges;
create trigger trg_block_account_delete
  before delete on exchanges
  for each row execute function _block_account_delete();
drop trigger if exists trg_block_account_delete on companies;
create trigger trg_block_account_delete
  before delete on companies
  for each row execute function _block_account_delete();

-- opening an account: the balance, its opening line and its cost together
create or replace function admin_open_account(
  p_company_id uuid,
  p_name       text,
  p_balance    numeric,
  p_our_code   text default null,
  p_country    text default null,
  p_cost_rate  numeric default null
)
returns exchanges
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin   uuid := auth.uid();
  v_balance numeric := round(coalesce(p_balance, 0), 2);
  v_row     exchanges;
  v_name    text;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if not exists (select 1 from companies where id = p_company_id and owner_id = v_admin) then
    raise exception 'company_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'account_name_required' using errcode = 'P0001';
  end if;
  if v_balance < 0 or v_balance > 999999999999.99 then
    raise exception 'adjust_amount_invalid' using errcode = 'P0001';
  end if;
  -- dollars with no dinar cost would stay out of the profit: a cost is required
  if v_balance > 0 and p_cost_rate is null then
    raise exception 'opening_cost_required' using errcode = 'P0001';
  end if;

  insert into exchanges (company_id, name, balance, our_code, country)
  values (p_company_id, btrim(p_name), v_balance,
          nullif(btrim(coalesce(p_our_code, '')), ''),
          nullif(btrim(coalesce(p_country, '')), ''))
  returning * into v_row;

  if v_balance > 0 then
    select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                    nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                    u.email, 'المدير')
      into v_name from auth.users u where u.id = v_admin;
    insert into balance_adjustments (
      owner_id, exchange_id, balance_before, balance_after, delta, reason,
      adjusted_by_name, kind
    ) values (
      v_admin, v_row.id, 0, v_balance, v_balance, 'رصيد افتتاحي', v_name, 'opening'
    );
  end if;
  if p_cost_rate is not null then
    perform set_account_cost(v_row.id, p_cost_rate);
  end if;
  return v_row;
end;
$$;
revoke all on function admin_open_account(uuid, text, numeric, text, text, numeric) from public, anon;
grant execute on function admin_open_account(uuid, text, numeric, text, text, numeric) to authenticated;

-- =============================================================================
-- F) the dinar treasury: movements and counts lock the treasury row
-- =============================================================================
create or replace function lyd_add_movement(
  p_kind text, p_pocket text, p_amount numeric, p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := _lyd_admin();
  v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_pos    record;
  v_from   numeric;
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_kind not in ('in', 'out', 'cash_to_bank', 'bank_to_cash') then
    raise exception 'lyd_kind_invalid' using errcode = 'P0001';
  end if;
  if p_kind in ('in', 'out') and (p_pocket is null or p_pocket not in ('cash', 'bank')) then
    raise exception 'lyd_kind_invalid' using errcode = 'P0001';
  end if;
  if v_amount <= 0 or v_amount > 999999999999.99 then
    raise exception 'lyd_amount_invalid' using errcode = 'P0001';
  end if;
  perform 1 from lyd_treasury where owner_id = v_admin for update;
  if not found then
    raise exception 'lyd_not_open' using errcode = 'P0001';
  end if;
  -- nothing leaves a pocket that does not hold it
  if p_kind in ('out', 'cash_to_bank', 'bank_to_cash') then
    select * into v_pos from _lyd_position(v_admin);
    v_from := case
      when p_kind = 'cash_to_bank' then v_pos.cash
      when p_kind = 'bank_to_cash' then v_pos.bank
      when p_pocket = 'cash' then v_pos.cash
      else v_pos.bank end;
    if v_amount > v_from then
      raise exception 'lyd_insufficient' using errcode = 'P0001',
        detail = format('available %s, amount %s', v_from, v_amount);
    end if;
  end if;
  insert into lyd_movements (owner_id, kind, pocket, amount, note)
  values (v_admin, p_kind,
          case when p_kind in ('in', 'out') then p_pocket end,
          v_amount, nullif(btrim(coalesce(p_note, '')), ''));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function lyd_record_count(
  p_counted numeric, p_note text default null, p_post boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin    uuid := _lyd_admin();
  v_counted  numeric := round(coalesce(p_counted, -1), 2);
  v_expected numeric;
  v_diff     numeric;
  v_id       uuid;
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if v_counted < 0 or v_counted > 999999999999.99 then
    raise exception 'lyd_amount_invalid' using errcode = 'P0001';
  end if;
  -- saves paid in dinars wait for the count; the count sees every finished one
  perform 1 from lyd_treasury where owner_id = v_admin for update;
  if not found then
    raise exception 'lyd_not_open' using errcode = 'P0001';
  end if;
  select cash into v_expected from _lyd_position(v_admin);
  v_diff := v_counted - v_expected;
  insert into lyd_counts (owner_id, expected, counted, difference, posted, note)
  values (v_admin, v_expected, v_counted, v_diff, coalesce(p_post, true) and v_diff <> 0,
          nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;
  if coalesce(p_post, true) and v_diff <> 0 then
    insert into lyd_movements (owner_id, kind, amount, note, count_id)
    values (v_admin, case when v_diff > 0 then 'count_over' else 'count_short' end,
            abs(v_diff), nullif(btrim(coalesce(p_note, '')), ''), v_id);
  end if;
  return jsonb_build_object('ok', true, 'expected', v_expected,
                            'counted', v_counted, 'difference', v_diff);
end;
$$;

-- =============================================================================
-- G) wiping the operations: with the password, and complete
-- =============================================================================
drop function if exists owner_wipe_operations();
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

  -- no two wipes or saves of this administrator at the same moment
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || v_owner::text, 0));

  -- the numbering goes on after the last number used: every company starts
  -- again from the number it would have given next
  for r in select id from companies where owner_id = v_owner loop
    update companies set start_ref = next_reference(r.id) where id = r.id;
  end loop;

  -- A way back: a full snapshot before anything is deleted.
  v_backup := public._save_backup('pre_wipe');

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

-- =============================================================================
-- H) the legacy pending buy is closed; indexes
-- =============================================================================
do $$
begin
  if to_regprocedure('public.record_pending_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text)') is not null then
    execute 'revoke execute on function record_pending_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text) from public, anon, authenticated';
  end if;
end $$;

create index if not exists transfers_owner_created_idx
  on transfers (owner_id, created_at desc);
create index if not exists transfers_owner_archived_idx
  on transfers (owner_id, archived_at, id) where status = 'archived';
create index if not exists transfers_exchange_created_idx
  on transfers (exchange_id, created_at);
create index if not exists transfers_company_idx on transfers (company_id);
create index if not exists transfers_emp_created_idx
  on transfers (created_by_employee_id, created_at desc)
  where created_by_employee_id is not null;
create index if not exists currency_buys_owner_created_idx
  on currency_buys (owner_id, created_at desc);
create index if not exists currency_buys_owner_archived_idx
  on currency_buys (owner_id, archived_at, id) where status = 'archived';
create index if not exists currency_buys_exchange_created_idx
  on currency_buys (exchange_id, created_at);
create index if not exists currency_buys_my_company_idx on currency_buys (my_company_id);
create index if not exists currency_buys_client_idx on currency_buys (client_id);
create index if not exists currency_buys_emp_created_idx
  on currency_buys (created_by_employee_id, created_at desc)
  where created_by_employee_id is not null;
create index if not exists operation_costs_exchange_idx on operation_costs (exchange_id);
create index if not exists account_expenses_exchange_idx on account_expenses (exchange_id);

commit;
