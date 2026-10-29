-- 0091_customer_credit.sql
-- Phase 2 of docs/accounting-audit-and-plan.md, part 1: selling and buying
-- dollars ON CREDIT (asked for by the owner on 2026-10-29).
--
--  * A sale (exit) names the customer who pays the dinars (from the saved
--    customers) and how much was paid now: all in cash / bank, nothing
--    (credit) or part of it. What was not paid becomes the customer's debt.
--    A purchase (entry) the other way: what we did not pay the seller is
--    what we owe him.
--  * Each customer has ONE dinar account (customer_lyd_entries, append-only):
--    + he owes us more, − he owes us less (or we owe him). Later payments are
--    "collect" (he pays us, into the box or the bank) and "pay" (we pay him),
--    and the administrator may enter an opening balance.
--  * A credit limit per customer, set by the administrator: an employee's
--    sale over it is refused; the administrator is asked and may go over it.
--    No limit set = no credit.
--  * The dinar treasury counts only what was actually paid, plus the
--    collections and payments. Cancelling an operation reverses its debt.
--  * Backups, restores, the redaction and the wipe include the new table.
--
-- Older app builds keep working: a save without the new arguments is paid in
-- full, as before. Needs 0090. Safe to run more than once.

begin;

do $$
begin
  if to_regprocedure('public._next_reference_for(uuid, uuid)') is null then
    raise exception 'شغّل الترحيل 0089 و0090 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- =============================================================================
-- A) columns and the customers' dinar accounts
-- =============================================================================
alter table clients add column if not exists credit_limit numeric(14,2);
alter table clients drop constraint if exists clients_credit_limit_check;
alter table clients add constraint clients_credit_limit_check
  check (credit_limit is null or credit_limit >= 0);

alter table transfers add column if not exists customer_id uuid references clients (id);
alter table transfers add column if not exists lyd_paid numeric(14,2);
alter table currency_buys add column if not exists lyd_paid numeric(14,2);
-- everything saved before this was paid in full
update transfers set lyd_paid = lyd_amount where lyd_amount is not null and lyd_paid is null;
update currency_buys set lyd_paid = lyd_amount where lyd_amount is not null and lyd_paid is null;
alter table transfers drop constraint if exists transfers_lyd_paid_check;
alter table transfers add constraint transfers_lyd_paid_check
  check ((lyd_amount is null and lyd_paid is null)
      or (lyd_amount is not null and lyd_paid is not null
          and lyd_paid >= 0 and lyd_paid <= lyd_amount));
alter table currency_buys drop constraint if exists currency_buys_lyd_paid_check;
alter table currency_buys add constraint currency_buys_lyd_paid_check
  check ((lyd_amount is null and lyd_paid is null)
      or (lyd_amount is not null and lyd_paid is not null
          and lyd_paid >= 0 and lyd_paid <= lyd_amount));
create index if not exists transfers_customer_idx on transfers (customer_id) where customer_id is not null;

create table if not exists customer_lyd_entries (
  id                     uuid primary key default gen_random_uuid(),
  owner_id               uuid not null references profiles (id) on delete cascade,
  client_id              uuid not null references clients (id),
  kind                   text not null check (kind in
                           ('sale', 'buy', 'sale_cancel', 'buy_cancel',
                            'collect', 'pay', 'opening')),
  -- + the customer owes us more; − he owes us less (or we owe him)
  amount                 numeric(14,2) not null check (amount <> 0),
  pocket                 text check (pocket is null or pocket in ('cash', 'bank')),
  operation_id           uuid,
  note                   text check (note is null or char_length(note) <= 300),
  request_id             uuid,
  created_by_employee_id uuid,
  created_at             timestamptz not null default now()
);
create index if not exists customer_lyd_entries_client_idx
  on customer_lyd_entries (client_id, created_at);
create index if not exists customer_lyd_entries_owner_idx
  on customer_lyd_entries (owner_id, created_at);
create index if not exists customer_lyd_entries_operation_idx
  on customer_lyd_entries (operation_id) where operation_id is not null;
create unique index if not exists customer_lyd_entries_request_uq
  on customer_lyd_entries (owner_id, request_id) where request_id is not null;
alter table customer_lyd_entries enable row level security;
revoke all on table customer_lyd_entries from anon, authenticated;
grant select on table customer_lyd_entries to authenticated;
drop policy if exists customer_lyd_entries_own on customer_lyd_entries;
create policy customer_lyd_entries_own on customer_lyd_entries
  for select to authenticated using (owner_id = (select auth.uid()));

