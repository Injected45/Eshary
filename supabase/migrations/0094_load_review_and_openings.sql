-- 0094: the load review (phase 3) and the opening balances.
--
-- 1) «رصيد أول المدة»: admin_set_opening(account, book, usd, cost) gives a
--    book that never moved its first dollars at their cost — the same entry
--    as opening an account (a balance_adjustments 'opening' line + the
--    'opening' cost: dollars at cost against capital). Once per book; a
--    correction afterwards is «تسوية الرصيد» / the cost. An account still
--    holding dollars from before 0093 is split with set_account_books first.
-- 2) The cancellations check the password under the shared lock
--    (_admin_password_error): parallel guesses could beat the 5-in-15-minutes
--    limit of their old inline check.
-- 3) A cancellation locks the customer and the dinar treasury like the saves
--    do, so a dinar count running at that moment cannot count it twice.
-- 4) A retried purchase finds the saved one BEFORE the rate is checked (a
--    rate changed meanwhile made the retry fail, and the purchase was then
--    typed again).
-- 5) The next reference reads the highest number from an index instead of
--    scanning every transfer while every sale of the company waits for it.
-- 6) Request ids for a dinar movement, a move between books and a commission
--    (a resend after a dropped connection posted them twice).
-- 7) Owner indexes the statements and the ledger read by.
-- 8) One credit limit per customer over BOTH books (it was per book, so a
--    customer limited to 1,000 could owe 1,000 cash + 1,000 bank).
--
-- Administrator only. Needs 0093. Safe to run more than once.

begin;

do $$
begin
  if to_regclass('public.account_books') is null then
    raise exception 'شغّل الترحيل 0093 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- =============================================================================
-- 6) request ids: the columns and their unique indexes
-- =============================================================================
alter table lyd_movements add column if not exists request_id uuid;
alter table book_transfers add column if not exists request_id uuid;
alter table account_expenses add column if not exists request_id uuid;
create unique index if not exists lyd_movements_owner_request_uq
  on lyd_movements (owner_id, request_id) where request_id is not null;
create unique index if not exists book_transfers_owner_request_uq
  on book_transfers (owner_id, request_id) where request_id is not null;
create unique index if not exists account_expenses_owner_request_uq
  on account_expenses (owner_id, request_id) where request_id is not null;

-- =============================================================================
-- 5 + 7) indexes
-- =============================================================================
-- the active transfers of an owner (the count of next_reference)
create index if not exists transfers_owner_active_idx
  on transfers (owner_id) where cancelled_at is null;
-- the highest number of a prefix (next_reference)
create index if not exists transfers_owner_refnum_idx
  on transfers (owner_id, (substring(reference from '^[^0-9]*')),
                ((substring(reference from '[0-9]{1,30}$'))::numeric) desc)
  where cancelled_at is null and reference ~ '^[^0-9]*[0-9]{1,30}$';
-- the statements read the adjustments of an owner since a date; the ledger,
-- the wipe and the restore read the cost events and operation costs by owner
create index if not exists balance_adjustments_owner_idx
  on balance_adjustments (owner_id, created_at);
create index if not exists account_cost_events_owner_idx
  on account_cost_events (owner_id, created_at);
create index if not exists operation_costs_owner_idx
  on operation_costs (owner_id);

