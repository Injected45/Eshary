-- 0082_account_cost.sql
-- The cost price of the dollar, per account (weighted average cost).
--
--   Each account (exchanges row) has its own cost: dinars paid per dollar held.
--   * opening   the administrator types the cost of the dollars the account
--               holds now (its balance at that moment);
--   * entry     with a rate r for q dollars, on balance B at cost C:
--                 C' = (B × C + q × r) ÷ (B + q)
--               (B = 0: C' = r, the account starts again);
--   * exit, commission, a balance edited by hand, an entry from an older build
--               without a rate: the dollars go out / come in AT COST, so the
--               cost does not change;
--   * cancelling an entry: its value leaves at its own price:
--                 C' = ((B' + q) × C − q × r) ÷ B'    (B' = balance after it)
--   The cost is kept to 6 decimals and computed here, in the same transaction
--   as the save, with the account row locked.
--
-- Every change of a cost is kept in account_cost_events (append-only). Each
-- entry stores the cost before/after it, each exit the cost at that moment
-- (for a profit report later; nothing shows it yet).
-- Only the administrator sees the costs (treasury_positions) and sets them.
-- Needs 0081. Safe to run more than once.

begin;

-- superseded-guard: a later migration redefined what this file defines; running
-- it again would undo that, so it refuses.
do $$
begin
  if to_regclass('public.operation_costs') is not null then
    raise exception 'هذا الملف (0082) طُبّق سابقًا وجاءت بعده ترحيلات أحدث، وإعادة تشغيله تلغي إصلاحاتها. لم يتغير شيء.';
  end if;
end $$;

-- 0) refuse to run before 0081: the save functions below write its columns, and
--    without them every exit and entry would fail.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'transfers'
       and column_name = 'rate'
  ) or to_regprocedure('public._operation_rate(text, numeric)') is null then
    raise exception 'شغّل الترحيل 0081 أولًا (سعر الصرف)، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- 1) storage --------------------------------------------------------------------
create table if not exists account_costs (
  exchange_id uuid primary key references exchanges (id) on delete cascade,
  owner_id    uuid not null references profiles (id) on delete cascade,
  cost_rate   numeric(16,6) not null check (cost_rate > 0),
  updated_at  timestamptz not null default now()
);
alter table account_costs enable row level security;
revoke all on table account_costs from anon, authenticated;

create table if not exists account_cost_events (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references profiles (id) on delete cascade,
  exchange_id    uuid not null references exchanges (id) on delete cascade,
  kind           text not null
                 check (kind in ('opening', 'correction', 'buy', 'buy_cancel')),
  operation_id   uuid,
  balance_before numeric(14,2) not null,
  cost_before    numeric(16,6),
  usd_amount     numeric(14,2),
  rate           numeric(10,4),
  balance_after  numeric(14,2) not null,
  cost_after     numeric(16,6) not null,
  created_at     timestamptz not null default now()
);
create index if not exists account_cost_events_exchange_idx
  on account_cost_events (exchange_id, created_at);
alter table account_cost_events enable row level security;
revoke all on table account_cost_events from anon, authenticated;

alter table currency_buys
  add column if not exists cost_before numeric(16,6),
  add column if not exists cost_after  numeric(16,6);
alter table transfers
  add column if not exists cost_rate numeric(16,6);

-- 2) an entry moves the cost -------------------------------------------------------
-- p_balance_before: the account's balance before this entry, read with the row
-- locked by the caller. p_rate null = no rate (older build): at cost.
create or replace function _apply_buy_cost(
  p_owner          uuid,
  p_exchange_id    uuid,
  p_balance_before numeric,
  p_usd            numeric,
  p_rate           numeric,
  p_operation_id   uuid,
  out cost_before  numeric,
  out cost_after   numeric
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_q numeric := round(p_usd, 2);
begin
  select c.cost_rate into cost_before
    from account_costs c
   where c.exchange_id = p_exchange_id
     for update;

  if p_rate is null then
    cost_after := cost_before;            -- in at cost
    return;
  end if;
  if p_balance_before <= 0 then
    cost_after := round(p_rate, 6);       -- an empty account starts again
  elsif cost_before is null then
    cost_after := null;                   -- no opening cost yet: not tracked
    return;
  else
    cost_after := round(
      (p_balance_before * cost_before + v_q * p_rate) / (p_balance_before + v_q),
      6
    );
  end if;

  insert into account_costs (exchange_id, owner_id, cost_rate, updated_at)
  values (p_exchange_id, p_owner, cost_after, now())
  on conflict (exchange_id)
    do update set cost_rate = excluded.cost_rate, updated_at = excluded.updated_at;

  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after
  ) values (
    p_owner, p_exchange_id, 'buy', p_operation_id, p_balance_before, cost_before,
    v_q, p_rate, p_balance_before + v_q, cost_after
  );
end;
$$;
revoke all on function _apply_buy_cost(uuid, uuid, numeric, numeric, numeric, uuid)
  from public, anon, authenticated;