-- the credit limit changes only through set_customer_credit_limit
create or replace function _block_direct_credit_limit()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon')
     and ((tg_op = 'INSERT' and new.credit_limit is not null)
       or (tg_op = 'UPDATE' and new.credit_limit is distinct from old.credit_limit)) then
    raise exception 'credit_limit_direct_edit' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_block_direct_credit_limit on clients;
create trigger trg_block_direct_credit_limit
  before insert or update of credit_limit on clients
  for each row execute function _block_direct_credit_limit();

-- what a customer owes now (+) or is owed (−) (internal)
create or replace function _customer_balance(p_client_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(sum(amount), 0) from customer_lyd_entries where client_id = p_client_id
$$;
revoke all on function _customer_balance(uuid) from public, anon, authenticated;

-- =============================================================================
-- B) the save functions: who pays and how much now
-- =============================================================================
drop function if exists record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid);
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
  p_request_id                    uuid default null,
  p_customer_id                   uuid default null,
  p_lyd_paid                      numeric default null,
  p_over_limit                    boolean default false
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
  v_lyd         numeric;
  v_paid        numeric;
  v_unpaid      numeric := 0;
  v_limit       numeric;
  v_owed        numeric;
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
  if p_customer_id is not null and not exists (
    select 1 from clients where id = p_customer_id and owner_id = v_admin_id
  ) then
    raise exception 'client_not_found_or_forbidden' using errcode = 'P0001';
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

  -- the dinars: paid now (all of them unless told otherwise) and the rest owed
  if v_rate is not null then
    v_lyd := round(p_amount * v_rate, 2);
    v_paid := coalesce(round(p_lyd_paid, 2), v_lyd);
    if v_paid < 0 or v_paid > v_lyd then
      raise exception 'lyd_paid_invalid' using errcode = 'P0001';
    end if;
    v_unpaid := v_lyd - v_paid;
  elsif p_lyd_paid is not null then
    raise exception 'rate_not_set' using errcode = 'P0001';
  end if;
  if v_unpaid > 0 and p_customer_id is null then
    raise exception 'customer_required' using errcode = 'P0001';
  end if;

  perform 1 from exchanges where id = p_exchange_id for update;
  select cost_rate into v_cost from account_costs where exchange_id = p_exchange_id;

  -- the customer, locked before the treasury (the order customer_add_entry
  -- uses, so the two never wait for each other), and his limit
  if p_customer_id is not null then
    select credit_limit into v_limit from clients where id = p_customer_id for update;
  end if;
  if v_unpaid > 0 then
    v_owed := _customer_balance(p_customer_id);
    if v_owed + v_unpaid > coalesce(v_limit, 0)
       and (v_employee_id is not null or not coalesce(p_over_limit, false)) then
      if v_employee_id is not null then
        -- an employee does not see what a customer owes
        raise exception 'credit_limit_exceeded' using errcode = 'P0001';
      end if;
      raise exception 'credit_limit_exceeded' using errcode = 'P0001',
        detail = format('limit %s, owed %s, new %s', coalesce(v_limit, 0), v_owed, v_unpaid);
    end if;
  end if;

  -- a dinar count in progress finishes first (it locks this row for update)
  if v_paid > 0 then
    perform 1 from lyd_treasury where owner_id = v_admin_id for share;
  end if;

  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, archived_at, created_by_employee_id,
    rate, lyd_amount, lyd_method, request_id, customer_id, lyd_paid
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, v_ref, 'archived', now(), v_employee_id,
    v_rate, v_lyd,
    case when v_rate is null or v_paid = 0 then null else coalesce(p_lyd_method, 'cash') end,
    p_request_id, p_customer_id, v_paid
  )
  returning * into v_inserted;

  if v_cost is not null then
    insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                                 cost_before, cost_after)
    values (v_inserted.id, 'sell', v_admin_id, p_exchange_id, v_cost, v_cost);
  end if;

  if v_unpaid > 0 then
    insert into customer_lyd_entries (owner_id, client_id, kind, amount,
                                      operation_id, created_by_employee_id)
    values (v_admin_id, p_customer_id, 'sale', v_unpaid, v_inserted.id, v_employee_id);
  end if;

  update exchanges set balance = balance - p_amount where id = p_exchange_id;

  perform log_employee_activity('transfer_created', v_inserted.id, p_amount);
  return v_inserted;
end;
$$;
revoke all on function record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid, uuid, numeric, boolean) from public, anon;
grant execute on function record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid, uuid, numeric, boolean) to authenticated;

