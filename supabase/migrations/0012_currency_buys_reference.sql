-- 0012_currency_buys_reference.sql
-- Adds the إشاري (reference) column to currency_buys and overloads the two
-- buy-recording RPCs to accept and persist it. The new parameter has a
-- default of '' so callers compiled against the previous signature keep
-- working.

begin;

alter table currency_buys
  add column if not exists reference text not null default '';

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

  update exchanges
     set balance = balance + p_usd_amount
   where id = p_exchange_id;

  return v_inserted;
end;
$$;

create or replace function record_pending_buy(
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
    p_usd_amount, p_rate, p_lyd_amount, 'pending', p_reference
  )
  returning * into v_inserted;

  return v_inserted;
end;
$$;

commit;