-- =============================================================================
-- 5) the next reference (copied from 0089; the highest number from the index)
-- =============================================================================
create or replace function _next_reference_for(p_owner uuid, p_company_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_start_ref text;
  v_count     integer;
  v_match     text[];
  v_prefix    text;
  v_first     numeric;
  v_pad_width integer;
  v_max       numeric;
begin
  select start_ref into v_start_ref
    from companies where id = p_company_id and owner_id = p_owner;
  if not found then
    return null;
  end if;
  select count(*) into v_count
    from transfers where owner_id = p_owner and cancelled_at is null;
  v_match := regexp_match(coalesce(v_start_ref, ''), '^([^0-9]*)([0-9]+)$');
  if v_match is not null then
    v_prefix := v_match[1]; v_first := v_match[2]::numeric; v_pad_width := length(v_match[2]);
  else
    v_prefix := coalesce(v_start_ref, ''); v_first := 1; v_pad_width := 3;
  end if;
  if v_match is not null then
    -- (0094) the highest number from an index, not a scan of every transfer:
    -- the prefix has no digits, so "the prefix + only digits" is "the
    -- reference's letters are the prefix and the rest is digits"
    select (substring(reference from '[0-9]{1,30}$'))::numeric
      into v_max
      from transfers
     where owner_id = p_owner
       and cancelled_at is null
       and reference ~ '^[^0-9]*[0-9]{1,30}$'
       and substring(reference from '^[^0-9]*') = v_prefix
     order by (substring(reference from '[0-9]{1,30}$'))::numeric desc
     limit 1;
  else
    select max(substr(reference, length(v_prefix) + 1)::numeric)
      into v_max
      from transfers
     where owner_id = p_owner
       and cancelled_at is null
       and left(reference, length(v_prefix)) = v_prefix
       and substr(reference, length(v_prefix) + 1) ~ '^[0-9]{1,30}$';
  end if;
  return v_prefix || _ref_pad(greatest(v_first + v_count, coalesce(v_max + 1, 0)), v_pad_width);
end;
$$;
revoke all on function _next_reference_for(uuid, uuid) from public, anon, authenticated;

-- =============================================================================
-- 2 + 3) the cancellations (copied from 0093)
-- =============================================================================
create or replace function admin_cancel_operation(
  p_kind         text,
  p_operation_id uuid,
  p_reason       text,
  p_password     text,
  p_request_id   uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin      uuid := auth.uid();
  v_reason     text := btrim(coalesce(p_reason, ''));
  v_hash       text;
  v_admin_name text;
  v_fails      integer;
  v_err        jsonb;
  v_t          transfers;
  v_b          currency_buys;
  v_company    uuid;
  v_exchange   uuid;
  v_amount     numeric;
  v_ref        text;
  v_party      text;
  v_at         timestamptz;
  v_emp        uuid;
  v_emp_name   text;
  v_before     numeric;
  v_after      numeric;
  v_book       text;
  v_in_book    numeric;
  v_req_id     uuid;
  v_req_name   text;
  v_req_emp    uuid;
  v_id         uuid;
  v_ex_name    text;
  v_ex_code    text;
  v_co_name    text;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_kind not in ('transfer', 'buy') then
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;
  if length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception 'cancel_reason_required' using errcode = 'P0001';
  end if;

  -- the password under the shared lock (0094): parallel tries could beat
  -- the 5-in-15-minutes limit of the old inline check
  v_err := _admin_password_error(v_admin, p_password);
  if v_err is not null then
    return v_err;
  end if;
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_admin_name
    from auth.users u where u.id = v_admin;

  -- The operation, locked.
  if p_kind = 'transfer' then
    select * into v_t from transfers
     where id = p_operation_id and owner_id = v_admin
       for update;
    if not found then
      raise exception 'cancel_not_found' using errcode = 'P0001';
    end if;
    if v_t.status <> 'archived' then
      raise exception 'cancel_not_cancellable' using errcode = 'P0001';
    end if;
    if v_t.cancelled_at is not null then
      raise exception 'cancel_already' using errcode = 'P0001';
    end if;
    v_company := v_t.company_id;  v_exchange := v_t.exchange_id;
    v_amount  := v_t.amount;      v_ref      := v_t.reference;
    v_party   := v_t.beneficiary_name;
    v_at      := v_t.created_at;  v_emp      := v_t.created_by_employee_id;
    v_book    := _book_of(v_t.book, null);
  else
    select * into v_b from currency_buys
     where id = p_operation_id and owner_id = v_admin
       for update;
    if not found then
      raise exception 'cancel_not_found' using errcode = 'P0001';
    end if;
    if v_b.status <> 'archived' then
      raise exception 'cancel_not_cancellable' using errcode = 'P0001';
    end if;
    if v_b.cancelled_at is not null then
      raise exception 'cancel_already' using errcode = 'P0001';
    end if;
    v_company := v_b.my_company_id;  v_exchange := v_b.exchange_id;
    v_amount  := v_b.usd_amount;     v_ref      := v_b.reference;
    select coalesce(c.name, v_b.client_from_account) into v_party
      from (select 1) x left join clients c on c.id = v_b.client_id;
    v_at      := v_b.created_at;     v_emp      := v_b.created_by_employee_id;
    v_book    := _book_of(v_b.book, null);
  end if;

  if _ops_day(v_at) <> _ops_day(now()) then
    raise exception 'cancel_day_passed' using errcode = 'P0001';
  end if;

  -- The reversing entry, on the locked account and its book.
  select balance, name, our_code into v_before, v_ex_name, v_ex_code
    from exchanges where id = v_exchange for update;
  select balance into v_in_book from account_books
   where exchange_id = v_exchange and book = v_book for update;
  if p_kind = 'transfer' then
    v_after := v_before + v_amount;
  else
    v_after := v_before - v_amount;
    if v_after < 0 or coalesce(v_in_book, 0) < v_amount then
      raise exception 'cancel_insufficient_balance' using errcode = 'P0001',
        detail = format('balance %s, book %s: %s, entry %s',
                        v_before, v_book, coalesce(v_in_book, 0), v_amount);
    end if;
  end if;
  -- (0094) the customer, then the dinar treasury, in the order the saves
  -- lock them: a dinar count or a payment running at this moment waits for
  -- the cancellation instead of counting the operation twice
  if p_kind = 'transfer' and v_t.customer_id is not null then
    perform 1 from clients where id = v_t.customer_id for update;
  elsif p_kind = 'buy' and v_b.client_id is not null then
    perform 1 from clients where id = v_b.client_id for update;
  end if;
  if coalesce(case p_kind when 'transfer' then v_t.lyd_paid else v_b.lyd_paid end, 0) > 0 then
    perform 1 from lyd_treasury where owner_id = v_admin for share;
  end if;

  update account_books
     set balance = balance + case when p_kind = 'transfer' then v_amount else -v_amount end,
         updated_at = now()
   where exchange_id = v_exchange and book = v_book;
  update exchanges set balance = v_after where id = v_exchange;

  if p_kind = 'transfer' then
    update transfers set cancelled_at = now() where id = p_operation_id;
  else
    update currency_buys set cancelled_at = now() where id = p_operation_id;
  end if;

  -- The request(s) for it, approved.
  if p_request_id is not null and not exists (
    select 1 from cancellation_requests
     where id = p_request_id and owner_id = v_admin
       and operation_id = p_operation_id and status = 'pending'
  ) then
    raise exception 'cancel_request_not_found' using errcode = 'P0001';
  end if;
  update cancellation_requests
     set status = 'approved', decided_at = now()
   where operation_id = p_operation_id and status = 'pending'
  returning id, employee_name, sub_user_id into v_req_id, v_req_name, v_req_emp;

  select name into v_co_name from companies where id = v_company;
  if v_emp is not null then
    select employee_name into v_emp_name from sub_users where id = v_emp;
  end if;

  insert into operation_cancellations (
    owner_id, kind, operation_id, company_id, exchange_id, company_name,
    exchange_name, exchange_code, amount, reference, party_name,
    operation_created_at, operation_employee_id, operation_employee_name,
    request_id, requested_by_name, reason, balance_before, balance_after,
    cancelled_by, cancelled_by_name
  ) values (
    v_admin, p_kind, p_operation_id, v_company, v_exchange, v_co_name,
    v_ex_name, v_ex_code, v_amount, v_ref, v_party,
    v_at, v_emp, case when v_emp is null then 'المدير' else coalesce(v_emp_name, '—') end,
    v_req_id, v_req_name, v_reason, v_before, v_after,
    v_admin, v_admin_name
  )
  returning id into v_id;

  -- Tell the employee whose operation it was.
  if v_emp is not null then
    insert into employee_messages (owner_id, sub_user_id, broadcast_id, title, body)
    values (
      v_admin, v_emp, gen_random_uuid(), 'تم إلغاء عملية',
      format(E'تم إلغاء عملية "%s" بقيمة %s$\nالسبب: %s',
             case p_kind when 'transfer' then 'بيع' else 'شراء' end,
             to_char(v_amount, 'FM999G999G990D00'), v_reason)
    );
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'balance_after', v_after);
end;
$$;
revoke all on function admin_cancel_operation(text, uuid, text, text, uuid) from public, anon;
grant execute on function admin_cancel_operation(text, uuid, text, text, uuid) to authenticated;