drop function if exists record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid);
-- the very first version (0004), never dropped by name: gone too
drop function if exists record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric);
create or replace function record_currency_buy(
  p_my_company_id uuid, p_exchange_id uuid, p_client_id uuid,
  p_client_from_account text, p_usd_amount numeric, p_rate numeric,
  p_lyd_amount numeric, p_reference text default '',
  p_lyd_method text default null,
  p_request_id uuid default null,
  p_lyd_paid numeric default null
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
  v_lyd         numeric;
  v_paid        numeric;
  v_unpaid      numeric := 0;
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

  -- the dinars: paid now (all of them unless told otherwise) and the rest we owe
  if v_rate is not null then
    v_lyd := round(p_usd_amount * v_rate, 2);
    v_paid := coalesce(round(p_lyd_paid, 2), v_lyd);
    if v_paid < 0 or v_paid > v_lyd then
      raise exception 'lyd_paid_invalid' using errcode = 'P0001';
    end if;
    v_unpaid := v_lyd - v_paid;
  elsif p_lyd_paid is not null then
    raise exception 'rate_not_set' using errcode = 'P0001';
  end if;
  if v_unpaid > 0 and p_client_id is null then
    raise exception 'customer_required' using errcode = 'P0001';
  end if;

  select balance into v_balance from exchanges where id = p_exchange_id for update;

  -- the same request again: the account lock makes a retry wait for the first
  if p_request_id is not null then
    select * into v_inserted from currency_buys
     where owner_id = v_admin_id and request_id = p_request_id;
    if found then
      return v_inserted;
    end if;
  end if;

  -- the seller, locked before the treasury (the order customer_add_entry uses)
  if p_client_id is not null then
    perform 1 from clients where id = p_client_id for update;
  end if;
  if v_paid > 0 then
    perform 1 from lyd_treasury where owner_id = v_admin_id for share;
  end if;

  select c.cost_before, c.cost_after into v_cost_before, v_cost_after
    from _apply_buy_cost(v_admin_id, p_exchange_id, v_balance, p_usd_amount,
                         v_rate, v_id) c;

  insert into currency_buys (
    id, owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id, lyd_method, request_id, lyd_paid
  ) values (
    v_id, v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, v_lyd, 'archived', now(), p_reference,
    v_employee_id,
    case when v_rate is null or v_paid = 0 then null else coalesce(p_lyd_method, 'cash') end,
    p_request_id, v_paid
  )
  returning * into v_inserted;

  if v_unpaid > 0 then
    insert into customer_lyd_entries (owner_id, client_id, kind, amount,
                                      operation_id, created_by_employee_id)
    values (v_admin_id, p_client_id, 'buy', -v_unpaid, v_id, v_employee_id);
  end if;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;
revoke all on function record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid, numeric) from public, anon;
grant execute on function record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid, numeric) to authenticated;

-- =============================================================================
-- C) a cancelled operation gives its debt back
-- =============================================================================
create or replace function _customer_debt_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into customer_lyd_entries (owner_id, client_id, kind, amount, operation_id)
  select e.owner_id, e.client_id,
         case e.kind when 'sale' then 'sale_cancel' else 'buy_cancel' end,
         -e.amount, e.operation_id
    from customer_lyd_entries e
   where e.operation_id = new.id and e.kind in ('sale', 'buy');
  return new;
end;
$$;
drop trigger if exists trg_customer_debt_on_cancel on transfers;
create trigger trg_customer_debt_on_cancel
  after update of cancelled_at on transfers
  for each row
  when (old.cancelled_at is null and new.cancelled_at is not null)
  execute function _customer_debt_on_cancel();
drop trigger if exists trg_customer_debt_on_cancel on currency_buys;
create trigger trg_customer_debt_on_cancel
  after update of cancelled_at on currency_buys
  for each row
  when (old.cancelled_at is null and new.cancelled_at is not null)
  execute function _customer_debt_on_cancel();