-- 3) cancelling an entry takes its value out at its own price -----------------------
-- admin_cancel_operation (0048) moves the balance back BEFORE it stamps
-- cancelled_at, so here the account's balance is already the one after it.
create or replace function _cost_on_buy_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_bal   numeric;
  v_cost  numeric;
  v_q     numeric := round(new.usd_amount, 2);
  v_value numeric;
  v_new   numeric;
begin
  if new.rate is null then
    return new;                           -- it came in at cost
  end if;
  select balance into v_bal from exchanges where id = new.exchange_id;
  select cost_rate into v_cost from account_costs
   where exchange_id = new.exchange_id for update;
  if v_cost is null then
    return new;                           -- this account is not tracked
  end if;

  v_value := (v_bal + v_q) * v_cost - v_q * new.rate;
  if v_bal <= 0 or v_value <= 0 then
    v_new := v_cost;                      -- nothing left to average
  else
    v_new := round(v_value / v_bal, 6);
  end if;

  update account_costs set cost_rate = v_new, updated_at = now()
   where exchange_id = new.exchange_id;
  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after
  ) values (
    new.owner_id, new.exchange_id, 'buy_cancel', new.id, v_bal + v_q, v_cost,
    v_q, new.rate, v_bal, v_new
  );
  return new;
end;
$$;

drop trigger if exists trg_cost_on_buy_cancel on currency_buys;
create trigger trg_cost_on_buy_cancel
  after update of cancelled_at on currency_buys
  for each row
  when (old.cancelled_at is null and new.cancelled_at is not null)
  execute function _cost_on_buy_cancel();

-- 4) the administrator: opening cost / correction, and the treasury ------------------
create or replace function set_account_cost(p_exchange_id uuid, p_rate numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_bal   numeric;
  v_old   numeric;
  v_new   numeric := round(p_rate, 6);
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_rate is null or p_rate <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  select e.balance into v_bal
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select cost_rate into v_old from account_costs
   where exchange_id = p_exchange_id for update;

  insert into account_costs (exchange_id, owner_id, cost_rate, updated_at)
  values (p_exchange_id, v_admin, v_new, now())
  on conflict (exchange_id)
    do update set cost_rate = excluded.cost_rate, updated_at = excluded.updated_at;
  insert into account_cost_events (
    owner_id, exchange_id, kind, balance_before, cost_before,
    balance_after, cost_after
  ) values (
    v_admin, p_exchange_id,
    case when v_old is null then 'opening' else 'correction' end,
    v_bal, v_old, v_bal, v_new
  );
  return jsonb_build_object('ok', true, 'balance', v_bal, 'cost_rate', v_new);
end;
$$;
revoke all on function set_account_cost(uuid, numeric) from public, anon;
grant execute on function set_account_cost(uuid, numeric) to authenticated;

create or replace function treasury_positions()
returns table (
  exchange_id     uuid,
  company_name    text,
  account_name    text,
  balance         numeric,
  cost_rate       numeric,
  book_value      numeric,
  cost_updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  return query
    select e.id, c.name, e.name, e.balance, k.cost_rate,
           case when k.cost_rate is null then null
                else round(e.balance * k.cost_rate, 2) end,
           k.updated_at
      from exchanges e
      join companies c on c.id = e.company_id
      left join account_costs k on k.exchange_id = e.id
     where c.owner_id = auth.uid()
     order by c.name, e.name;
end;
$$;
revoke all on function treasury_positions() from public, anon;
grant execute on function treasury_positions() to authenticated;

-- 5) the save functions (as 0081, plus the cost) ------------------------------------
create or replace function record_transfer(
  p_company_id                    uuid,
  p_exchange_id                   uuid,
  p_beneficiary_name              text,
  p_beneficiary_account_company   text,
  p_beneficiary_code              text,
  p_amount                        numeric,
  p_reference                     text,
  p_rate                          numeric default null
)
returns transfers
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_rate        numeric;
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

  v_rate := _operation_rate('sell', p_rate);

  -- The trigger checks the balance (and locks the account) before the insert.
  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, archived_at, created_by_employee_id,
    rate, lyd_amount, cost_rate
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'archived', now(), v_employee_id,
    v_rate, round(round(p_amount, 2) * v_rate, 2),
    (select cost_rate from account_costs where exchange_id = p_exchange_id)
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

  v_rate := _operation_rate(
    'buy',
    case when p_rate = 1 and p_lyd_amount = p_usd_amount then null else p_rate end
  );

  -- the account, locked: its balance before this entry averages the cost
  select balance into v_balance from exchanges where id = p_exchange_id for update;
  select c.cost_before, c.cost_after into v_cost_before, v_cost_after
    from _apply_buy_cost(v_admin_id, p_exchange_id, v_balance, p_usd_amount,
                         v_rate, v_id) c;

  insert into currency_buys (
    id, owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id, cost_before, cost_after
  ) values (
    v_id, v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, round(round(p_usd_amount, 2) * v_rate, 2), 'archived', now(), p_reference,
    v_employee_id, v_cost_before, v_cost_after
  )
  returning * into v_inserted;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

commit;