create or replace function admin_cancel_expense(
  p_expense_id uuid,
  p_reason     text,
  p_password   text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin      uuid := auth.uid();
  v_reason     text := btrim(coalesce(p_reason, ''));
  v_hash       text;
  v_admin_name text;
  v_fails      integer;
  v_err        jsonb;
  v_x          account_expenses;
  v_before     numeric;
  v_after      numeric;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception 'cancel_reason_required' using errcode = 'P0001';
  end if;

  -- the password under the shared lock (0094): parallel tries could beat
  -- the 5-in-15-minutes limit of the old inline check
  v_err := _admin_password_error(v_admin, p_password);
  if v_err is not null then
    return v_err;
  end if;
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_admin_name
    from auth.users u where u.id = v_admin;

  select * into v_x from account_expenses
   where id = p_expense_id and owner_id = v_admin
     for update;
  if not found then
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;
  if v_x.cancelled_at is not null then
    raise exception 'cancel_already' using errcode = 'P0001';
  end if;
  if _ops_day(v_x.created_at) <> _ops_day(now()) then
    raise exception 'cancel_day_passed' using errcode = 'P0001';
  end if;

  select balance into v_before from exchanges where id = v_x.exchange_id for update;
  v_after := v_before + v_x.amount;
  update account_books set balance = balance + v_x.amount, updated_at = now()
   where exchange_id = v_x.exchange_id and book = _book_of(v_x.book, null);
  update exchanges set balance = v_after where id = v_x.exchange_id;

  update account_expenses
     set cancelled_at = now(),
         cancelled_by_name = coalesce(v_admin_name, 'المدير'),
         cancel_reason = v_reason
   where id = p_expense_id;

  return jsonb_build_object('ok', true, 'id', p_expense_id, 'balance_after', v_after);
end;
$$;
revoke all on function admin_cancel_expense(uuid, text, text) from public, anon;
grant execute on function admin_cancel_expense(uuid, text, text) to authenticated;

-- =============================================================================
-- 4) the purchase (copied from 0093): a retry is answered before the rate
-- =============================================================================
create or replace function record_currency_buy(
  p_my_company_id uuid, p_exchange_id uuid, p_client_id uuid,
  p_client_from_account text, p_usd_amount numeric, p_rate numeric,
  p_lyd_amount numeric, p_reference text default '',
  p_lyd_method text default null,
  p_request_id uuid default null,
  p_lyd_paid numeric default null,
  p_book text default null
)
returns currency_buys
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  -- an older build names no book: how it was paid says it
  v_book        text := coalesce(p_book, p_lyd_method, 'bank');
  v_rate        numeric;
  v_total       numeric;
  v_in_book     numeric;
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
  if v_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;

  p_usd_amount := round(p_usd_amount, 2);

  select balance into v_total from exchanges where id = p_exchange_id for update;

  -- the same request again, BEFORE the rate (0094): a retry of a saved
  -- purchase must return it even if the last rate changed meanwhile; the
  -- account lock makes a retry wait for the first
  if p_request_id is not null then
    select * into v_inserted from currency_buys
     where owner_id = v_admin_id and request_id = p_request_id;
    if found then
      return v_inserted;
    end if;
  end if;

  v_rate := _operation_rate(
    'buy_' || v_book,
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

  -- the book: its dollars before this purchase average its cost
  select balance into v_in_book from account_books
   where exchange_id = p_exchange_id and book = v_book for update;

  -- the seller, locked before the treasury (the order customer_add_entry uses)
  if p_client_id is not null then
    perform 1 from clients where id = p_client_id for update;
  end if;
  if v_paid > 0 then
    perform 1 from lyd_treasury where owner_id = v_admin_id for share;
  end if;

  select c.cost_before, c.cost_after into v_cost_before, v_cost_after
    from _apply_buy_cost(v_admin_id, p_exchange_id, v_book, coalesce(v_in_book, 0),
                         p_usd_amount, v_rate, v_id) c;

  insert into currency_buys (
    id, owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id, lyd_method, request_id, lyd_paid, book
  ) values (
    v_id, v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, v_lyd, 'archived', now(), p_reference,
    v_employee_id,
    -- the paid part goes through the book's pocket
    case when v_rate is null or v_paid = 0 then null else v_book end,
    p_request_id, v_paid, v_book
  )
  returning * into v_inserted;

  if v_unpaid > 0 then
    insert into customer_lyd_entries (owner_id, client_id, kind, amount,
                                      operation_id, created_by_employee_id, book)
    values (v_admin_id, p_client_id, 'buy', -v_unpaid, v_id, v_employee_id, v_book);
  end if;

  update account_books set balance = balance + p_usd_amount, updated_at = now()
   where exchange_id = p_exchange_id and book = v_book;
  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;
revoke all on function record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid, numeric, text) from public, anon;
grant execute on function record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid, numeric, text) to authenticated;