-- =============================================================================
-- D) the administrator: limits, collections, payments, opening balances
-- =============================================================================
create or replace function set_customer_credit_limit(p_client_id uuid, p_limit numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_limit is not null and (p_limit < 0 or p_limit > 999999999999.99) then
    raise exception 'credit_limit_invalid' using errcode = 'P0001';
  end if;
  update clients set credit_limit = round(p_limit, 2)
   where id = p_client_id and owner_id = v_admin;
  if not found then
    raise exception 'client_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  return jsonb_build_object('ok', true, 'credit_limit', round(p_limit, 2));
end;
$$;
revoke all on function set_customer_credit_limit(uuid, numeric) from public, anon;
grant execute on function set_customer_credit_limit(uuid, numeric) to authenticated;

-- collect: the customer pays us [amount] into [pocket]
-- pay:     we pay the customer [amount] from [pocket]
-- opening: what he owes us (+) or we owe him (−) before the app
create or replace function customer_add_entry(
  p_client_id  uuid,
  p_kind       text,
  p_amount     numeric,
  p_pocket     text default null,
  p_note       text default null,
  p_request_id uuid default null
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
  v_signed numeric;
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_kind not in ('collect', 'pay', 'opening') then
    raise exception 'lyd_kind_invalid' using errcode = 'P0001';
  end if;
  if p_kind in ('collect', 'pay') then
    if v_amount <= 0 or v_amount > 999999999999.99 then
      raise exception 'lyd_amount_invalid' using errcode = 'P0001';
    end if;
    if p_pocket is null or p_pocket not in ('cash', 'bank') then
      raise exception 'lyd_kind_invalid' using errcode = 'P0001';
    end if;
  elsif v_amount = 0 or abs(v_amount) > 999999999999.99 then
    raise exception 'lyd_amount_invalid' using errcode = 'P0001';
  end if;

  perform 1 from clients where id = p_client_id and owner_id = v_admin for update;
  if not found then
    raise exception 'client_not_found_or_forbidden' using errcode = 'P0001';
  end if;

  if p_request_id is not null and exists (
    select 1 from customer_lyd_entries where owner_id = v_admin and request_id = p_request_id
  ) then
    return jsonb_build_object('ok', true, 'balance', _customer_balance(p_client_id));
  end if;

  if p_kind in ('collect', 'pay') then
    -- the treasury row: a count waits for this, and nothing leaves a pocket
    -- that does not hold it
    perform 1 from lyd_treasury where owner_id = v_admin for update;
    if found and p_kind = 'pay' then
      select * into v_pos from _lyd_position(v_admin);
      v_from := case p_pocket when 'cash' then v_pos.cash else v_pos.bank end;
      if v_amount > v_from then
        raise exception 'lyd_insufficient' using errcode = 'P0001',
          detail = format('available %s, amount %s', v_from, v_amount);
      end if;
    end if;
  end if;

  v_signed := case p_kind when 'collect' then -v_amount when 'pay' then v_amount else v_amount end;
  insert into customer_lyd_entries (owner_id, client_id, kind, amount, pocket, note, request_id)
  values (v_admin, p_client_id, p_kind, v_signed,
          case when p_kind in ('collect', 'pay') then p_pocket end,
          nullif(btrim(coalesce(p_note, '')), ''), p_request_id);
  return jsonb_build_object('ok', true, 'balance', _customer_balance(p_client_id));
end;
$$;
revoke all on function customer_add_entry(uuid, text, numeric, text, text, uuid) from public, anon;
grant execute on function customer_add_entry(uuid, text, numeric, text, text, uuid) to authenticated;

-- every customer with a dinar account or a limit: what he owes (+) / is owed (−)
create or replace function customer_balances()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'client_id', c.id, 'name', c.name, 'company', c.company, 'code', c.code,
             'credit_limit', c.credit_limit,
             'balance', coalesce(s.balance, 0),
             'last_at', s.last_at)
           order by coalesce(s.balance, 0) desc, c.name)
      from clients c
      left join (select client_id, sum(amount) as balance, max(created_at) as last_at
                   from customer_lyd_entries where owner_id = v_admin
                  group by client_id) s on s.client_id = c.id
     where c.owner_id = v_admin
       and (s.client_id is not null or c.credit_limit is not null)
  ), '[]'::jsonb);
end;
$$;
revoke all on function customer_balances() from public, anon;
grant execute on function customer_balances() to authenticated;

-- one customer's dinar statement for [from, to]
create or replace function customer_statement(
  p_client_id uuid, p_from timestamptz, p_to timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin   uuid := _lyd_admin();
  v_opening numeric;
begin
  if not exists (select 1 from clients where id = p_client_id and owner_id = v_admin) then
    raise exception 'client_not_found_or_forbidden' using errcode = 'P0001';
  end if;
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  select coalesce(sum(amount), 0) into v_opening
    from customer_lyd_entries where client_id = p_client_id and created_at < p_from;
  return jsonb_build_object(
    'opening', v_opening,
    'closing', _customer_balance(p_client_id),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'kind', e.kind, 'amount', e.amount, 'pocket', e.pocket,
               'note', e.note, 'created_at', e.created_at,
               'operation_id', e.operation_id,
               'reference', coalesce(t.reference, b.reference),
               'usd', coalesce(t.amount, b.usd_amount),
               'rate', coalesce(t.rate, b.rate),
               'lyd', coalesce(t.lyd_amount, b.lyd_amount))
             order by e.created_at, e.id)
        from customer_lyd_entries e
        left join transfers t on t.id = e.operation_id
        left join currency_buys b on b.id = e.operation_id
       where e.client_id = p_client_id
         and e.created_at between p_from and p_to), '[]'::jsonb)
  );
