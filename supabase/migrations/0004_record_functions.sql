-- 0004_record_functions.sql
-- Atomic write helpers used by Phase 3 UI. Each function performs both the
-- insert into the transactional table and the matching balance update on
-- exchanges in a single Postgres transaction so the two cannot drift.
-- All SECURITY INVOKER, all check ownership against auth.uid().

begin;

-- =========================================================================
-- record_transfer
-- Inserts a transfer (status='daily') and decrements the exchange balance
-- by the same amount. Mirrors saveToDailyList() (project_web.html:608).
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
  v_uid     uuid := auth.uid();
  v_owner   uuid;
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

  update exchanges
     set balance = balance - p_amount
   where id = p_exchange_id;

  return v_inserted;
end;
$$;

-- =========================================================================
-- record_currency_buy
-- Inserts a confirmed currency buy (status='daily') and increments the
-- exchange balance by usd_amount. Mirrors processCurrencyBuy()
-- (project_web.html:626).
-- =========================================================================

create or replace function record_currency_buy(
  p_my_company_id        uuid,
  p_exchange_id          uuid,
  p_client_id            uuid,
  p_client_from_account  text,
  p_usd_amount           numeric,
  p_rate                 numeric,
  p_lyd_amount           numeric
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
    usd_amount, rate, lyd_amount, status
  ) values (
    v_uid, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, p_rate, p_lyd_amount, 'daily'
  )
  returning * into v_inserted;

  update exchanges
     set balance = balance + p_usd_amount
   where id = p_exchange_id;

  return v_inserted;
end;
$$;

-- =========================================================================
-- record_pending_buy
-- Inserts a pending currency buy. No balance change (matches setBuyStatus
-- 'pending' in project_web.html:644).
-- =========================================================================

create or replace function record_pending_buy(
  p_my_company_id        uuid,
  p_exchange_id          uuid,
  p_client_id            uuid,
  p_client_from_account  text,
  p_usd_amount           numeric,
  p_rate                 numeric,
  p_lyd_amount           numeric
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
    usd_amount, rate, lyd_amount, status
  ) values (
    v_uid, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, p_rate, p_lyd_amount, 'pending'
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

commit;