-- =============================================================================
-- 8) the sale (copied from 0093): one credit limit over both books
-- =============================================================================
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
  p_over_limit                    boolean default false,
  p_book                          text default null
)
returns transfers
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  -- an older build names no book: how it was paid says it
  v_book        text := coalesce(p_book, p_lyd_method, 'bank');
  v_rate        numeric;
  v_cost        numeric;
  v_ref         text;
  v_lyd         numeric;
  v_paid        numeric;
  v_unpaid      numeric := 0;
  v_limit       numeric;
  v_owed        numeric;
  v_total       numeric;
  v_in_book     numeric;
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
  if v_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
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
  v_rate := _operation_rate('sell_' || v_book, p_rate);
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

  -- the account, then its book: only the dollars of THIS book are sold
  select balance into v_total from exchanges where id = p_exchange_id for update;
  select balance, cost_rate into v_in_book, v_cost from account_books
   where exchange_id = p_exchange_id and book = v_book for update;
  if coalesce(v_in_book, 0) < p_amount and v_total >= p_amount then
    raise exception 'book_insufficient' using errcode = 'P0001',
      detail = format('book %s: %s, requested %s', v_book, coalesce(v_in_book, 0), p_amount);
  end if;

  -- the customer, locked before the treasury (the order customer_add_entry
  -- uses, so the two never wait for each other), and his limit: ONE limit
  -- over what he owes in both books (0094; it was per book, so a customer
  -- could owe the limit twice)
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
    rate, lyd_amount, lyd_method, request_id, customer_id, lyd_paid, book
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, v_ref, 'archived', now(), v_employee_id,
    v_rate, v_lyd,
    -- the paid part goes through the book's pocket
    case when v_rate is null or v_paid = 0 then null else v_book end,
    p_request_id, p_customer_id, v_paid, v_book
  )
  returning * into v_inserted;

  if v_cost is not null then
    insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                                 cost_before, cost_after, book)
    values (v_inserted.id, 'sell', v_admin_id, p_exchange_id, v_cost, v_cost, v_book);
  end if;

  if v_unpaid > 0 then
    insert into customer_lyd_entries (owner_id, client_id, kind, amount,
                                      operation_id, created_by_employee_id, book)
    values (v_admin_id, p_customer_id, 'sale', v_unpaid, v_inserted.id, v_employee_id, v_book);
  end if;

  update account_books set balance = balance - p_amount, updated_at = now()
   where exchange_id = p_exchange_id and book = v_book;
  update exchanges set balance = balance - p_amount where id = p_exchange_id;

  perform log_employee_activity('transfer_created', v_inserted.id, p_amount);
  return v_inserted;