end;
$$;
revoke all on function customer_statement(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function customer_statement(uuid, timestamptz, timestamptz) to authenticated;

-- =============================================================================

-- G) existing functions that now know the customers' ledger (copied from

--    their latest definition: 0086, and 0089 for the restore and the wipe)

-- =============================================================================

create or replace function _lyd_position(p_owner uuid, out cash numeric, out bank numeric)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_t lyd_treasury;
begin
  select * into v_t from lyd_treasury where owner_id = p_owner;
  if not found then
    cash := null; bank := null;
    return;
  end if;
  cash := v_t.opening_cash;
  bank := v_t.opening_bank;

  select cash + coalesce(sum(case
           when m.kind = 'in' and m.pocket = 'cash' then m.amount
           when m.kind = 'out' and m.pocket = 'cash' then -m.amount
           when m.kind = 'cash_to_bank' then -m.amount
           when m.kind = 'bank_to_cash' then m.amount
           when m.kind = 'count_over' then m.amount
           when m.kind = 'count_short' then -m.amount
           else 0 end), 0),
         bank + coalesce(sum(case
           when m.kind = 'in' and m.pocket = 'bank' then m.amount
           when m.kind = 'out' and m.pocket = 'bank' then -m.amount
           when m.kind = 'cash_to_bank' then m.amount
           when m.kind = 'bank_to_cash' then -m.amount
           else 0 end), 0)
    into cash, bank
    from lyd_movements m
   where m.owner_id = p_owner;

  select cash + coalesce(sum(t.lyd_paid) filter (where t.lyd_method = 'cash'), 0),
         bank + coalesce(sum(t.lyd_paid) filter (where t.lyd_method = 'bank'), 0)
    into cash, bank
    from transfers t
   where t.owner_id = p_owner and t.status = 'archived' and t.cancelled_at is null
     and t.lyd_amount is not null and t.created_at >= v_t.started_at;

  select cash - coalesce(sum(b.lyd_paid) filter (where b.lyd_method = 'cash'), 0),
         bank - coalesce(sum(b.lyd_paid) filter (where b.lyd_method = 'bank'), 0)
    into cash, bank
    from currency_buys b
   where b.owner_id = p_owner and b.status = 'archived' and b.cancelled_at is null
     and b.lyd_amount is not null and b.created_at >= v_t.started_at;

  -- what customers paid us later (collect, stored negative) and what we paid
  -- sellers later (pay, stored positive), by pocket (0091)
  select cash - coalesce(sum(e.amount) filter (where e.kind in ('collect', 'pay') and e.pocket = 'cash'), 0),
         bank - coalesce(sum(e.amount) filter (where e.kind in ('collect', 'pay') and e.pocket = 'bank'), 0)
    into cash, bank
    from customer_lyd_entries e
   where e.owner_id = p_owner and e.created_at >= v_t.started_at;
end;
$$;

