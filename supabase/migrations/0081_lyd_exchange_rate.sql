-- 0081_lyd_exchange_rate.sql
-- The Libyan dinar next to the dollar. Every exit (we SELL dollars) and every
-- entry (we BUY dollars) now carries an exchange rate and its total in dinars:
--
--   lyd_amount = round(usd × rate, 2)        -- computed HERE, never by the app
--   (usd as stored, to the cent; rate as stored, to 4 decimals; half up)
--
-- * transfers gets rate numeric(10,4) and lyd_amount numeric(14,2); old rows
--   keep both empty (no rate was ever asked for them).
-- * currency_buys already had both columns, but the app sent a hidden rate of 1
--   (so lyd = usd). Those placeholder values are emptied: an entry without a
--   real rate shows "—" and stays out of the dinar totals.
-- * The account balances stay in dollars; nothing here moves a balance.
-- * The rate is required by the new app. The database still accepts an
--   operation WITHOUT a rate from an older build (it is stored empty), so the
--   phones that have not updated yet keep working.
-- * An employee without the new permission "rate_edit" cannot choose the rate:
--   the database uses the last rate the ADMINISTRATOR used for that kind
--   (sell for an exit, buy for an entry), whatever the phone sent.
-- Safe to run more than once.

begin;

-- superseded-guard: a later migration redefined what this file defines; running
-- it again would undo that, so it refuses.
do $$
begin
  if to_regclass('public.account_costs') is not null then
    raise exception 'هذا الملف (0081) طُبّق سابقًا وجاءت بعده ترحيلات أحدث، وإعادة تشغيله تلغي إصلاحاتها. لم يتغير شيء.';
  end if;
end $$;

-- 1) the columns --------------------------------------------------------------
alter table transfers
  add column if not exists rate       numeric(10,4),
  add column if not exists lyd_amount numeric(14,2);

alter table currency_buys alter column rate drop not null;
alter table currency_buys alter column lyd_amount drop not null;

-- the hidden placeholder of the earlier builds: rate 1, dinars = dollars
update currency_buys
   set rate = null, lyd_amount = null
 where rate = 1 and lyd_amount = usd_amount;

alter table transfers drop constraint if exists transfers_rate_pair;
alter table transfers add constraint transfers_rate_pair check (
  (rate is null and lyd_amount is null)
  or (rate is not null and lyd_amount is not null and rate > 0 and lyd_amount >= 0)
);
alter table currency_buys drop constraint if exists currency_buys_rate_pair;
alter table currency_buys add constraint currency_buys_rate_pair check (
  (rate is null and lyd_amount is null)
  or (rate is not null and lyd_amount is not null and rate > 0 and lyd_amount >= 0)
);

-- 2) the administrator's last rate per kind ------------------------------------
-- Written only by record_transfer / record_currency_buy when the administrator
-- saves an operation. No direct access (RLS on, no policy).
create table if not exists last_exchange_rates (
  owner_id   uuid not null references profiles (id) on delete cascade,
  kind       text not null check (kind in ('sell', 'buy')),
  rate       numeric(10,4) not null check (rate > 0),
  updated_at timestamptz not null default now(),
  primary key (owner_id, kind)
);
alter table last_exchange_rates enable row level security;
revoke all on table last_exchange_rates from anon, authenticated;

-- 3) the permission key ---------------------------------------------------------
-- every key of the earlier migrations (0078 added clients_add) plus rate_edit
create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all',
               'party_letters', 'clients_add', 'rate_edit']
$$;

-- 4) the rate an operation is saved with ---------------------------------------
-- p_rate: what the phone sent (null = an older build that asks no rate).
-- Returns the rate to store, or null.
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

  if current_employee_id() is not null and not employee_has_perm('rate_edit') then
    select rate into v_last
      from last_exchange_rates
     where owner_id = v_admin and kind = p_kind;
    if v_last is null and p_rate is not null then
      raise exception 'rate_not_set' using errcode = 'P0001';
    end if;
    return v_last;
  end if;

  if p_rate is not null and current_employee_id() is null then
    insert into last_exchange_rates (owner_id, kind, rate, updated_at)
    values (v_admin, p_kind, p_rate, now())
    on conflict (owner_id, kind)
      do update set rate = excluded.rate, updated_at = excluded.updated_at;
  end if;
  return round(p_rate, 4);
end;
$$;
revoke all on function _operation_rate(text, numeric) from public, anon, authenticated;

-- What the exit / entry screens show: the last rates and whether the caller may
-- type another one.
create or replace function current_exchange_rates()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
begin
  if v_admin is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'sell', (select rate from last_exchange_rates where owner_id = v_admin and kind = 'sell'),
    'buy',  (select rate from last_exchange_rates where owner_id = v_admin and kind = 'buy'),
    'can_edit', current_employee_id() is null or employee_has_perm('rate_edit')
  );
end;
$$;
revoke all on function current_exchange_rates() from public, anon;
grant execute on function current_exchange_rates() to authenticated;

-- 5) exit: one more argument, p_rate (an older build simply does not send it) ---
drop function if exists record_transfer(uuid, uuid, text, text, text, numeric, text);

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
    rate, lyd_amount
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'archived', now(), v_employee_id,
    v_rate, round(round(p_amount, 2) * v_rate, 2)
  )
  returning * into v_inserted;

  update exchanges set balance = balance - p_amount where id = p_exchange_id;

  perform log_employee_activity('transfer_created', v_inserted.id, p_amount);
  return v_inserted;
end;
$$;

-- 6) entry: same arguments as before; the dinars are computed here ------------
-- p_lyd_amount is ignored. An older build sends the placeholder rate 1 with
-- dinars = dollars: that is "no rate".
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

  insert into currency_buys (
    owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id
  ) values (
    v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, round(round(p_usd_amount, 2) * v_rate, 2), 'archived', now(), p_reference,
    v_employee_id
  )
  returning * into v_inserted;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

commit;