end;
$$;
revoke all on function record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid, uuid, numeric, boolean, text) from public, anon;
grant execute on function record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid, uuid, numeric, boolean, text) to authenticated;

-- =============================================================================
-- 6) request ids (copied from 0093; the old signatures are dropped so older
--    builds, which name their arguments, reach the new ones)
-- =============================================================================
drop function if exists lyd_add_movement(text, text, numeric, text, numeric);
create or replace function lyd_add_movement(
  p_kind text, p_pocket text, p_amount numeric, p_note text default null,
  p_amount_in numeric default null, p_request_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := _lyd_admin();
  v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_in     numeric := round(p_amount_in, 2);
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
  if v_in is not null and (p_kind in ('in', 'out') or v_in <= 0 or v_in > 999999999999.99) then
    raise exception 'lyd_amount_invalid' using errcode = 'P0001';
  end if;
  perform 1 from lyd_treasury where owner_id = v_admin for update;
  if not found then
    raise exception 'lyd_not_open' using errcode = 'P0001';
  end if;
  -- (0094) the same request again (the network dropped after it was saved)
  if p_request_id is not null and exists (
    select 1 from lyd_movements where owner_id = v_admin and request_id = p_request_id
  ) then
    return jsonb_build_object('ok', true, 'repeat', true);
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
  insert into lyd_movements (owner_id, kind, pocket, amount, note, amount_in, request_id)
  values (v_admin, p_kind,
          case when p_kind in ('in', 'out') then p_pocket end,
          v_amount, nullif(btrim(coalesce(p_note, '')), ''),
          case when v_in <> v_amount then v_in end, p_request_id);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function lyd_add_movement(text, text, numeric, text, numeric, uuid) from public, anon;
grant execute on function lyd_add_movement(text, text, numeric, text, numeric, uuid) to authenticated;

drop function if exists move_between_books(uuid, text, numeric, numeric, text);
create or replace function move_between_books(
  p_exchange_id uuid,
  p_from        text,
  p_usd         numeric,
  p_price       numeric,
  p_note        text default null,
  p_request_id  uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_to    text;
  v_q     numeric := round(coalesce(p_usd, 0), 2);
  v_p     numeric := round(p_price, 4);
  v_from  account_books;
  v_dest  account_books;
  v_new   numeric;
  v_name  text;
  v_id    uuid;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_from is null or p_from not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;
  v_to := case p_from when 'cash' then 'bank' else 'cash' end;
  if v_q <= 0 or v_q > 999999999999.99 then
    raise exception 'book_move_invalid' using errcode = 'P0001';
  end if;
  if p_price is null or p_price <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  if p_price <= 1 or p_price > 100 then
    raise exception 'rate_out_of_range' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_note, '')) > 300 then
    raise exception 'book_move_invalid' using errcode = 'P0001';
  end if;

  perform 1
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  -- (0094) the same request again (the network dropped after it was saved)
  if p_request_id is not null and exists (
    select 1 from book_transfers where owner_id = v_admin and request_id = p_request_id
  ) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  -- both books, always in the same order
  perform 1 from account_books where exchange_id = p_exchange_id order by book for update;
  select * into v_from from account_books where exchange_id = p_exchange_id and book = p_from;
  select * into v_dest from account_books where exchange_id = p_exchange_id and book = v_to;
  if coalesce(v_from.balance, 0) < v_q then
    raise exception 'book_insufficient' using errcode = 'P0001',
      detail = format('book %s: %s, requested %s', p_from, coalesce(v_from.balance, 0), v_q);
  end if;
  -- dollars without a cost cannot be valued on either side
  if v_from.cost_rate is null or (v_dest.balance > 0 and v_dest.cost_rate is null) then
    raise exception 'book_cost_missing' using errcode = 'P0001';
  end if;

  if v_dest.balance <= 0 then
    v_new := round(v_p, 6);               -- an empty book starts again
  else
    v_new := round((v_dest.balance * v_dest.cost_rate + v_q * v_p) / (v_dest.balance + v_q), 6);
  end if;

  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_name from auth.users u where u.id = v_admin;

  update account_books set balance = balance - v_q, updated_at = now()
   where exchange_id = p_exchange_id and book = p_from;
  update account_books set balance = balance + v_q, cost_rate = v_new, updated_at = now()
   where exchange_id = p_exchange_id and book = v_to;

  insert into book_transfers (owner_id, exchange_id, from_book, to_book, usd,
                              from_cost, to_price, note, created_by_name, request_id)
  values (v_admin, p_exchange_id, p_from, v_to, v_q, v_from.cost_rate, v_p,
          nullif(btrim(coalesce(p_note, '')), ''), v_name, p_request_id)
  returning id into v_id;
  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after, book
  ) values (
    v_admin, p_exchange_id, 'move_in', v_id, v_dest.balance, v_dest.cost_rate,
    v_q, v_p, v_dest.balance + v_q, v_new, v_to
  );

  return jsonb_build_object('ok', true, 'id', v_id,
                            'from_balance', v_from.balance - v_q,
                            'to_balance', v_dest.balance + v_q,
                            'to_cost', v_new);