create or replace function lyd_summary(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_t     lyd_treasury;
  v_pos   record;
  v_flows jsonb;
begin
  select * into v_t from lyd_treasury where owner_id = v_admin;
  if not found then
    return jsonb_build_object('open', false);
  end if;
  select * into v_pos from _lyd_position(v_admin);

  select jsonb_build_object(
    'sales_cash', coalesce((select sum(lyd_paid) from transfers
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'cash' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'sales_bank', coalesce((select sum(lyd_paid) from transfers
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'bank' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'buys_cash', coalesce((select sum(lyd_paid) from currency_buys
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'cash' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'buys_bank', coalesce((select sum(lyd_paid) from currency_buys
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'bank' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'collect_cash', coalesce((select -sum(amount) from customer_lyd_entries
        where owner_id = v_admin and kind = 'collect' and pocket = 'cash'
          and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'collect_bank', coalesce((select -sum(amount) from customer_lyd_entries
        where owner_id = v_admin and kind = 'collect' and pocket = 'bank'
          and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'pay_cash', coalesce((select sum(amount) from customer_lyd_entries
        where owner_id = v_admin and kind = 'pay' and pocket = 'cash'
          and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'pay_bank', coalesce((select sum(amount) from customer_lyd_entries
        where owner_id = v_admin and kind = 'pay' and pocket = 'bank'
          and created_at between greatest(p_from, v_t.started_at) and p_to), 0)
  ) into v_flows;

  return jsonb_build_object(
    'open', true,
    'started_at', v_t.started_at,
    'opening_cash', v_t.opening_cash,
    'opening_bank', v_t.opening_bank,
    'cash', v_pos.cash,
    'bank', v_pos.bank,
    'flows', v_flows,
    'movements', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id, 'kind', m.kind, 'pocket', m.pocket, 'amount', m.amount,
               'note', m.note, 'created_at', m.created_at) order by m.created_at desc)
        from lyd_movements m
       where m.owner_id = v_admin and m.created_at between p_from and p_to), '[]'::jsonb),
    'counts', coalesce((
      select jsonb_agg(c order by c.created_at desc)
        from (select id, expected, counted, difference, posted, note, created_at
                from lyd_counts where owner_id = v_admin
               order by created_at desc limit 30) c), '[]'::jsonb)
  );
end;
$$;

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
    'employee_activity_logs', 'notifications',
    'cancellation_requests', 'operation_cancellations',
    'account_expenses',
    'last_exchange_rates', 'account_costs', 'account_cost_events',
    'operation_costs',
    'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts',
    'customer_lyd_entries'
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

  perform set_config('eshary.skip_balance_check', 'on', true);
  perform set_config('eshary.restoring', 'on', true);

  -- Safety net: snapshot the current state first.
  perform public._save_backup('pre_restore');

  -- Children first.
  delete from public.customer_lyd_entries where true;
  delete from public.lyd_counts where true;
  delete from public.lyd_movements where true;
  delete from public.lyd_treasury where true;
  delete from public.balance_adjustments where true;
  delete from public.operation_costs where true;
  delete from public.account_cost_events where true;
  delete from public.account_costs where true;
  delete from public.last_exchange_rates where true;
  delete from public.operation_cancellations where true;
  delete from public.cancellation_requests where true;
  delete from public.account_expenses where true;
  delete from public.employee_activity_logs where true;
  delete from public.transfers where true;
  delete from public.currency_buys where true;
  delete from public.exchanges where true;
  delete from public.clients where true;
  delete from public.beneficiaries where true;
  delete from public.countries where true;
  delete from public.exchange_companies where true;
  delete from public.companies where true;
  delete from public.sub_users where true;
  delete from public.branches where true;

  -- Parents first. Rows whose owning account no longer exists are skipped. A
  -- backup made before a table existed simply has no rows for it.
  foreach t in array array[
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs',
    'cancellation_requests', 'operation_cancellations',
    'account_expenses',
    'last_exchange_rates', 'account_costs', 'account_cost_events',
    'operation_costs',
    'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts',
    'customer_lyd_entries'
  ] loop
    v_rows := coalesce(v_tables -> t, '[]'::jsonb);

    if t = 'employee_activity_logs' then
      select coalesce(jsonb_agg(elem - 'session_id'), '[]'::jsonb)
        into v_rows
        from jsonb_array_elements(v_rows) elem;
    end if;

    -- a backup made before 0091 has no lyd_paid: it was paid in full
    if t in ('transfers', 'currency_buys') then
      select coalesce(jsonb_agg(case when elem ? 'lyd_paid' then elem
               else elem || jsonb_build_object('lyd_paid', elem -> 'lyd_amount') end), '[]'::jsonb)
        into v_rows
        from jsonb_array_elements(v_rows) elem;
    end if;

    v_filter := case t
      when 'branches'               then 'r.parent_admin_id in (select id from auth.users)'
      when 'sub_users'              then 'r.parent_admin_id in (select id from auth.users)'
      when 'employee_activity_logs' then 'r.parent_admin_id in (select id from auth.users)'
      when 'exchanges'              then 'r.company_id in (select id from public.companies)'
      when 'account_expenses'       then 'r.exchange_id in (select id from public.exchanges)'
      when 'account_costs'          then 'r.exchange_id in (select id from public.exchanges)'
      when 'account_cost_events'    then 'r.exchange_id in (select id from public.exchanges)'
      when 'operation_costs'        then 'r.exchange_id in (select id from public.exchanges)'
      when 'balance_adjustments'    then 'r.exchange_id in (select id from public.exchanges)'
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

create or replace function _redact_owner_from_backups(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.backups b
     set data = jsonb_set(
       b.data,
       '{tables}',
       (
         select coalesce(jsonb_object_agg(e.k, case
           when e.k = 'profiles' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'id' is distinct from p_uid::text)
           when e.k = 'account_licenses' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'user_id' is distinct from p_uid::text)
           when e.k in ('branches', 'sub_users', 'employee_activity_logs') then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'parent_admin_id' is distinct from p_uid::text)
           when e.k = 'exchanges' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where (r ->> 'company_id') not in (
                 select c ->> 'id'
                   from jsonb_array_elements(coalesce(b.data -> 'tables' -> 'companies', '[]'::jsonb)) c
                  where c ->> 'owner_id' = p_uid::text))
           when e.k in ('companies', 'clients', 'beneficiaries', 'countries',
                        'exchange_companies', 'transfers', 'currency_buys',
                        'cancellation_requests', 'operation_cancellations',
                        'account_expenses', 'last_exchange_rates',
                        'account_costs', 'account_cost_events',
                        'operation_costs', 'balance_adjustments',
                        'lyd_treasury', 'lyd_movements', 'lyd_counts',
                        'customer_lyd_entries') then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'owner_id' is distinct from p_uid::text)
           else e.v
         end), '{}'::jsonb)
         from jsonb_each(b.data -> 'tables') as e(k, v)
       )
     )
   where jsonb_typeof(b.data -> 'tables') = 'object';
  update public.backups set size_bytes = octet_length(data::text) where true;
end;
$$;

create or replace function public.admin_restore_owner(p_backup_id uuid, p_owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tables jsonb;
  v_rows   jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_n      integer;
  t        text;
  v_filter text;
  v_before jsonb := '{}'::jsonb;
  r        record;
  v_old    text[];
  v_new    text[];
  v_now    text;
  v_active integer;
begin
  if not public.is_caller_admin() then
    raise exception 'admin only';
  end if;
  select data -> 'tables' into v_tables from public.backups where id = p_backup_id;
  if v_tables is null then
    raise exception 'backup_not_found' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profiles where id = p_owner) then
    raise exception 'owner_not_found' using errcode = 'P0001';
  end if;
  -- a backup without this subscriber would only delete them
  if not exists (
    select 1 from jsonb_array_elements(coalesce(v_tables -> 'companies', '[]'::jsonb)) c
     where c ->> 'owner_id' = p_owner::text
  ) then
    raise exception 'owner_not_in_backup' using errcode = 'P0001';
  end if;

  perform set_config('eshary.skip_balance_check', 'on', true);
  perform set_config('eshary.restoring', 'on', true);
  -- no exit of this subscriber is saved while the restore runs
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || p_owner::text, 0));

  -- the number each company would give next NOW: never given again
  for r in select id from public.companies where owner_id = p_owner loop
    v_before := v_before || jsonb_build_object(r.id::text, _next_reference_for(p_owner, r.id));
  end loop;

  -- Safety net: snapshot the current state first.
  perform public._save_backup('pre_restore');

  -- this subscriber's rows only, children first
  delete from public.customer_lyd_entries where owner_id = p_owner;
  delete from public.lyd_counts where owner_id = p_owner;
  delete from public.lyd_movements where owner_id = p_owner;
  delete from public.lyd_treasury where owner_id = p_owner;
  delete from public.balance_adjustments where owner_id = p_owner;
  delete from public.operation_costs where owner_id = p_owner;
  delete from public.account_cost_events where owner_id = p_owner;
  delete from public.account_costs where owner_id = p_owner;
  delete from public.last_exchange_rates where owner_id = p_owner;
  delete from public.operation_cancellations where owner_id = p_owner;
  delete from public.cancellation_requests where owner_id = p_owner;
  delete from public.account_expenses where owner_id = p_owner;
  delete from public.employee_activity_logs where parent_admin_id = p_owner;
  delete from public.transfers where owner_id = p_owner;
  delete from public.currency_buys where owner_id = p_owner;
  delete from public.exchanges
   where company_id in (select id from public.companies where owner_id = p_owner);
  delete from public.clients where owner_id = p_owner;
  delete from public.beneficiaries where owner_id = p_owner;
  delete from public.countries where owner_id = p_owner;
  delete from public.exchange_companies where owner_id = p_owner;
  delete from public.companies where owner_id = p_owner;
  delete from public.sub_users where parent_admin_id = p_owner;
  delete from public.branches where parent_admin_id = p_owner;

  -- parents first, as the full restore
  foreach t in array array[
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs',
    'cancellation_requests', 'operation_cancellations',
    'account_expenses',
    'last_exchange_rates', 'account_costs', 'account_cost_events',
    'operation_costs',
    'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts',
    'customer_lyd_entries'
  ] loop
    v_rows := coalesce(v_tables -> t, '[]'::jsonb);

    if t = 'employee_activity_logs' then
      select coalesce(jsonb_agg(elem - 'session_id'), '[]'::jsonb)
        into v_rows
        from jsonb_array_elements(v_rows) elem;
    end if;

    -- a backup made before 0091 has no lyd_paid: it was paid in full
    if t in ('transfers', 'currency_buys') then
      select coalesce(jsonb_agg(case when elem ? 'lyd_paid' then elem
               else elem || jsonb_build_object('lyd_paid', elem -> 'lyd_amount') end), '[]'::jsonb)
        into v_rows
        from jsonb_array_elements(v_rows) elem;
    end if;

    v_filter := case t
      when 'branches'               then 'r.parent_admin_id = $2'
      when 'sub_users'              then 'r.parent_admin_id = $2'
      when 'employee_activity_logs' then 'r.parent_admin_id = $2'
      when 'exchanges'              then 'r.company_id in (select id from public.companies where owner_id = $2)'
      else                               'r.owner_id = $2'
    end;

    execute format(
      'insert into public.%1$I select r.* from jsonb_populate_recordset(null::public.%1$I, $1) r where %2$s',
      t, v_filter
    ) using v_rows, p_owner;
    get diagnostics v_n = row_count;
    v_counts := v_counts || jsonb_build_object(t, v_n);
  end loop;

  -- the numbering never goes back: a company now behind the number it would
  -- have given before the restore starts again from that number
  select count(*) into v_active
    from public.transfers where owner_id = p_owner and cancelled_at is null;
  for r in select id from public.companies where owner_id = p_owner loop
    v_now := v_before ->> r.id::text;
    continue when v_now is null;
    v_old := regexp_match(v_now, '^([^0-9]*)([0-9]+)$');
    v_new := regexp_match(coalesce(_next_reference_for(p_owner, r.id), ''), '^([^0-9]*)([0-9]+)$');
    if v_old is not null and v_new is not null and v_old[1] = v_new[1]
       and v_new[2]::numeric < v_old[2]::numeric
       and v_old[2]::numeric - v_active >= 0 then
      update public.companies
         set start_ref = v_old[1] || _ref_pad(v_old[2]::numeric - v_active, length(v_old[2]))
       where id = r.id;
    end if;
  end loop;

  return v_counts;
end;
$$;

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

  -- no exit of this administrator meanwhile (the reference lock), and every
  -- account locked before anything else, in the order the saves lock them:
  -- an entry saved at this moment either finishes first or waits for the wipe
  perform pg_advisory_xact_lock(hashtextextended('eshary.ref:' || v_owner::text, 0));
  perform 1 from exchanges e join companies c on c.id = e.company_id
   where c.owner_id = v_owner
   order by e.id
     for update of e;
  -- and the dinar treasury: no collection or payment slips in meanwhile
  perform 1 from lyd_treasury where owner_id = v_owner for update;

  -- A way back: a full snapshot before anything changes (the numbering too).
  v_backup := public._save_backup('pre_wipe');

  -- the numbering goes on after the last number used: every company starts
  -- again from the number it would have given next
  for r in select id from companies where owner_id = v_owner loop
    update companies set start_ref = _next_reference_for(v_owner, r.id) where id = r.id;
  end loop;

  delete from customer_lyd_entries where owner_id = v_owner;
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

create or replace function delete_party(p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner   uuid := auth.uid();
  v_party   clients;
  v_removed text;
begin
  if v_owner is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select * into v_party from clients
   where id = p_client_id and owner_id = v_owner
     for update;
  if not found then
    raise exception 'party_not_found' using errcode = 'P0001';
  end if;
  if exists (select 1 from currency_buys where client_id = p_client_id)
     or exists (select 1 from transfers where customer_id = p_client_id)
     or exists (select 1 from customer_lyd_entries where client_id = p_client_id) then
    raise exception 'client_has_operations' using errcode = 'P0001';
  end if;

  delete from clients where id = p_client_id;

  -- the company that came with it, when nothing else uses it and nothing was
  -- ever recorded on it
  if nullif(btrim(coalesce(v_party.company, '')), '') is not null
     and not exists (
       select 1 from clients c
        where c.owner_id = v_owner and c.company = v_party.company)
     and not exists (
       select 1 from transfers t
        where t.owner_id = v_owner
          and t.beneficiary_account_company = v_party.company) then
    delete from exchange_companies ec
     where ec.owner_id = v_owner
       and ec.name = v_party.company
       and ec.kind = 'client'
    returning ec.name into v_removed;
  end if;

  return jsonb_build_object('ok', true, 'company_removed', v_removed);
end;
$$;

commit;
