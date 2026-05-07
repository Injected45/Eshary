-- 0017_defer_balance_update.sql
-- Moves exchanges.balance updates from per-row inserts to batched application
-- at archive time. Per-row insert RPCs no longer touch the balance; the two
-- archive_* functions sum the daily rows per exchange and apply the delta
-- inside the same transaction that flips status to 'archived'.
--
-- One-time corrective at the top: existing status='daily' rows already
-- affected the balance under the previous logic. We revert that effect now
-- so the new archive_* call can re-apply it correctly. Pending rows never
-- touched the balance, so they are not corrected.

begin;

-- =========================================================================
-- ONE-TIME CORRECTIVE: revert the prior per-row balance effect of every
-- status='daily' row currently in the system. After this block the balance
-- of each exchange equals what it was just before the first un-archived
-- daily row was inserted. The new archive_* functions will re-apply the
-- aggregate delta when the user runs the next close.
-- =========================================================================

with t_sums as (
  select exchange_id, sum(amount) as s
    from transfers
   where status = 'daily'
   group by exchange_id
)
update exchanges e
   set balance = e.balance + t_sums.s
  from t_sums
 where e.id = t_sums.exchange_id;

with b_sums as (
  select exchange_id, sum(usd_amount) as s
    from currency_buys
   where status = 'daily'
   group by exchange_id
)
update exchanges e
   set balance = e.balance - b_sums.s
  from b_sums
 where e.id = b_sums.exchange_id;

-- =========================================================================
-- record_transfer — insert only, no balance change.
-- Same signature as 0004; only the body changes.
-- =========================================================================

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
language plpgsql
security invoker
as $$
declare
  v_uid      uuid := auth.uid();
  v_owner    uuid;
  v_inserted transfers;
begin
  if v_uid is null then
    raise exception 'not authorized: no auth.uid()';
  end if;

  select owner_id into v_owner from companies where id = p_company_id;
  if v_owner is null or v_owner <> v_uid then
    raise exception 'company not found or not owned by caller';
  end if;

  if not exists (
    select 1 from exchanges
     where id = p_exchange_id
       and company_id = p_company_id
  ) then
    raise exception 'exchange does not belong to company';
  end if;

  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status
  ) values (
    v_uid, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'daily'
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

-- =========================================================================
-- record_currency_buy — insert only, no balance change.
-- Preserves p_reference parameter added in 0012.
-- =========================================================================

create or replace function record_currency_buy(
  p_my_company_id        uuid,
  p_exchange_id          uuid,
  p_client_id            uuid,
  p_client_from_account  text,
  p_usd_amount           numeric,
  p_rate                 numeric,
  p_lyd_amount           numeric,
  p_reference            text default ''
)
returns currency_buys
language plpgsql
security invoker
as $$
declare
  v_uid      uuid := auth.uid();
  v_owner    uuid;
  v_inserted currency_buys;
begin
  if v_uid is null then
    raise exception 'not authorized: no auth.uid()';
  end if;

  select owner_id into v_owner from companies where id = p_my_company_id;
  if v_owner is null or v_owner <> v_uid then
    raise exception 'company not found or not owned by caller';
  end if;

  if not exists (
    select 1 from exchanges
     where id = p_exchange_id
       and company_id = p_my_company_id
  ) then
    raise exception 'exchange does not belong to company';
  end if;

  insert into currency_buys (
    owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, reference
  ) values (
    v_uid, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, p_rate, p_lyd_amount, 'daily', p_reference
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

-- =========================================================================
-- archive_daily_transfers — sum daily transfer amounts per exchange,
-- decrement balances, then flip status. Single transaction.
-- =========================================================================

create or replace function archive_daily_transfers(p_owner uuid)
returns integer
language plpgsql
security invoker
as $$
declare
  v_count integer;
begin
  if p_owner is null or p_owner <> auth.uid() then
    raise exception 'not authorized: p_owner must equal auth.uid()';
  end if;

  with sums as (
    select exchange_id, sum(amount) as s
      from transfers
     where owner_id = p_owner
       and status   = 'daily'
     group by exchange_id
  )
  update exchanges e
     set balance = e.balance - sums.s
    from sums
   where e.id = sums.exchange_id;

  update transfers
     set status      = 'archived',
         archived_at = now()
   where owner_id = p_owner
     and status   = 'daily';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- =========================================================================
-- archive_daily_buys — pending block preserved. Sum daily buy usd_amounts
-- per exchange, increment balances, then flip status. Single transaction.
-- =========================================================================

create or replace function archive_daily_buys(p_owner uuid)
returns integer
language plpgsql
security invoker
as $$
declare
  v_count   integer;
  v_pending integer;
begin
  if p_owner is null or p_owner <> auth.uid() then
    raise exception 'not authorized: p_owner must equal auth.uid()';
  end if;

  select count(*) into v_pending
    from currency_buys
   where owner_id = p_owner
     and status   = 'pending';

  if v_pending > 0 then
    raise exception 'cannot archive: % pending currency buy(s) must be resolved first', v_pending
      using errcode = 'check_violation';
  end if;

  with sums as (
    select exchange_id, sum(usd_amount) as s
      from currency_buys
     where owner_id = p_owner
       and status   = 'daily'
     group by exchange_id
  )
  update exchanges e
     set balance = e.balance + sums.s
    from sums
   where e.id = sums.exchange_id;

  update currency_buys
     set status      = 'archived',
         archived_at = now()
   where owner_id = p_owner
     and status   = 'daily';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

commit;