end;
$$;
revoke all on function move_between_books(uuid, text, numeric, numeric, text, uuid) from public, anon;
grant execute on function move_between_books(uuid, text, numeric, numeric, text, uuid) to authenticated;

drop function if exists record_account_expense(uuid, numeric, text, text, text);
create or replace function record_account_expense(
  p_exchange_id uuid,
  p_amount      numeric,
  p_code        text,
  p_note        text,
  p_book        text default null,
  p_request_id  uuid default null
) returns account_expenses
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin      uuid := auth.uid();
  v_amount     numeric := round(coalesce(p_amount, 0), 2);
  v_code       text := nullif(btrim(coalesce(p_code, '')), '');
  v_note       text := btrim(coalesce(p_note, ''));
  v_before     numeric;
  v_book       text;
  v_in_book    numeric;
  v_admin_name text;
  v_row        account_expenses;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if v_amount <= 0 or v_amount > 999999999999.99 then
    raise exception 'expense_amount_invalid' using errcode = 'P0001';
  end if;
  if char_length(v_note) < 1 then
    raise exception 'expense_note_required' using errcode = 'P0001';
  end if;
  if char_length(v_note) > 300 or char_length(coalesce(v_code, '')) > 60 then
    raise exception 'expense_text_too_long' using errcode = 'P0001';
  end if;

  -- the account, locked, and only one of this administrator's; then its book
  select e.balance into v_before
    from exchanges e
    join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'expense_account_not_found' using errcode = 'P0001';
  end if;
  -- (0094) the same request again (the network dropped after it was saved)
  if p_request_id is not null then
    select * into v_row from account_expenses
     where owner_id = v_admin and request_id = p_request_id;
    if found then
      return v_row;
    end if;
  end if;
  v_book := _pick_book(p_exchange_id, p_book);
  select balance into v_in_book from account_books
   where exchange_id = p_exchange_id and book = v_book for update;
  if v_before < v_amount then
    raise exception 'insufficient_balance' using errcode = 'P0001',
      detail = format('balance %s, expense %s', v_before, v_amount);
  end if;
  if coalesce(v_in_book, 0) < v_amount then
    raise exception 'book_insufficient' using errcode = 'P0001',
      detail = format('book %s: %s, expense %s', v_book, coalesce(v_in_book, 0), v_amount);
  end if;

  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_admin_name
    from auth.users u where u.id = v_admin;

  update account_books set balance = balance - v_amount, updated_at = now()
   where exchange_id = p_exchange_id and book = v_book;
  update exchanges set balance = v_before - v_amount where id = p_exchange_id;

  insert into account_expenses (
    owner_id, exchange_id, amount, code, note,
    balance_before, balance_after, created_by_name, book, request_id
  ) values (
    v_admin, p_exchange_id, v_amount, v_code, v_note,
    v_before, v_before - v_amount, coalesce(v_admin_name, 'المدير'), v_book, p_request_id
  )
  returning * into v_row;

  return v_row;
end;
$$;
revoke all on function record_account_expense(uuid, numeric, text, text, text, uuid) from public, anon;
grant execute on function record_account_expense(uuid, numeric, text, text, text, uuid) to authenticated;

-- =============================================================================
-- 1) «رصيد أول المدة»: the first dollars of a book, at their cost
-- =============================================================================
create or replace function admin_set_opening(
  p_exchange_id uuid,
  p_book        text,
  p_usd         numeric,
  p_cost        numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_usd   numeric := round(coalesce(p_usd, 0), 2);
  v_total numeric;
  v_split timestamptz;
  v_book  account_books;
  v_name  text;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_book is null or p_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;
  if v_usd <= 0 or v_usd > 999999999999.99 then
    raise exception 'adjust_amount_invalid' using errcode = 'P0001';
  end if;
  if p_cost is null or p_cost <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  if p_cost <= 1 or p_cost > 100 then
    raise exception 'rate_out_of_range' using errcode = 'P0001';
  end if;

  select e.balance, e.books_split_at into v_total, v_split
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  -- dollars from before 0093 are all in the bank book until they are split:
  -- an opening on top would count them twice
  if v_split is null and v_total <> 0 then
    raise exception 'books_not_split' using errcode = 'P0001';
  end if;
  select * into v_book from account_books
   where exchange_id = p_exchange_id and book = p_book for update;
  -- only a book that never moved: its opening is the first thing in it
  if not found or v_book.balance <> 0 or v_book.cost_rate is not null
     or exists (select 1 from transfers
                 where exchange_id = p_exchange_id and coalesce(book, 'bank') = p_book)
     or exists (select 1 from currency_buys
                 where exchange_id = p_exchange_id and coalesce(book, 'bank') = p_book)
     or exists (select 1 from account_expenses
                 where exchange_id = p_exchange_id and coalesce(book, 'bank') = p_book)
     or exists (select 1 from balance_adjustments
                 where exchange_id = p_exchange_id and coalesce(book, 'bank') = p_book)
     or exists (select 1 from account_cost_events
                 where exchange_id = p_exchange_id and coalesce(book, 'bank') = p_book)
     or exists (select 1 from book_transfers
                 where exchange_id = p_exchange_id and p_book in (from_book, to_book)) then
    raise exception 'opening_already_set' using errcode = 'P0001';
  end if;

  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_name from auth.users u where u.id = v_admin;

  -- the book first, then the account (the books trigger then has nothing to do)
  update account_books set balance = v_usd, updated_at = now()
   where exchange_id = p_exchange_id and book = p_book;
  update exchanges
     set balance = v_total + v_usd,
         books_split_at = coalesce(books_split_at, now())
   where id = p_exchange_id;
  insert into balance_adjustments (
    owner_id, exchange_id, balance_before, balance_after, delta, reason,
    adjusted_by_name, kind, book
  ) values (
    v_admin, p_exchange_id, v_total, v_total + v_usd, v_usd, 'رصيد أول المدة',
    v_name, 'opening', p_book
  );
  -- its cost: the 'opening' cost event, as an account opened with a balance
  perform set_account_cost(p_exchange_id, p_cost, p_book);
  return jsonb_build_object('ok', true, 'book', p_book, 'balance', v_usd,
                            'cost_rate', round(p_cost, 6), 'account_balance', v_total + v_usd);
end;
$$;
revoke all on function admin_set_opening(uuid, text, numeric, numeric) from public, anon;
grant execute on function admin_set_opening(uuid, text, numeric, numeric) to authenticated;

commit;
