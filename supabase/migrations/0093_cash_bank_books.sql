-- 0093_cash_bank_books.sql
-- Phase 2 of docs/accounting-audit-and-plan.md, part 3: the CASH and BANK
-- books (asked for by the owner on 2026-10-29).
--
-- In Libya the dinar is two currencies in practice: cash dinars (scarce
-- notes) and bank dinars (cheques, transfers), and the dollar has a price in
-- each. So every account now keeps two books:
--
--  * account_books (exchange, book): the dollars of that book and their
--    weighted-average cost IN THAT BOOK'S DINARS. Always
--      balance(cash) + balance(bank) = exchanges.balance
--    (every function that moves a balance moves the book first; a trigger
--    keeps a direct edit by the platform in step).
--  * A sale / purchase belongs to ONE book (book = cash / bank). A sale larger
--    than its book's dollars is refused (book_insufficient), even when the
--    other book holds dollars: the administrator moves dollars between the
--    books himself (move_between_books, at a price he types; the difference is
--    its own result, account 4500).
--  * The dinars of a sale / purchase always go through the book's pocket: a
--    cash-book operation is paid in the box, a bank-book one through the bank.
--  * The last rates: sell_cash, sell_bank, buy_cash, buy_bank.
--  * The customers' dinar accounts are per book (a credit limit applies to
--    each book apart); collections and payments name the book by the pocket.
--  * Converting dinars between the box and the bank has two amounts (what
--    left, what arrived); the difference is a result (account 4400).
--  * The ledger: every line carries its book; 3300 «تحويلات بين الدفترين»
--    clears what crosses from one book to the other. Statements per book, or
--    combined with the bank's lines × a factor the administrator types.
--
-- Existing data: every account's dollars and cost go into its BANK book (the
-- cash book starts empty); the administrator splits them once per account
-- (set_account_books). Rows saved before this file have book = null: their
-- dollars are the bank book's (where they were put), their dinars and their
-- result follow _book_of(book, lyd_method) = coalesce(book, lyd_method, 'bank').
-- The customers' lines saved before it get their book here (and in every
-- restore): a collection / payment its pocket's, a sale / purchase (and its
-- cancel) its operation's, an opening the bank's.
-- account_costs (0082) is kept, read-only for older builds: it follows the
-- account's average over both books.
--
-- Results in mixed units: 4400 (a dinar conversion) and 4500 (a move between
-- the books) are booked in the book the money left, at face value; in the
-- combined view (bank lines × the factor) the rest of the difference sits in
-- 3300, which is then not zero.
--
-- Going live (the new build fails against 0092; an older build paying in cash
-- fails against an account not split yet):
--   1. at the end of the day, take a backup, then apply 0093;
--   2. the administrator splits every account at once in the new build
--      (set_account_books works only while the cash book is untouched);
--   3. save one sale and one purchase in each book, so the four last rates
--      are real ones;
--   4. publish the new APK right after.
--
-- Older app builds keep working: every new argument has a default and a save
-- without p_book takes coalesce(p_lyd_method, 'bank').
-- Administrator only (the books, costs and statements). Needs 0092. Safe to
-- run more than once.

begin;

do $$
begin
  if to_regclass('public.period_closes') is null
     or to_regprocedure('public._journal(uuid)') is null then
    raise exception 'شغّل الترحيل 0092 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
  -- run again after 0094 it would bring back the cancellations without the
  -- shared password lock and the money moves without their request ids
  if to_regprocedure('public.admin_set_opening(uuid, text, numeric, numeric)') is not null then
    raise exception 'هذا الملف (0093) طُبِّق سابقًا وتبعه 0094. لا تشغّله مرة أخرى. لم يتغير شيء.';
  end if;
end $$;

-- =============================================================================
-- A) the book of every operation, the books of every account
-- =============================================================================
-- null = saved before this file (see _book_of)
do $$
declare
  t text;
begin
  foreach t in array array['transfers', 'currency_buys', 'account_expenses',
                           'balance_adjustments', 'customer_lyd_entries',
                           'account_cost_events', 'operation_costs'] loop
    execute format('alter table %I add column if not exists book text', t);
    execute format('alter table %I drop constraint if exists %I', t, t || '_book_check');
    execute format('alter table %I add constraint %I check (book is null or book in (''cash'', ''bank''))',
                   t, t || '_book_check');
  end loop;
end $$;

-- the book of a row: its own, else (saved before 0093) how its dinars were
-- paid, else the bank. The DOLLARS of a row saved before 0093 are always the
-- bank book's: _book_of(book, null).
create or replace function _book_of(p_book text, p_method text)
returns text
language sql
immutable
as $$
  select coalesce(p_book, p_method, 'bank')
$$;
revoke all on function _book_of(text, text) from public, anon, authenticated;

-- the customers' lines saved before 0093 get their book, so a debt stays in
-- the book its dinars belong to: a collection / payment its pocket's, a sale /
-- purchase and its cancel the book of its operation (how it was paid), an
-- opening the bank's. Run here and after every restore ([p_owner] null: all).
create or replace function _customer_entry_books(p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_n integer;
begin
  update customer_lyd_entries e
     set book = coalesce(
           case when e.kind in ('collect', 'pay') then e.pocket end,
           case when e.kind in ('sale', 'sale_cancel') then
             (select _book_of(t.book, t.lyd_method) from transfers t where t.id = e.operation_id) end,
           case when e.kind in ('buy', 'buy_cancel') then
             (select _book_of(b.book, b.lyd_method) from currency_buys b where b.id = e.operation_id) end,
           'bank')
   where e.book is null
     and (p_owner is null or e.owner_id = p_owner);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function _customer_entry_books(uuid) from public, anon, authenticated;
select _customer_entry_books(null);

-- an account opened from now on has nothing to split
alter table exchanges add column if not exists books_split_at timestamptz;

create table if not exists account_books (
  exchange_id uuid not null references exchanges (id) on delete cascade,
  book        text not null check (book in ('cash', 'bank')),
  owner_id    uuid not null references profiles (id) on delete cascade,
  balance     numeric(14,2) not null default 0,
  cost_rate   numeric(16,6) check (cost_rate is null or cost_rate > 0),
  updated_at  timestamptz not null default now(),
  primary key (exchange_id, book)
);
create index if not exists account_books_owner_idx on account_books (owner_id);
alter table account_books enable row level security;
revoke all on table account_books from anon, authenticated;
grant select on table account_books to authenticated;
drop policy if exists account_books_admin on account_books;
create policy account_books_admin on account_books
  for select to authenticated
  using (owner_id = (select auth.uid()) and (select current_employee_id()) is null);

-- every account's dollars and cost go into its bank book; the cash book
-- starts empty (an account below zero from before 0089 keeps that balance)
insert into account_books (exchange_id, book, owner_id, balance, cost_rate)
select e.id, b.book, c.owner_id,
       case b.book when 'bank' then e.balance else 0 end,
       case b.book when 'bank' then ac.cost_rate end
  from exchanges e
  join companies c on c.id = e.company_id
  cross join (values ('cash'), ('bank')) b(book)
  left join account_costs ac on ac.exchange_id = e.id
on conflict (exchange_id, book) do nothing;

-- dollars moved from one book of an account to the other
create table if not exists book_transfers (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references profiles (id) on delete cascade,
  exchange_id     uuid not null references exchanges (id) on delete cascade,
  from_book       text not null check (from_book in ('cash', 'bank')),
  to_book         text not null check (to_book in ('cash', 'bank')),
  usd             numeric(14,2) not null check (usd > 0),
  from_cost       numeric(16,6) not null,        -- the cost they left at
  to_price        numeric(10,4) not null,        -- the price they came in at
  note            text check (note is null or char_length(note) <= 300),
  created_by_name text,
  created_at      timestamptz not null default now(),
  check (from_book <> to_book)
);
create index if not exists book_transfers_exchange_idx on book_transfers (exchange_id, created_at);
create index if not exists book_transfers_owner_idx on book_transfers (owner_id, created_at);
alter table book_transfers enable row level security;
revoke all on table book_transfers from anon, authenticated;
grant select on table book_transfers to authenticated;
drop policy if exists book_transfers_admin on book_transfers;
create policy book_transfers_admin on book_transfers
  for select to authenticated
  using (owner_id = (select auth.uid()) and (select current_employee_id()) is null);

-- a conversion between the box and the bank: what arrived (null = the same)
alter table lyd_movements add column if not exists amount_in numeric(14,2);
alter table lyd_movements drop constraint if exists lyd_movements_amount_in_check;
alter table lyd_movements add constraint lyd_movements_amount_in_check
  check (amount_in is null or (amount_in > 0 and kind in ('cash_to_bank', 'bank_to_cash')));

-- the last rates, per book: the old one goes to both books
alter table last_exchange_rates drop constraint if exists last_exchange_rates_kind_check;
insert into last_exchange_rates (owner_id, kind, rate, updated_at)
select r.owner_id, r.kind || s.suffix, r.rate, r.updated_at
  from last_exchange_rates r
  cross join (values ('_cash'), ('_bank')) s(suffix)
 where r.kind in ('sell', 'buy')
on conflict (owner_id, kind) do nothing;
delete from last_exchange_rates where kind in ('sell', 'buy');
alter table last_exchange_rates add constraint last_exchange_rates_kind_check
  check (kind in ('sell_cash', 'sell_bank', 'buy_cash', 'buy_bank'));

-- the record of cost changes knows a move between the books (every earlier
-- value kept)
alter table account_cost_events drop constraint if exists account_cost_events_kind_check;
alter table account_cost_events add constraint account_cost_events_kind_check
  check (kind in ('opening', 'correction', 'buy', 'buy_cancel', 'sell_cancel', 'move_in'));
create index if not exists account_cost_events_book_idx
  on account_cost_events (exchange_id, book, created_at);

-- =============================================================================
-- B) the books stay in step with the account
-- =============================================================================
-- a new account: born split (nothing to split), its two books created
create or replace function _account_books_born()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if coalesce(current_setting('eshary.restoring', true), '') = 'on' then
    return new;                           -- a restore brings its own books
  end if;
  if tg_op = 'INSERT' and tg_when = 'BEFORE' then
    new.books_split_at := coalesce(new.books_split_at, now());
    return new;
  end if;
  insert into account_books (exchange_id, book, owner_id, balance)
  select new.id, b.book, c.owner_id, case b.book when 'bank' then new.balance else 0 end
    from companies c cross join (values ('cash'), ('bank')) b(book)
   where c.id = new.company_id
  on conflict (exchange_id, book) do nothing;
  return new;
end;
$$;
revoke all on function _account_books_born() from public, anon, authenticated;
drop trigger if exists trg_account_books_born_before on exchanges;
create trigger trg_account_books_born_before
  before insert on exchanges
  for each row execute function _account_books_born();
drop trigger if exists trg_account_books_born on exchanges;
create trigger trg_account_books_born
  after insert on exchanges
  for each row execute function _account_books_born();

-- whether an account was split changes only inside the database's functions
-- (the app's update of an account cannot clear it)
create or replace function _block_direct_split_edit()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon')
     and new.books_split_at is distinct from old.books_split_at then
    raise exception 'balance_direct_edit' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_block_direct_split_edit on exchanges;
create trigger trg_block_direct_split_edit
  before update of books_split_at on exchanges
  for each row execute function _block_direct_split_edit();

-- The database's functions move the book first, then the account: nothing to
-- do. A balance changed any other way (the platform's own maintenance) is
-- carried into the books: an increase into the bank book, a decrease out of
-- the bank book first, then the cash book.
create or replace function _books_follow_balance()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_sum  numeric;
  v_diff numeric;
  v_bank numeric;
  v_take numeric;
begin
  if not exists (select 1 from account_books where exchange_id = new.id) then
    insert into account_books (exchange_id, book, owner_id, balance)
    select new.id, b.book, c.owner_id, case b.book when 'bank' then new.balance else 0 end
      from companies c cross join (values ('cash'), ('bank')) b(book)
     where c.id = new.company_id
    on conflict (exchange_id, book) do nothing;
    return null;
  end if;
  select coalesce(sum(balance), 0) into v_sum from account_books where exchange_id = new.id;
  v_diff := new.balance - v_sum;
  if v_diff = 0 then
    return null;
  end if;
  if v_diff > 0 then
    update account_books set balance = balance + v_diff, updated_at = now()
     where exchange_id = new.id and book = 'bank';
    return null;
  end if;
  select balance into v_bank from account_books
   where exchange_id = new.id and book = 'bank' for update;
  v_take := least(-v_diff, greatest(coalesce(v_bank, 0), 0));
  if v_take > 0 then
    update account_books set balance = balance - v_take, updated_at = now()
     where exchange_id = new.id and book = 'bank';
  end if;
  if -v_diff - v_take > 0 then
    update account_books set balance = balance - (-v_diff - v_take), updated_at = now()
     where exchange_id = new.id and book = 'cash';
  end if;
  return null;
end;
$$;
revoke all on function _books_follow_balance() from public, anon, authenticated;
drop trigger if exists trg_books_follow_balance on exchanges;
create trigger trg_books_follow_balance
  after update of balance on exchanges
  for each row
  when (new.balance is distinct from old.balance)
  execute function _books_follow_balance();

-- a book never goes below zero (one already below it from before 0089 may come
-- back up); a restore puts back what was there
create or replace function _book_not_negative()
returns trigger
language plpgsql
as $$
begin
  if new.balance < 0
     and (tg_op = 'INSERT' or new.balance < old.balance)
     and coalesce(current_setting('eshary.restoring', true), '') <> 'on' then
    raise exception 'book_insufficient' using errcode = 'P0001',
      detail = format('book %s: %s', new.book, new.balance);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_book_not_negative on account_books;
create trigger trg_book_not_negative
  before insert or update of balance on account_books
  for each row execute function _book_not_negative();

-- account_costs (0082) for older builds and reads: the account's average over
-- both books (only what holds a cost counts). Never written by a restore,
-- which brings its own.
create or replace function _sync_account_cost()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_val  numeric;
  v_qty  numeric;
  v_cost numeric;
begin
  if coalesce(current_setting('eshary.restoring', true), '') = 'on' then
    return null;
  end if;
  select sum(b.balance * b.cost_rate), sum(b.balance) into v_val, v_qty
    from account_books b
   where b.exchange_id = new.exchange_id and b.balance > 0 and b.cost_rate is not null;
  if v_qty > 0 then
    v_cost := round(v_val / v_qty, 6);
  elsif not exists (select 1 from account_costs where exchange_id = new.exchange_id) then
    select b.cost_rate into v_cost from account_books b
     where b.exchange_id = new.exchange_id and b.cost_rate is not null
     order by b.book limit 1;              -- 'bank' first
  end if;
  if v_cost is null then
    return null;
  end if;
  insert into account_costs (exchange_id, owner_id, cost_rate, updated_at)
  values (new.exchange_id, new.owner_id, v_cost, now())
  on conflict (exchange_id)
    do update set cost_rate = excluded.cost_rate, updated_at = excluded.updated_at
     where account_costs.cost_rate is distinct from excluded.cost_rate;
  return null;
end;
$$;
revoke all on function _sync_account_cost() from public, anon, authenticated;
drop trigger if exists trg_sync_account_cost on account_books;
create trigger trg_sync_account_cost
  after insert or update of balance, cost_rate on account_books
  for each row execute function _sync_account_cost();

-- an account with book moves has a history (copied from 0087)
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
              or exists (select 1 from balance_adjustments a where a.exchange_id = e.id)
              or exists (select 1 from book_transfers m where m.exchange_id = e.id))
    ) then
      raise exception 'account_has_history' using errcode = 'P0001';
    end if;
    return old;
  end if;
  if old.balance <> 0
     or exists (select 1 from account_expenses x where x.exchange_id = old.id)
     or exists (select 1 from balance_adjustments a where a.exchange_id = old.id)
     or exists (select 1 from book_transfers m where m.exchange_id = old.id) then
    raise exception 'account_has_history' using errcode = 'P0001';
  end if;
  return old;
end;
$$;

-- the book a caller named, or (none named) the one that holds all the dollars
-- of the account; both hold some: book_required (internal)
create or replace function _pick_book(p_exchange_id uuid, p_book text)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_cash numeric;
  v_bank numeric;
begin
  if p_book is not null then
    if p_book not in ('cash', 'bank') then
      raise exception 'book_invalid' using errcode = 'P0001';
    end if;
    return p_book;
  end if;
  select coalesce(sum(balance) filter (where book = 'cash'), 0),
         coalesce(sum(balance) filter (where book = 'bank'), 0)
    into v_cash, v_bank
    from account_books where exchange_id = p_exchange_id;
  if v_cash <> 0 and v_bank <> 0 then
    raise exception 'book_required' using errcode = 'P0001';
  end if;
  return case when v_cash <> 0 then 'cash' else 'bank' end;
end;
$$;
revoke all on function _pick_book(uuid, text) from public, anon, authenticated;

-- =============================================================================
-- C) the rate of each kind AND book (copied from 0087)
-- =============================================================================
-- p_kind: sell_cash / sell_bank / buy_cash / buy_bank (a bare sell / buy is
-- the cash book's)
create or replace function _operation_rate(p_kind text, p_rate numeric)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_kind  text := case p_kind when 'sell' then 'sell_cash' when 'buy' then 'buy_cash' else p_kind end;
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
     where owner_id = v_admin and kind = v_kind;
    if not employee_has_perm(
         case when v_kind like 'sell%' then 'rate_edit_sell' else 'rate_edit_buy' end
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
    values (v_admin, v_kind, p_rate, now())
    on conflict (owner_id, kind)
      do update set rate = excluded.rate, updated_at = excluded.updated_at;
  end if;
  return round(p_rate, 4);
end;
$$;
revoke all on function _operation_rate(text, numeric) from public, anon, authenticated;

-- the four last rates; sell / buy (= the cash book's) stay for older builds
create or replace function current_exchange_rates()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_emp   boolean := current_employee_id() is not null;
  v_sell  boolean;
  v_buy   boolean;
  v_r     jsonb;
begin
  if v_admin is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  v_sell := not v_emp or employee_has_perm('rate_edit_sell');
  v_buy  := not v_emp or employee_has_perm('rate_edit_buy');
  select coalesce(jsonb_object_agg(kind, rate), '{}'::jsonb) into v_r
    from last_exchange_rates where owner_id = v_admin;
  return jsonb_build_object(
    'sell_cash', v_r -> 'sell_cash',
    'sell_bank', v_r -> 'sell_bank',
    'buy_cash',  v_r -> 'buy_cash',
    'buy_bank',  v_r -> 'buy_bank',
    'sell',      v_r -> 'sell_cash',
    'buy',       v_r -> 'buy_cash',
    'can_edit_sell', v_sell,
    'can_edit_buy',  v_buy,
    'can_edit',      v_sell and v_buy
  );
end;
$$;
revoke all on function current_exchange_rates() from public, anon;
grant execute on function current_exchange_rates() to authenticated;

-- =============================================================================
-- D) the cost, per book (copied from 0084)
-- =============================================================================
-- the cost of [p_book] of an account at moment [p_at] (the last change of
-- that book at or before it; a change saved before 0093 is the bank book's)
drop function if exists _cost_at(uuid, timestamptz);
create or replace function _cost_at(p_exchange_id uuid, p_book text, p_at timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public, extensions
as $$
  select cost_after from account_cost_events
   where exchange_id = p_exchange_id and coalesce(book, 'bank') = p_book
     and created_at <= p_at
   order by created_at desc, id desc
   limit 1
$$;
revoke all on function _cost_at(uuid, text, timestamptz) from public, anon, authenticated;

-- a purchase moves the cost of its book: C' = (B×C + q×r) ÷ (B+q), B = the
-- book's dollars before it (locked by the caller)
drop function if exists _apply_buy_cost(uuid, uuid, numeric, numeric, numeric, uuid);
create or replace function _apply_buy_cost(
  p_owner          uuid,
  p_exchange_id    uuid,
  p_book           text,
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
  select b.cost_rate into cost_before
    from account_books b
   where b.exchange_id = p_exchange_id and b.book = p_book
     for update;

  if p_rate is null then
    cost_after := cost_before;            -- in at cost
    return;
  end if;
  if p_balance_before <= 0 then
    cost_after := round(p_rate, 6);       -- an empty book starts again
  elsif cost_before is null then
    cost_after := null;                   -- no opening cost yet: not tracked
    return;
  else
    cost_after := round(
      (p_balance_before * cost_before + v_q * p_rate) / (p_balance_before + v_q),
      6
    );
  end if;

  update account_books set cost_rate = cost_after, updated_at = now()
   where exchange_id = p_exchange_id and book = p_book;

  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after, book
  ) values (
    p_owner, p_exchange_id, 'buy', p_operation_id, p_balance_before, cost_before,
    v_q, p_rate, p_balance_before + v_q, cost_after, p_book
  );
  insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                               cost_before, cost_after, book)
  values (p_operation_id, 'buy', p_owner, p_exchange_id, cost_before, cost_after, p_book)
  on conflict (operation_id) do nothing;
end;
$$;
revoke all on function _apply_buy_cost(uuid, uuid, text, numeric, numeric, numeric, uuid)
  from public, anon, authenticated;

-- cancelling a purchase: only one that was costed, and not across a new
-- opening / correction of ITS book. admin_cancel_operation moved the book's
-- balance back before stamping cancelled_at.
create or replace function _cost_on_buy_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_book  text := _book_of(new.book, null);
  v_bal   numeric;
  v_cost  numeric;
  v_q     numeric := round(new.usd_amount, 2);
  v_value numeric;
  v_new   numeric;
begin
  if new.rate is null then
    return new;                           -- it came in at cost
  end if;
  if not exists (select 1 from operation_costs
                  where operation_id = new.id and kind = 'buy') then
    return new;                           -- it never moved the cost
  end if;
  if exists (select 1 from account_cost_events
              where exchange_id = new.exchange_id
                and coalesce(book, 'bank') = v_book
                and kind in ('opening', 'correction')
                and created_at > new.created_at) then
    return new;                           -- the administrator re-set the cost since
  end if;
  select balance, cost_rate into v_bal, v_cost from account_books
   where exchange_id = new.exchange_id and book = v_book for update;
  if v_cost is null then
    return new;
  end if;

  v_value := (v_bal + v_q) * v_cost - v_q * new.rate;
  if v_bal < 1 or v_value <= 0 then
    v_new := v_cost;                      -- nothing meaningful left to average
  else
    v_new := round(v_value / v_bal, 6);
  end if;

  update account_books set cost_rate = v_new, updated_at = now()
   where exchange_id = new.exchange_id and book = v_book;
  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after, book
  ) values (
    new.owner_id, new.exchange_id, 'buy_cancel', new.id, v_bal + v_q, v_cost,
    v_q, new.rate, v_bal, v_new, v_book
  );
  return new;
end;
$$;

-- cancelling a sale: its dollars come back into its book at the cost they
-- left at
create or replace function _cost_on_sell_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_book   text := _book_of(new.book, null);
  v_bal    numeric;
  v_cost   numeric;
  v_exit   numeric;
  v_q      numeric := round(new.amount, 2);
  v_before numeric;
  v_new    numeric;
begin
  select cost_after into v_exit from operation_costs
   where operation_id = new.id and kind = 'sell';
  if v_exit is null then
    return new;                           -- it left without a known cost
  end if;
  if exists (select 1 from account_cost_events
              where exchange_id = new.exchange_id
                and coalesce(book, 'bank') = v_book
                and kind in ('opening', 'correction')
                and created_at > new.created_at) then
    return new;
  end if;
  -- the book's balance is already the one after the cancellation
  select balance, cost_rate into v_bal, v_cost from account_books
   where exchange_id = new.exchange_id and book = v_book for update;
  if v_cost is null or v_bal <= 0 then
    return new;
  end if;

  v_before := v_bal - v_q;
  if v_before < 1 then
    v_new := round(v_exit, 6);            -- only these dollars are left
  else
    v_new := round((v_before * v_cost + v_q * v_exit) / v_bal, 6);
  end if;
  if v_new = v_cost then
    return new;
  end if;

  update account_books set cost_rate = v_new, updated_at = now()
   where exchange_id = new.exchange_id and book = v_book;
  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after, book
  ) values (
    new.owner_id, new.exchange_id, 'sell_cancel', new.id, v_before, v_cost,
    v_q, v_exit, v_bal, v_new, v_book
  );
  return new;
end;
$$;

-- setting / correcting the cost of a book. Without p_book: the book that
-- holds all the dollars (book_required when both hold some).
drop function if exists set_account_cost(uuid, numeric);
create or replace function set_account_cost(
  p_exchange_id uuid,
  p_rate        numeric,
  p_book        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_book  text;
  v_bal   numeric;
  v_old   numeric;
  v_new   numeric := round(p_rate, 6);
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_rate is null or p_rate <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  if p_rate <= 1 or p_rate > 100 then
    raise exception 'rate_out_of_range' using errcode = 'P0001';
  end if;
  perform 1
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_book := _pick_book(p_exchange_id, p_book);
  select balance, cost_rate into v_bal, v_old from account_books
   where exchange_id = p_exchange_id and book = v_book for update;

  update account_books set cost_rate = v_new, updated_at = now()
   where exchange_id = p_exchange_id and book = v_book;
  insert into account_cost_events (
    owner_id, exchange_id, kind, balance_before, cost_before,
    balance_after, cost_after, book
  ) values (
    v_admin, p_exchange_id,
    case when v_old is null then 'opening' else 'correction' end,
    v_bal, v_old, v_bal, v_new, v_book
  );
  return jsonb_build_object('ok', true, 'book', v_book, 'balance', v_bal, 'cost_rate', v_new);
end;
$$;
revoke all on function set_account_cost(uuid, numeric, text) from public, anon;
grant execute on function set_account_cost(uuid, numeric, text) to authenticated;

-- =============================================================================
-- E) the save functions: the book (copied from 0091)
-- =============================================================================
drop function if exists record_transfer(uuid, uuid, text, text, text, numeric, text, numeric, text, uuid, uuid, numeric, boolean);
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
  -- uses, so the two never wait for each other), and his limit IN THIS BOOK
  if p_customer_id is not null then
    select credit_limit into v_limit from clients where id = p_customer_id for update;
  end if;
  if v_unpaid > 0 then
    v_owed := _customer_balance(p_customer_id, v_book);
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

drop function if exists record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text, text, uuid, numeric);
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

  select balance into v_total from exchanges where id = p_exchange_id for update;

  -- the same request again: the account lock makes a retry wait for the first
  if p_request_id is not null then
    select * into v_inserted from currency_buys
     where owner_id = v_admin_id and request_id = p_request_id;
    if found then
      return v_inserted;
    end if;
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

-- a cancelled operation gives its debt back, in its book (copied from 0091)
create or replace function _customer_debt_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into customer_lyd_entries (owner_id, client_id, kind, amount, operation_id, book)
  select e.owner_id, e.client_id,
         case e.kind when 'sale' then 'sale_cancel' else 'buy_cancel' end,
         -e.amount, e.operation_id, e.book
    from customer_lyd_entries e
   where e.operation_id = new.id and e.kind in ('sale', 'buy');
  return new;
end;
$$;

-- =============================================================================
-- F) cancelling, adjusting, commissions: the operation's book moves too
-- =============================================================================
-- copied from 0090; the book's dollars move back with the account's
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

  -- Lock after 5 wrong passwords in 15 minutes.
  select count(*) into v_fails
    from cancel_auth_failures
   where user_id = v_admin and created_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;

  select u.encrypted_password,
         coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_hash, v_admin_name
    from auth.users u
   where u.id = v_admin;

  if v_hash is null or v_hash = '' then
    return jsonb_build_object('ok', false, 'error', 'password_not_set');
  end if;
  if p_password is null or crypt(p_password, v_hash) <> v_hash then
    insert into cancel_auth_failures (user_id) values (v_admin);
    return jsonb_build_object(
      'ok', false, 'error', 'wrong_password', 'remaining', greatest(0, 4 - v_fails)
    );
  end if;
  delete from cancel_auth_failures where user_id = v_admin;

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

-- a balance adjustment: the new balance OF A BOOK (copied from 0086; the
-- password check is 0087's shared one). Without p_book: the book that holds
-- all the dollars (book_required when both hold some). The cost is left alone.
drop function if exists admin_adjust_balance(uuid, numeric, text, text);
create or replace function admin_adjust_balance(
  p_exchange_id  uuid,
  p_new_balance  numeric,
  p_reason       text,
  p_password     text,
  p_book         text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_new    numeric := round(coalesce(p_new_balance, -1), 2);
  v_err    jsonb;
  v_name   text;
  v_book   text;
  v_total  numeric;
  v_before numeric;
  v_delta  numeric;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 500 then
    raise exception 'adjust_reason_required' using errcode = 'P0001';
  end if;
  if v_new < 0 or v_new > 999999999999.99 then
    raise exception 'adjust_amount_invalid' using errcode = 'P0001';
  end if;
  if p_book is not null and p_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;

  -- the password, with the lock the cancellations use (5 wrong in 15 minutes)
  v_err := _admin_password_error(v_admin, p_password);
  if v_err is not null then
    return v_err;
  end if;
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_name
    from auth.users u where u.id = v_admin;

  select e.balance into v_total
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  v_book := _pick_book(p_exchange_id, p_book);
  select balance into v_before from account_books
   where exchange_id = p_exchange_id and book = v_book for update;
  if v_new = v_before then
    raise exception 'adjust_no_change' using errcode = 'P0001';
  end if;
  v_delta := v_new - v_before;

  update account_books set balance = v_new, updated_at = now()
   where exchange_id = p_exchange_id and book = v_book;
  update exchanges set balance = v_total + v_delta where id = p_exchange_id;
  -- the line keeps the ACCOUNT's balance before / after (the statement's)
  insert into balance_adjustments (
    owner_id, exchange_id, balance_before, balance_after, delta, reason,
    adjusted_by_name, kind, book
  ) values (
    v_admin, p_exchange_id, v_total, v_total + v_delta, v_delta, v_reason, v_name,
    'adjust', v_book
  );
  return jsonb_build_object('ok', true, 'book', v_book,
                            'balance_before', v_before, 'balance_after', v_new,
                            'account_balance_before', v_total,
                            'account_balance_after', v_total + v_delta);
end;
$$;
revoke all on function admin_adjust_balance(uuid, numeric, text, text, text) from public, anon;
grant execute on function admin_adjust_balance(uuid, numeric, text, text, text) to authenticated;

-- a commission taken from an account, from a book (copied from 0072).
-- Without p_book: the book that holds all the dollars (book_required when
-- both hold some).
drop function if exists record_account_expense(uuid, numeric, text, text);
create or replace function record_account_expense(
  p_exchange_id uuid,
  p_amount      numeric,
  p_code        text,
  p_note        text,
  p_book        text default null
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
    balance_before, balance_after, created_by_name, book
  ) values (
    v_admin, p_exchange_id, v_amount, v_code, v_note,
    v_before, v_before - v_amount, coalesce(v_admin_name, 'المدير'), v_book
  )
  returning * into v_row;

  return v_row;
end;
$$;
revoke all on function record_account_expense(uuid, numeric, text, text, text) from public, anon;
grant execute on function record_account_expense(uuid, numeric, text, text, text) to authenticated;

-- cancelling a commission: the dollars back into its book (copied from 0072)
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

  select count(*) into v_fails
    from cancel_auth_failures
   where user_id = v_admin and created_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;

  select u.encrypted_password,
         coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_hash, v_admin_name
    from auth.users u where u.id = v_admin;

  if v_hash is null or v_hash = '' then
    return jsonb_build_object('ok', false, 'error', 'password_not_set');
  end if;
  if p_password is null or crypt(p_password, v_hash) <> v_hash then
    insert into cancel_auth_failures (user_id) values (v_admin);
    return jsonb_build_object(
      'ok', false, 'error', 'wrong_password', 'remaining', greatest(0, 4 - v_fails)
    );
  end if;
  delete from cancel_auth_failures where user_id = v_admin;

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
-- G) the books themselves (administrator only)
-- =============================================================================
-- opening an account: its balance and cost go into ONE book (copied from 0087)
drop function if exists admin_open_account(uuid, text, numeric, text, text, numeric);
create or replace function admin_open_account(
  p_company_id uuid,
  p_name       text,
  p_balance    numeric,
  p_our_code   text default null,
  p_country    text default null,
  p_cost_rate  numeric default null,
  p_book       text default 'bank'
)
returns exchanges
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin   uuid := auth.uid();
  v_balance numeric := round(coalesce(p_balance, 0), 2);
  v_book    text := coalesce(p_book, 'bank');
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
  if v_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;
  -- dollars with no dinar cost would stay out of the profit: a cost is required
  if v_balance > 0 and p_cost_rate is null then
    raise exception 'opening_cost_required' using errcode = 'P0001';
  end if;

  -- born split: its two books are created with it (all in the bank book)
  insert into exchanges (company_id, name, balance, our_code, country, books_split_at)
  values (p_company_id, btrim(p_name), v_balance,
          nullif(btrim(coalesce(p_our_code, '')), ''),
          nullif(btrim(coalesce(p_country, '')), ''), now())
  returning * into v_row;
  if v_book = 'cash' and v_balance <> 0 then
    update account_books
       set balance = case book when 'cash' then v_balance else 0 end, updated_at = now()
     where exchange_id = v_row.id;
  end if;

  if v_balance > 0 then
    select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                    nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                    u.email, 'المدير')
      into v_name from auth.users u where u.id = v_admin;
    insert into balance_adjustments (
      owner_id, exchange_id, balance_before, balance_after, delta, reason,
      adjusted_by_name, kind, book
    ) values (
      v_admin, v_row.id, 0, v_balance, v_balance, 'رصيد افتتاحي', v_name, 'opening', v_book
    );
  end if;
  if p_cost_rate is not null then
    perform set_account_cost(v_row.id, p_cost_rate, v_book);
  end if;
  return v_row;
end;
$$;
revoke all on function admin_open_account(uuid, text, numeric, text, text, numeric, text) from public, anon;
grant execute on function admin_open_account(uuid, text, numeric, text, text, numeric, text) to authenticated;

-- the dollars an account held before 0093, split once between the books:
-- [p_cash_qty] into the cash book at [p_cash_cost], the rest into the bank
-- book at [p_bank_cost]. A cost is required for every book with dollars.
-- Both books get an 'opening' cost change (equity: 3100).
create or replace function set_account_books(
  p_exchange_id uuid,
  p_cash_qty    numeric,
  p_cash_cost   numeric,
  p_bank_cost   numeric
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_total numeric;
  v_split timestamptz;
  v_qty   numeric := round(coalesce(p_cash_qty, -1), 2);
  v_cash  account_books;
  v_bank  account_books;
  v_new   numeric;
  v_cost  numeric;
  r       record;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  select e.balance, e.books_split_at into v_total, v_split
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if v_split is not null then
    raise exception 'books_already_split' using errcode = 'P0001';
  end if;
  -- the split is for the dollars held when 0093 came: once the cash book has
  -- been used (a purchase, a move, a cost) it is not overwritten
  if exists (select 1 from account_books
              where exchange_id = p_exchange_id and book = 'cash'
                and (balance <> 0 or cost_rate is not null))
     or exists (select 1 from account_cost_events
                 where exchange_id = p_exchange_id and book = 'cash') then
    raise exception 'books_split_invalid' using errcode = 'P0001',
      detail = 'the cash book is already in use';
  end if;
  if v_qty < 0 or v_qty > greatest(v_total, 0) then
    raise exception 'books_split_invalid' using errcode = 'P0001',
      detail = format('balance %s, cash %s', v_total, v_qty);
  end if;
  if (v_qty > 0 and p_cash_cost is null) or (v_total - v_qty > 0 and p_bank_cost is null) then
    raise exception 'opening_cost_required' using errcode = 'P0001';
  end if;
  if (p_cash_cost is not null and p_cash_cost <= 0) or (p_bank_cost is not null and p_bank_cost <= 0) then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  if (p_cash_cost is not null and (p_cash_cost <= 1 or p_cash_cost > 100))
     or (p_bank_cost is not null and (p_bank_cost <= 1 or p_bank_cost > 100)) then
    raise exception 'rate_out_of_range' using errcode = 'P0001';
  end if;

  select * into v_bank from account_books where exchange_id = p_exchange_id and book = 'bank' for update;
  select * into v_cash from account_books where exchange_id = p_exchange_id and book = 'cash' for update;

  for r in
    select 'cash'::text as book, v_cash.balance as bal_before, v_cash.cost_rate as cost_before,
           v_qty as bal_after, p_cash_cost as typed, p_bank_cost as other
    union all
    select 'bank', v_bank.balance, v_bank.cost_rate, v_total - v_qty, p_bank_cost, p_cash_cost
  loop
    v_new := round(coalesce(r.typed, r.cost_before, r.other), 6);
    continue when r.bal_before = r.bal_after and r.cost_before is not distinct from v_new;
    update account_books set balance = r.bal_after, cost_rate = v_new, updated_at = now()
     where exchange_id = p_exchange_id and book = r.book;
    continue when v_new is null;          -- an empty book that never had a cost
    insert into account_cost_events (
      owner_id, exchange_id, kind, balance_before, cost_before,
      balance_after, cost_after, book
    ) values (
      v_admin, p_exchange_id, 'opening', r.bal_before, r.cost_before,
      r.bal_after, v_new, r.book
    );
  end loop;

  update exchanges set books_split_at = now() where id = p_exchange_id;
  return jsonb_build_object('ok', true,
    'cash', jsonb_build_object('balance', v_qty, 'cost_rate',
              (select cost_rate from account_books where exchange_id = p_exchange_id and book = 'cash')),
    'bank', jsonb_build_object('balance', v_total - v_qty, 'cost_rate',
              (select cost_rate from account_books where exchange_id = p_exchange_id and book = 'bank')));
end;
$$;
revoke all on function set_account_books(uuid, numeric, numeric, numeric) from public, anon;
grant execute on function set_account_books(uuid, numeric, numeric, numeric) to authenticated;

-- dollars moved from one book of an account to the other: they leave [p_from]
-- at its cost and come into the other book at [p_price] (its dinars per
-- dollar), averaging into its cost. The difference is a result (4500).
create or replace function move_between_books(
  p_exchange_id uuid,
  p_from        text,
  p_usd         numeric,
  p_price       numeric,
  p_note        text default null
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
                              from_cost, to_price, note, created_by_name)
  values (v_admin, p_exchange_id, p_from, v_to, v_q, v_from.cost_rate, v_p,
          nullif(btrim(coalesce(p_note, '')), ''), v_name)
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
revoke all on function move_between_books(uuid, text, numeric, numeric, text) from public, anon;
grant execute on function move_between_books(uuid, text, numeric, numeric, text) to authenticated;

-- every account with its two books
create or replace function account_books_list()
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
             'exchange_id', e.id, 'company_name', co.name, 'account_name', e.name,
             'balance', e.balance, 'split', e.books_split_at is not null,
             'split_at', e.books_split_at,
             'cash', jsonb_build_object('balance', coalesce(bc.balance, 0), 'cost_rate', bc.cost_rate,
                       'book_value', round(coalesce(bc.balance, 0) * bc.cost_rate, 2)),
             'bank', jsonb_build_object('balance', coalesce(bb.balance, 0), 'cost_rate', bb.cost_rate,
                       'book_value', round(coalesce(bb.balance, 0) * bb.cost_rate, 2)),
             'market_sell_cash', (select rate from last_exchange_rates
                                   where owner_id = v_admin and kind = 'sell_cash'),
             'market_sell_bank', (select rate from last_exchange_rates
                                   where owner_id = v_admin and kind = 'sell_bank'))
           order by co.name, e.name)
      from exchanges e
      join companies co on co.id = e.company_id and co.owner_id = v_admin
      left join account_books bc on bc.exchange_id = e.id and bc.book = 'cash'
      left join account_books bb on bb.exchange_id = e.id and bb.book = 'bank'
  ), '[]'::jsonb);
end;
$$;
revoke all on function account_books_list() from public, anon;
grant execute on function account_books_list() to authenticated;

-- =============================================================================
-- H) the customers' dinar accounts, per book (copied from 0091)
-- =============================================================================
-- what a customer owes now (+) or is owed (−), in one book or (null) in both;
-- a line saved before 0093 is the bank book's (internal)
drop function if exists _customer_balance(uuid);
create or replace function _customer_balance(p_client_id uuid, p_book text default null)
returns numeric
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(sum(amount), 0) from customer_lyd_entries
   where client_id = p_client_id
     and (p_book is null or coalesce(book, 'bank') = p_book)
$$;
revoke all on function _customer_balance(uuid, text) from public, anon, authenticated;

-- collect: the customer pays us [amount] into [pocket] — the pocket's book
-- pay:     we pay the customer [amount] from [pocket] — the pocket's book
-- opening: what he owes us (+) or we owe him (−) before the app, in [p_book]
drop function if exists customer_add_entry(uuid, text, numeric, text, text, uuid);
create or replace function customer_add_entry(
  p_client_id  uuid,
  p_kind       text,
  p_amount     numeric,
  p_pocket     text default null,
  p_note       text default null,
  p_request_id uuid default null,
  p_book       text default 'bank'
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := _lyd_admin();
  v_amount numeric := round(coalesce(p_amount, 0), 2);
  v_book   text;
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
    v_book := p_pocket;                   -- the box is the cash book, the bank the bank book
  else
    if v_amount = 0 or abs(v_amount) > 999999999999.99 then
      raise exception 'lyd_amount_invalid' using errcode = 'P0001';
    end if;
    v_book := coalesce(p_book, 'bank');
    if v_book not in ('cash', 'bank') then
      raise exception 'book_invalid' using errcode = 'P0001';
    end if;
  end if;

  perform 1 from clients where id = p_client_id and owner_id = v_admin for update;
  if not found then
    raise exception 'client_not_found_or_forbidden' using errcode = 'P0001';
  end if;

  if p_request_id is not null and exists (
    select 1 from customer_lyd_entries where owner_id = v_admin and request_id = p_request_id
  ) then
    return jsonb_build_object('ok', true, 'balance', _customer_balance(p_client_id),
                              'balance_cash', _customer_balance(p_client_id, 'cash'),
                              'balance_bank', _customer_balance(p_client_id, 'bank'));
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
  insert into customer_lyd_entries (owner_id, client_id, kind, amount, pocket, note, request_id, book)
  values (v_admin, p_client_id, p_kind, v_signed,
          case when p_kind in ('collect', 'pay') then p_pocket end,
          nullif(btrim(coalesce(p_note, '')), ''), p_request_id, v_book);
  return jsonb_build_object('ok', true, 'book', v_book,
                            'balance', _customer_balance(p_client_id),
                            'balance_cash', _customer_balance(p_client_id, 'cash'),
                            'balance_bank', _customer_balance(p_client_id, 'bank'));
end;
$$;
revoke all on function customer_add_entry(uuid, text, numeric, text, text, uuid, text) from public, anon;
grant execute on function customer_add_entry(uuid, text, numeric, text, text, uuid, text) to authenticated;

-- every customer with a dinar account or a limit: what he owes (+) / is owed
-- (−) in each book; balance = both (older builds)
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
             'balance_cash', coalesce(s.balance_cash, 0),
             'balance_bank', coalesce(s.balance_bank, 0),
             'last_at', s.last_at)
           order by coalesce(s.balance, 0) desc, c.name)
      from clients c
      left join (select client_id, sum(amount) as balance,
                        coalesce(sum(amount) filter (where coalesce(book, 'bank') = 'cash'), 0) as balance_cash,
                        coalesce(sum(amount) filter (where coalesce(book, 'bank') = 'bank'), 0) as balance_bank,
                        max(created_at) as last_at
                   from customer_lyd_entries where owner_id = v_admin
                  group by client_id) s on s.client_id = c.id
     where c.owner_id = v_admin
       and (s.client_id is not null or c.credit_limit is not null)
  ), '[]'::jsonb);
end;
$$;
revoke all on function customer_balances() from public, anon;
grant execute on function customer_balances() to authenticated;

-- one customer's dinar statement for [from, to], in one book or (null) both
drop function if exists customer_statement(uuid, timestamptz, timestamptz);
create or replace function customer_statement(
  p_client_id uuid, p_from timestamptz, p_to timestamptz, p_book text default null
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
  if p_book is not null and p_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;
  select coalesce(sum(amount), 0) into v_opening
    from customer_lyd_entries
   where client_id = p_client_id and created_at < p_from
     and (p_book is null or coalesce(book, 'bank') = p_book);
  return jsonb_build_object(
    'book', p_book,
    'opening', v_opening,
    'closing', _customer_balance(p_client_id, p_book),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'kind', e.kind, 'amount', e.amount, 'pocket', e.pocket,
               'book', coalesce(e.book, 'bank'),
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
         and (p_book is null or coalesce(e.book, 'bank') = p_book)
         and e.created_at between p_from and p_to), '[]'::jsonb)
  );
end;
$$;
revoke all on function customer_statement(uuid, timestamptz, timestamptz, text) from public, anon;
grant execute on function customer_statement(uuid, timestamptz, timestamptz, text) to authenticated;

-- =============================================================================
-- I) the dinar treasury: a conversion has two amounts (copied from 0091 / 0087)
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

  -- a conversion: what left one pocket (amount) and what arrived in the
  -- other (amount_in, null = the same)
  select cash + coalesce(sum(case
           when m.kind = 'in' and m.pocket = 'cash' then m.amount
           when m.kind = 'out' and m.pocket = 'cash' then -m.amount
           when m.kind = 'cash_to_bank' then -m.amount
           when m.kind = 'bank_to_cash' then coalesce(m.amount_in, m.amount)
           when m.kind = 'count_over' then m.amount
           when m.kind = 'count_short' then -m.amount
           else 0 end), 0),
         bank + coalesce(sum(case
           when m.kind = 'in' and m.pocket = 'bank' then m.amount
           when m.kind = 'out' and m.pocket = 'bank' then -m.amount
           when m.kind = 'cash_to_bank' then coalesce(m.amount_in, m.amount)
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

-- a deposit, a withdrawal or a conversion between the box and the bank:
-- [p_amount] leaves, [p_amount_in] (default the same) arrives; the difference
-- is the conversion's result (4400)
drop function if exists lyd_add_movement(text, text, numeric, text);
create or replace function lyd_add_movement(
  p_kind text, p_pocket text, p_amount numeric, p_note text default null,
  p_amount_in numeric default null
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
  insert into lyd_movements (owner_id, kind, pocket, amount, note, amount_in)
  values (v_admin, p_kind,
          case when p_kind in ('in', 'out') then p_pocket end,
          v_amount, nullif(btrim(coalesce(p_note, '')), ''),
          case when v_in <> v_amount then v_in end);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function lyd_add_movement(text, text, numeric, text, numeric) from public, anon;
grant execute on function lyd_add_movement(text, text, numeric, text, numeric) to authenticated;

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
          and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    -- what the conversions cost (+) or gained (−) in the period (0093)
    'conversion_result', coalesce((select sum(amount - amount_in) from lyd_movements
        where owner_id = v_admin and amount_in is not null
          and created_at between p_from and p_to), 0)
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
               'amount_in', coalesce(m.amount_in, case when m.kind in ('cash_to_bank', 'bank_to_cash')
                                                       then m.amount end),
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

-- =============================================================================
-- J) the reports: per book (copied from 0085)
-- =============================================================================
-- older builds: one line per account, the two books together (the book value
-- is the sum of each book's; unrealized at each book's last sell rate)
create or replace function treasury_positions()
returns table (
  exchange_id     uuid,
  company_name    text,
  account_name    text,
  balance         numeric,
  cost_rate       numeric,
  book_value      numeric,
  cost_updated_at timestamptz,
  market_rate     numeric,
  unrealized      numeric
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_cash numeric;
  v_bank numeric;
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select rate into v_cash from last_exchange_rates where owner_id = auth.uid() and kind = 'sell_cash';
  select rate into v_bank from last_exchange_rates where owner_id = auth.uid() and kind = 'sell_bank';
  return query
    with k as (
      select b.exchange_id,
             bool_or(b.balance <> 0 and b.cost_rate is null) as uncosted,
             sum(round(b.balance * b.cost_rate, 2)) as value,
             max(b.updated_at) as updated_at,
             sum(round(b.balance * ((case b.book when 'cash' then v_cash else v_bank end) - b.cost_rate), 2))
               as unrealized,
             bool_or(b.balance <> 0 and (case b.book when 'cash' then v_cash else v_bank end) is null) as unpriced,
             max(b.cost_rate) filter (where b.cost_rate is not null) as any_cost,
             (array_agg(b.book order by b.balance desc))[1] as main_book
        from account_books b
       group by b.exchange_id
    )
    select e.id, c.name, e.name, e.balance,
           case when k.uncosted or k.value is null then null
                when e.balance > 0 then round(k.value / e.balance, 6)
                else k.any_cost end,
           case when k.uncosted then null else k.value end,
           k.updated_at,
           case k.main_book when 'cash' then v_cash else v_bank end,
           case when k.uncosted or k.unpriced or k.value is null then null else k.unrealized end
      from exchanges e
      join companies c on c.id = e.company_id
      left join k on k.exchange_id = e.id
     where c.owner_id = auth.uid()
     order by c.name, e.name;
end;
$$;
revoke all on function treasury_positions() from public, anon;
grant execute on function treasury_positions() to authenticated;

-- realized profit of a period, per account AND book. The book of a row saved
-- before 0093: _book_of(book, lyd_method).
drop function if exists profit_report(timestamptz, timestamptz);
create function profit_report(p_from timestamptz, p_to timestamptz)
returns table (
  exchange_id     uuid,
  company_name    text,
  account_name    text,
  book            text,
  sold_usd        numeric,   -- exits with a rate and a cost
  sales_lyd       numeric,
  cost_lyd        numeric,
  profit_lyd      numeric,
  exits_priced    integer,
  exits_unpriced  integer,   -- exits without a rate or a cost
  unpriced_usd    numeric,
  bought_usd      numeric,   -- entries with a rate
  bought_lyd      numeric,
  entries_priced  integer
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  return query
    with ex as (
      select t.exchange_id, _book_of(t.book, t.lyd_method) as bk,
             (t.rate is not null and oc.cost_after is not null) as priced,
             t.amount, t.lyd_amount,
             round(t.amount * oc.cost_after, 2) as cogs
        from transfers t
        left join operation_costs oc
          on oc.operation_id = t.id and oc.kind = 'sell'
       where t.owner_id = auth.uid()
         and t.status = 'archived'
         and t.cancelled_at is null
         and t.created_at between p_from and p_to
    ),
    en as (
      select b.exchange_id, _book_of(b.book, b.lyd_method) as bk, b.usd_amount, b.lyd_amount
        from currency_buys b
       where b.owner_id = auth.uid()
         and b.status = 'archived'
         and b.cancelled_at is null
         and b.rate is not null
         and b.created_at between p_from and p_to
    ),
    s as (
      select ex.exchange_id, ex.bk,
             coalesce(sum(ex.amount) filter (where priced), 0)      as sold_usd,
             coalesce(sum(ex.lyd_amount) filter (where priced), 0)  as sales_lyd,
             coalesce(sum(ex.cogs) filter (where priced), 0)        as cost_lyd,
             count(*) filter (where priced)::integer                as exits_priced,
             count(*) filter (where not priced)::integer            as exits_unpriced,
             coalesce(sum(ex.amount) filter (where not priced), 0)  as unpriced_usd
        from ex group by ex.exchange_id, ex.bk
    ),
    b as (
      select en.exchange_id, en.bk,
             sum(en.usd_amount) as bought_usd,
             sum(en.lyd_amount) as bought_lyd,
             count(*)::integer  as entries_priced
        from en group by en.exchange_id, en.bk
    ),
    keys as (
      select s.exchange_id, s.bk from s
      union
      select b.exchange_id, b.bk from b
    )
    select e.id, c.name, e.name, k.bk,
           coalesce(s.sold_usd, 0), coalesce(s.sales_lyd, 0),
           coalesce(s.cost_lyd, 0),
           coalesce(s.sales_lyd, 0) - coalesce(s.cost_lyd, 0),
           coalesce(s.exits_priced, 0), coalesce(s.exits_unpriced, 0),
           coalesce(s.unpriced_usd, 0),
           coalesce(b.bought_usd, 0), coalesce(b.bought_lyd, 0),
           coalesce(b.entries_priced, 0)
      from keys k
      join exchanges e on e.id = k.exchange_id
      join companies c on c.id = e.company_id
      left join s on s.exchange_id = k.exchange_id and s.bk = k.bk
      left join b on b.exchange_id = k.exchange_id and b.bk = k.bk
     where c.owner_id = auth.uid()
     order by c.name, e.name, k.bk;
end;
$$;
revoke all on function profit_report(timestamptz, timestamptz) from public, anon;
grant execute on function profit_report(timestamptz, timestamptz) to authenticated;

-- the history of an account's cost, each change with its book (a change saved
-- before 0093 is the bank book's); [p_book] keeps one book
drop function if exists account_cost_history(uuid);
create or replace function account_cost_history(p_exchange_id uuid, p_book text default null)
returns table (
  kind           text,
  operation_id   uuid,
  balance_before numeric,
  cost_before    numeric,
  usd_amount     numeric,
  rate           numeric,
  balance_after  numeric,
  cost_after     numeric,
  created_at     timestamptz,
  book           text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  return query
    select v.kind, v.operation_id, v.balance_before, v.cost_before, v.usd_amount,
           v.rate, v.balance_after, v.cost_after, v.created_at, coalesce(v.book, 'bank')
      from account_cost_events v
     where v.exchange_id = p_exchange_id
       and v.owner_id = auth.uid()
       and (p_book is null or coalesce(v.book, 'bank') = p_book)
     order by v.created_at desc
     limit 500;
end;
$$;
revoke all on function account_cost_history(uuid, text) from public, anon;
grant execute on function account_cost_history(uuid, text) to authenticated;

-- =============================================================================
-- K) the ledger: every line in a book (copied from 0092)
-- =============================================================================
-- Each line carries its book. The pockets are fixed: 1100 (the box) is the
-- cash book's, 1110 (the bank) the bank book's. The dollars (1300 / 1390) of
-- a row saved before 0093 are the bank book's (where 0093 put them); what a
-- customer owes on it (1200: the book its customer line was given), its
-- result and its dinars outside the treasury (3200) follow
-- _book_of(book, lyd_method). Whatever one source moves from
-- one book to the other is cleared through 3300 «تحويلات بين الدفترين», so
-- the lines of a source add up to zero in each book. New accounts:
--   3300 تحويلات بين الدفترين   4400 نتيجة تحويل الدينار (الصندوق ↔ المصرف)
--   4500 نتيجة النقل بين الدفترين
drop function if exists _journal(uuid);
create function _journal(p_owner uuid)
returns table (
  at          timestamptz,
  source      text,
  source_id   uuid,
  ref         text,
  memo        text,
  exchange_id uuid,
  client_id   uuid,
  account     text,
  amount      numeric,
  book        text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_start timestamptz;
begin
  select started_at into v_start from lyd_treasury where owner_id = p_owner;

  return query
  with
  -- the pocket an operation's dinars went through: the box or the bank once
  -- the dinar treasury is open, else outside it; dbook = its dollars' book,
  -- rbook = its own book (result, dinars outside the treasury)
  sales as (
    select t.*, oc.cost_before as c,
           _book_of(t.book, null) as dbook,
           _book_of(t.book, t.lyd_method) as rbook,
           case when v_start is null or t.created_at < v_start then '3200'
                when t.lyd_method = 'bank' then '1110' else '1100' end as pocket_at,
           -- the value its dollars came back with when it was cancelled: that
           -- cancel's cost change, else the book's cost at that moment
           -- (null: the book still has no cost)
           case when t.cancelled_at is null then null
                when sc.id is not null
                  then round(sc.balance_after * sc.cost_after, 2)
                     - round(sc.balance_before * coalesce(sc.cost_before, 0), 2)
                else round(t.amount * _cost_at(t.exchange_id, _book_of(t.book, null), t.cancelled_at), 2)
           end as ret
      from transfers t
      left join operation_costs oc on oc.operation_id = t.id and oc.kind = 'sell'
      left join account_cost_events sc
        on sc.operation_id = t.id and sc.kind = 'sell_cancel' and sc.owner_id = p_owner
     where t.owner_id = p_owner and t.status = 'archived'
  ),
  sale_lines as (
    -- with a rate: the dinars received, owed, the dollars out at cost, the result
    select s.id, s.reference, s.exchange_id, s.customer_id, s.created_at as at,
           s.pocket_at as pocket, s.lyd_paid as paid,
           s.lyd_amount - s.lyd_paid as unpaid,
           case when s.c is null then null else round(s.amount * s.c, 2) end as cost_value,
           s.lyd_amount as lyd, s.amount, s.cancelled_at, s.ret, s.dbook, s.rbook
      from sales s
     where s.lyd_amount is not null
  ),
  buys as (
    select b.*,
           _book_of(b.book, null) as dbook,
           _book_of(b.book, b.lyd_method) as rbook,
           case when v_start is null or b.created_at < v_start then '3200'
                when b.lyd_method = 'bank' then '1110' else '1100' end as pocket_at,
           ev.balance_after * ev.cost_after as ev_after,
           ev.balance_before * coalesce(ev.cost_before, 0) as ev_before,
           ce.balance_after * ce.cost_after as ce_after,
           ce.balance_before * coalesce(ce.cost_before, 0) as ce_before,
           case when b.cancelled_at is null then null
                else _cost_at(b.exchange_id, _book_of(b.book, null), b.cancelled_at) end as cost_then,
           case when b.lyd_amount is not null then null
                else _cost_at(b.exchange_id, _book_of(b.book, null), b.created_at) end as cost_in
      from currency_buys b
      left join account_cost_events ev
        on ev.operation_id = b.id and ev.kind = 'buy' and ev.owner_id = p_owner
      left join account_cost_events ce
        on ce.operation_id = b.id and ce.kind = 'buy_cancel' and ce.owner_id = p_owner
     where b.owner_id = p_owner and b.status = 'archived'
  ),
  buy_cancels as (
    -- the dollars out when a purchase is cancelled: its cost change, else the
    -- book's cost then; a book still without a cost: unvalued, at the dinars
    select b.*,
           case when b.ev_after is null and b.cost_then is null then '1390' else '1300' end as acct,
           case when b.ce_after is not null
                  then round(b.ce_before, 2) - round(b.ce_after, 2)
                when b.cost_then is not null then round(b.usd_amount * b.cost_then, 2)
                else b.lyd_amount end as val
      from buys b where b.cancelled_at is not null and b.lyd_amount is not null
  ),
  -- the "unvalued dollars" (1390) of each book of each account, line by line:
  -- released into 1300 when the book is given its opening cost
  unval (exchange_id, book, at, amount) as (
    select l.exchange_id, l.dbook, l.at, -l.lyd from sale_lines l where l.cost_value is null
    union all
    select l.exchange_id, l.dbook, l.cancelled_at, l.lyd from sale_lines l
     where l.cancelled_at is not null and l.cost_value is null and l.ret is null
    union all
    select b.exchange_id, b.dbook, b.created_at, b.lyd_amount from buys b
     where b.lyd_amount is not null and b.ev_after is null
    union all
    select c.exchange_id, c.dbook, c.cancelled_at, -c.val from buy_cancels c where c.acct = '1390'
  ),
  openings as (
    select e.*, _book_of(e.book, null) as dbook,
           round(e.balance_after * e.cost_after, 2)
             - round(e.balance_before * coalesce(e.cost_before, 0), 2) as delta,
           coalesce((select sum(u.amount) from unval u
                      where u.exchange_id = e.exchange_id and u.book = _book_of(e.book, null)
                        and u.at <= e.created_at
                        and u.at > coalesce((select max(p.created_at) from account_cost_events p
                                              where p.exchange_id = e.exchange_id
                                                and _book_of(p.book, null) = _book_of(e.book, null)
                                                and p.kind = 'opening'
                                                and p.created_at < e.created_at), '-infinity')), 0)
             as released
      from account_cost_events e
     where e.owner_id = p_owner and e.kind in ('opening', 'correction')
  ),
  -- dollars moved between the books: out of one at its cost (fv), into the
  -- other at the price typed (pv), its cost change (tv)
  moves as (
    select m.*,
           round(m.usd * m.from_cost, 2) as fv,
           round(m.usd * m.to_price, 2) as pv,
           round(ev.balance_after * ev.cost_after, 2)
             - round(ev.balance_before * coalesce(ev.cost_before, 0), 2) as tv
      from book_transfers m
      left join account_cost_events ev on ev.operation_id = m.id and ev.kind = 'move_in'
     where m.owner_id = p_owner
  ),
  lines (at, source, source_id, ref, memo, exchange_id, client_id, account, amount, book) as (
    ---------------------------------------------------------------- sales
    select l.at, 'sale'::text, l.id, l.reference, null::text, l.exchange_id, null::uuid, l.pocket, l.paid, l.rbook
      from sale_lines l where l.paid > 0
    union all
    select l.at, 'sale', l.id, l.reference, null, l.exchange_id, l.customer_id, '1200', l.unpaid, l.rbook
      from sale_lines l where l.unpaid > 0
    union all
    select l.at, 'sale', l.id, l.reference, null, l.exchange_id, null,
           case when l.cost_value is null then '1390' else '1300' end,
           -coalesce(l.cost_value, l.lyd), l.dbook
      from sale_lines l
    union all
    select l.at, 'sale', l.id, l.reference, null, l.exchange_id, null, '4100', -(l.lyd - l.cost_value), l.rbook
      from sale_lines l where l.cost_value is not null and l.lyd <> l.cost_value
    -- a sale without a rate (an older build): the dollars left at cost, the
    -- dinars are not known
    union all
    select s.created_at, 'sale', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '1300',
           -round(s.amount * s.c, 2), s.dbook
      from sales s where s.lyd_amount is null and s.c is not null
    union all
    select s.created_at, 'sale', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '3200',
           round(s.amount * s.c, 2), s.rbook
      from sales s where s.lyd_amount is null and s.c is not null
    ------------------------------------------- sale cancels: the dinars back, the dollars in
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, null, l.pocket, -l.paid, l.rbook
      from sale_lines l where l.cancelled_at is not null and l.paid > 0
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, l.customer_id, '1200', -l.unpaid, l.rbook
      from sale_lines l where l.cancelled_at is not null and l.unpaid > 0
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, null,
           case when l.ret is null then '1390' else '1300' end,
           coalesce(l.ret, l.lyd), l.dbook
      from sale_lines l where l.cancelled_at is not null
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, null, '4100', l.lyd - l.ret, l.rbook
      from sale_lines l where l.cancelled_at is not null and l.ret is not null and l.lyd <> l.ret
    union all
    select s.cancelled_at, 'sale_cancel', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '1300', s.ret, s.dbook
      from sales s where s.cancelled_at is not null and s.lyd_amount is null and s.ret is not null
    union all
    select s.cancelled_at, 'sale_cancel', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '3200',
           -coalesce(round(s.amount * s.c, 2), s.ret), s.rbook
      from sales s where s.cancelled_at is not null and s.lyd_amount is null
       and (s.c is not null or s.ret is not null)
    union all
    select s.cancelled_at, 'sale_cancel', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '4100',
           round(s.amount * s.c, 2) - s.ret, s.rbook
      from sales s where s.cancelled_at is not null and s.lyd_amount is null
       and s.c is not null and s.ret is not null and round(s.amount * s.c, 2) <> s.ret
    ---------------------------------------------------------------- buys
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, b.pocket_at, -b.lyd_paid, b.rbook
      from buys b where b.lyd_amount is not null and b.lyd_paid > 0
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, b.client_id, '1200',
           -(b.lyd_amount - b.lyd_paid), b.rbook
      from buys b where b.lyd_amount is not null and b.lyd_amount > b.lyd_paid
    -- the dollars in, at the value the cost change gave them
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, '1300',
           round(b.ev_after, 2) - round(b.ev_before, 2), b.dbook
      from buys b where b.lyd_amount is not null and b.ev_after is not null
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, '5900',
           b.lyd_amount - (round(b.ev_after, 2) - round(b.ev_before, 2)), b.rbook
      from buys b where b.lyd_amount is not null and b.ev_after is not null
       and b.lyd_amount <> round(b.ev_after, 2) - round(b.ev_before, 2)
    -- a book without a cost: the dinars paid, unvalued
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, '1390', b.lyd_amount, b.dbook
      from buys b where b.lyd_amount is not null and b.ev_after is null
    -- without a rate (an older build): in at the book's cost, dinars unknown
    union all
    select b.created_at, 'buy', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '1300',
           round(b.usd_amount * b.cost_in, 2), b.dbook
      from buys b where b.lyd_amount is null and b.cost_in is not null
    union all
    select b.created_at, 'buy', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '3200',
           -round(b.usd_amount * b.cost_in, 2), b.rbook
      from buys b where b.lyd_amount is null and b.cost_in is not null
    ------------------------------------------------- buy cancels: the dinars back, the dollars out
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, null, b.exchange_id, null, b.pocket_at, b.lyd_paid, b.rbook
      from buys b where b.cancelled_at is not null and b.lyd_amount is not null and b.lyd_paid > 0
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, null, b.exchange_id, b.client_id, '1200',
           b.lyd_amount - b.lyd_paid, b.rbook
      from buys b where b.cancelled_at is not null and b.lyd_amount is not null and b.lyd_amount > b.lyd_paid
    union all
    select c.cancelled_at, 'buy_cancel', c.id, c.reference, null, c.exchange_id, null, c.acct, -c.val, c.dbook
      from buy_cancels c
    union all
    select c.cancelled_at, 'buy_cancel', c.id, c.reference, null, c.exchange_id, null, '4100', c.val - c.lyd_amount, c.rbook
      from buy_cancels c where c.val <> c.lyd_amount
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '1300',
           -round(b.usd_amount * b.cost_then, 2), b.dbook
      from buys b where b.cancelled_at is not null and b.lyd_amount is null and b.cost_then is not null
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '3200',
           round(b.usd_amount * b.cost_then, 2), b.rbook
      from buys b where b.cancelled_at is not null and b.lyd_amount is null and b.cost_then is not null
    ------------------------------------------------ the opening cost and its corrections
    union all
    select o.created_at, 'cost_' || o.kind, o.id, null, null, o.exchange_id, null, '1300', o.delta, o.dbook
      from openings o
    -- the book's unvalued dollars until now are now valued: out of 1390
    union all
    select o.created_at, 'cost_' || o.kind, o.id, null, null, o.exchange_id, null, '1390', -o.released, o.dbook
      from openings o where o.kind = 'opening' and o.released <> 0
    union all
    select o.created_at, 'cost_' || o.kind, o.id, null, null, o.exchange_id, null,
           case o.kind when 'opening' then '3100' else '3150' end,
           -(o.delta - case o.kind when 'opening' then o.released else 0 end), o.dbook
      from openings o
    ------------------------------------------------ dollars moved between the books
    union all
    select m.created_at, 'book_move', m.id, null, m.note, m.exchange_id, null, '1300', -m.fv, m.from_book
      from moves m
    union all
    select m.created_at, 'book_move', m.id, null, m.note, m.exchange_id, null, '4500', -(m.pv - m.fv), m.from_book
      from moves m where m.pv <> m.fv
    union all
    select m.created_at, 'book_move', m.id, null, m.note, m.exchange_id, null, '1300', m.tv, m.to_book
      from moves m where m.tv is not null
    union all
    select m.created_at, 'book_move', m.id, null, m.note, m.exchange_id, null, '5900', m.pv - m.tv, m.to_book
      from moves m where m.tv is not null and m.pv <> m.tv
    ------------------------------------------------ balance adjustments, at the cost of the day
    union all
    select a.created_at, 'adjustment', a.id, null, a.reason, a.exchange_id, null, '1300',
           round(a.delta * _cost_at(a.exchange_id, _book_of(a.book, null), a.created_at), 2),
           _book_of(a.book, null)
      from balance_adjustments a
     where a.owner_id = p_owner and coalesce(a.kind, 'adjust') = 'adjust'
       and _cost_at(a.exchange_id, _book_of(a.book, null), a.created_at) is not null
    union all
    select a.created_at, 'adjustment', a.id, null, a.reason, a.exchange_id, null,
           case when a.delta > 0 then '4300' else '5100' end,
           -round(a.delta * _cost_at(a.exchange_id, _book_of(a.book, null), a.created_at), 2),
           _book_of(a.book, null)
      from balance_adjustments a
     where a.owner_id = p_owner and coalesce(a.kind, 'adjust') = 'adjust'
       and _cost_at(a.exchange_id, _book_of(a.book, null), a.created_at) is not null
    ------------------------------------------------ commissions taken from an account
    union all
    select x.created_at, 'expense', x.id, x.code, x.note, x.exchange_id, null, '5300', x.v, x.bk
      from (select e.*, _book_of(e.book, null) as bk,
                   round(e.amount * _cost_at(e.exchange_id, _book_of(e.book, null), e.created_at), 2) as v
              from account_expenses e where e.owner_id = p_owner) x
     where x.v is not null
    union all
    select x.created_at, 'expense', x.id, x.code, x.note, x.exchange_id, null, '1300', -x.v, x.bk
      from (select e.*, _book_of(e.book, null) as bk,
                   round(e.amount * _cost_at(e.exchange_id, _book_of(e.book, null), e.created_at), 2) as v
              from account_expenses e where e.owner_id = p_owner) x
     where x.v is not null
    -- cancelled: the commission reversed as it was booked; the dollars back
    -- at the cost of that moment, the difference a revaluation
    union all
    select x.cancelled_at, 'expense_cancel', x.id, x.code, x.note, x.exchange_id, null, '5300', -x.v, x.bk
      from (select e.*, _book_of(e.book, null) as bk,
                   round(e.amount * _cost_at(e.exchange_id, _book_of(e.book, null), e.created_at), 2) as v
              from account_expenses e where e.owner_id = p_owner and e.cancelled_at is not null) x
     where x.v is not null
    union all
    select x.cancelled_at, 'expense_cancel', x.id, x.code, x.note, x.exchange_id, null, '1300', x.r, x.bk
      from (select e.*, _book_of(e.book, null) as bk,
                   round(e.amount * _cost_at(e.exchange_id, _book_of(e.book, null), e.cancelled_at), 2) as r
              from account_expenses e where e.owner_id = p_owner and e.cancelled_at is not null) x
     where x.r is not null
    union all
    select x.cancelled_at, 'expense_cancel', x.id, x.code, x.note, x.exchange_id, null,
           case when x.v is null then '3100' else '5900' end,
           coalesce(x.v, 0) - x.r, x.bk
      from (select e.*, _book_of(e.book, null) as bk,
                   round(e.amount * _cost_at(e.exchange_id, _book_of(e.book, null), e.created_at), 2) as v,
                   round(e.amount * _cost_at(e.exchange_id, _book_of(e.book, null), e.cancelled_at), 2) as r
              from account_expenses e where e.owner_id = p_owner and e.cancelled_at is not null) x
     where x.r is not null and coalesce(x.v, 0) <> x.r
    ------------------------------------------------ customers: collections, payments, openings
    union all
    select e.created_at, 'customer_' || e.kind, e.id, null, e.note, null, e.client_id, '1200', e.amount,
           _book_of(e.book, null)
      from customer_lyd_entries e
     where e.owner_id = p_owner and e.kind in ('collect', 'pay', 'opening')
    union all
    select e.created_at, 'customer_' || e.kind, e.id, null, e.note, null, e.client_id,
           case when e.kind = 'opening' then '3100'
                when v_start is null or e.created_at < v_start then '3200'
                when e.pocket = 'bank' then '1110' else '1100' end,
           -e.amount, _book_of(e.book, null)
      from customer_lyd_entries e
     where e.owner_id = p_owner and e.kind in ('collect', 'pay', 'opening')
    ------------------------------------------------ the dinar treasury
    union all
    select t.started_at, 'lyd_opening', null::uuid, null, null, null, null, '1100', t.opening_cash, 'cash'
      from lyd_treasury t where t.owner_id = p_owner and t.opening_cash <> 0
    union all
    select t.started_at, 'lyd_opening', null, null, null, null, null, '1110', t.opening_bank, 'bank'
      from lyd_treasury t where t.owner_id = p_owner and t.opening_bank <> 0
    union all
    select t.started_at, 'lyd_opening', null, null, null, null, null, '3100', -t.opening_cash, 'cash'
      from lyd_treasury t where t.owner_id = p_owner and t.opening_cash <> 0
    union all
    select t.started_at, 'lyd_opening', null, null, null, null, null, '3100', -t.opening_bank, 'bank'
      from lyd_treasury t where t.owner_id = p_owner and t.opening_bank <> 0
    -- the pocket that received (a conversion: what arrived)
    union all
    select m.created_at, 'lyd_' || m.kind, m.id, null, m.note, null, null,
           case m.kind when 'in' then case m.pocket when 'bank' then '1110' else '1100' end
                       when 'out' then case m.pocket when 'bank' then '1110' else '1100' end
                       when 'cash_to_bank' then '1110'
                       when 'bank_to_cash' then '1100'
                       else '1100' end,
           case m.kind when 'in' then m.amount when 'out' then -m.amount
                       when 'count_short' then -m.amount
                       when 'cash_to_bank' then coalesce(m.amount_in, m.amount)
                       when 'bank_to_cash' then coalesce(m.amount_in, m.amount)
                       else m.amount end,
           coalesce(m.pocket, 'cash')
      from lyd_movements m where m.owner_id = p_owner
    -- the other side (a conversion: the pocket that paid out)
    union all
    select m.created_at, 'lyd_' || m.kind, m.id, null, m.note, null, null,
           case m.kind when 'in' then '3100' when 'out' then '3100'
                       when 'cash_to_bank' then '1100' when 'bank_to_cash' then '1110'
                       when 'count_over' then '4200' else '5200' end,
           case m.kind when 'in' then -m.amount when 'out' then m.amount
                       when 'count_short' then m.amount else -m.amount end,
           coalesce(m.pocket, 'cash')
      from lyd_movements m where m.owner_id = p_owner
    -- a conversion that lost (or gained) on the way, in the book it left
    union all
    select m.created_at, 'lyd_' || m.kind, m.id, null, m.note, null, null, '4400',
           m.amount - m.amount_in,
           case m.kind when 'cash_to_bank' then 'cash' else 'bank' end
      from lyd_movements m
     where m.owner_id = p_owner and m.kind in ('cash_to_bank', 'bank_to_cash')
       and m.amount_in is not null and m.amount_in <> m.amount
  ),
  -- the pockets' books are fixed
  tagged as (
    select l.at, l.source, l.source_id, l.ref, l.memo, l.exchange_id, l.client_id,
           l.account, l.amount,
           case l.account when '1100' then 'cash' when '1110' then 'bank' else l.book end as book
      from lines l
     where l.amount is not null and l.amount <> 0
  ),
  -- what a source moved from one book to the other
  clearing as (
    select g.at, g.source, g.source_id, max(g.ref) as ref, max(g.memo) as memo, g.exchange_id,
           null::uuid as client_id, '3300'::text as account, -sum(g.amount) as amount, g.book
      from tagged g
     group by g.at, g.source, g.source_id, g.exchange_id, g.book
    having sum(g.amount) <> 0
  )
  select g.at, g.source, g.source_id, g.ref, g.memo, g.exchange_id, g.client_id, g.account, g.amount, g.book
    from tagged g
  union all
  select c.at, c.source, c.source_id, c.ref, c.memo, c.exchange_id, c.client_id, c.account, c.amount, c.book
    from clearing c;
end;
$$;
revoke all on function _journal(uuid) from public, anon, authenticated;

-- the Arabic name of an account
create or replace function _ledger_account_name(p_code text)
returns text
language sql
immutable
as $$
  select case p_code
    when '1100' then 'الصندوق'
    when '1110' then 'المصرف'
    when '1200' then 'ذمم العملاء'
    when '1300' then 'مخزون الدولار بالتكلفة'
    when '1390' then 'دولار غير مقيّم'
    when '3100' then 'رأس المال والأرصدة الافتتاحية'
    when '3150' then 'إعادة تقييم التكلفة'
    when '3200' then 'نقدية خارج خزينة الدينار'
    when '3300' then 'تحويلات بين الدفترين'
    when '4100' then 'نتيجة بيع العملة'
    when '4200' then 'زيادة الجرد'
    when '4300' then 'أرباح تسوية الأرصدة'
    when '4400' then 'نتيجة تحويل الدينار'
    when '4500' then 'نتيجة النقل بين الدفترين'
    when '5100' then 'خسائر تسوية الأرصدة'
    when '5200' then 'عجز الجرد'
    when '5300' then 'العمولات'
    when '5900' then 'فروق التقريب'
    else p_code end
$$;

-- the lines of a report: one book as they are; both books (p_book null) with
-- the bank's lines × p_bank_factor (cash dinars per bank dinar) (internal)
create or replace function _ledger_lines(p_owner uuid, p_book text, p_bank_factor numeric)
returns table (
  at          timestamptz,
  source      text,
  source_id   uuid,
  ref         text,
  memo        text,
  exchange_id uuid,
  client_id   uuid,
  account     text,
  amount      numeric,
  book        text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
begin
  if p_book is not null and p_book not in ('cash', 'bank') then
    raise exception 'book_invalid' using errcode = 'P0001';
  end if;
  if p_bank_factor is null or p_bank_factor <= 0 or p_bank_factor > 10 then
    raise exception 'factor_invalid' using errcode = 'P0001';
  end if;
  return query
    select j.at, j.source, j.source_id, j.ref, j.memo, j.exchange_id, j.client_id, j.account,
           case when p_book is null and j.book = 'bank' then j.amount * p_bank_factor else j.amount end,
           j.book
      from _journal(p_owner) j
     where p_book is null or j.book = p_book;
end;
$$;
revoke all on function _ledger_lines(uuid, text, numeric) from public, anon, authenticated;

-- =============================================================================
-- L) the statements (copied from 0092): a book, or both at a factor
-- =============================================================================
drop function if exists ledger_trial_balance(timestamptz);
create or replace function ledger_trial_balance(
  p_to timestamptz, p_book text default null, p_bank_factor numeric default 1
)
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
             'account', j.account, 'name', _ledger_account_name(j.account),
             'debit', j.debit, 'credit', j.credit, 'balance', j.debit - j.credit)
           order by j.account)
      from (select l.account,
                   round(coalesce(sum(l.amount) filter (where l.amount > 0), 0), 2) as debit,
                   round(coalesce(-sum(l.amount) filter (where l.amount < 0), 0), 2) as credit
              from _ledger_lines(v_admin, p_book, p_bank_factor) l where l.at <= p_to
             group by l.account) j
  ), '[]'::jsonb);
end;
$$;
revoke all on function ledger_trial_balance(timestamptz, text, numeric) from public, anon;
grant execute on function ledger_trial_balance(timestamptz, text, numeric) to authenticated;

drop function if exists ledger_income_statement(timestamptz, timestamptz);
create or replace function ledger_income_statement(
  p_from timestamptz, p_to timestamptz, p_book text default null, p_bank_factor numeric default 1
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_rows  jsonb;
  v_net   numeric;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'account', x.account, 'name', _ledger_account_name(x.account),
           'amount', x.result) order by x.account), '[]'::jsonb),
         coalesce(sum(x.result), 0)
    into v_rows, v_net
    from (select l.account, round(-sum(l.amount), 2) as result   -- income is credit: shown positive
            from _ledger_lines(v_admin, p_book, p_bank_factor) l
           where l.at between p_from and p_to and l.account >= '4000'
           group by l.account) x
   where x.result <> 0;
  return jsonb_build_object('book', p_book, 'bank_factor', p_bank_factor,
                            'lines', v_rows, 'net', v_net);
end;
$$;
revoke all on function ledger_income_statement(timestamptz, timestamptz, text, numeric) from public, anon;
grant execute on function ledger_income_statement(timestamptz, timestamptz, text, numeric) to authenticated;

drop function if exists ledger_balance_sheet(timestamptz);
create or replace function ledger_balance_sheet(
  p_at timestamptz, p_book text default null, p_bank_factor numeric default 1
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_out   jsonb;
begin
  -- the journal once, up to [p_at]
  with j as materialized (
    select l.account, l.amount, l.client_id, l.exchange_id, l.book
      from _ledger_lines(v_admin, p_book, p_bank_factor) l where l.at <= p_at
  )
  select jsonb_build_object(
    'book', p_book, 'bank_factor', p_bank_factor,
    -- every balance-sheet account; the profit to date stays in one line
    'balances', coalesce((
      select jsonb_object_agg(x.account, x.bal)
        from (select case when j.account >= '4000' then 'profit' else j.account end as account,
                     round(sum(j.amount), 2) as bal
                from j group by 1) x), '{}'::jsonb),
    -- the customers: what they owe us and what we owe them, apart
    'receivable', coalesce((select round(sum(b), 2) from (select sum(j.amount) as b from j
                             where j.account = '1200' group by j.client_id) c where b > 0), 0),
    'payable', coalesce((select round(-sum(b), 2) from (select sum(j.amount) as b from j
                          where j.account = '1200' group by j.client_id) c where b < 0), 0),
    -- each book of each account: the ledger's value against balance × cost now
    'inventory', coalesce((
      select jsonb_agg(jsonb_build_object(
               'exchange_id', e.id, 'company_name', co.name, 'account_name', e.name,
               'book', ab.book,
               'balance', ab.balance, 'cost_rate', ab.cost_rate,
               'book_value', round(ab.balance * ab.cost_rate
                                   * case when p_book is null and ab.book = 'bank' then p_bank_factor else 1 end, 2),
               'ledger_value', round(coalesce(v.v, 0), 2)) order by co.name, e.name, ab.book)
        from exchanges e
        join companies co on co.id = e.company_id and co.owner_id = v_admin
        join account_books ab on ab.exchange_id = e.id and (p_book is null or ab.book = p_book)
        left join (select j.exchange_id, j.book, sum(j.amount) as v from j
                    where j.account = '1300' group by j.exchange_id, j.book) v
          on v.exchange_id = e.id and v.book = ab.book
       where ab.balance <> 0 or v.v is not null
    ), '[]'::jsonb)
  ) into v_out;
  return v_out;
end;
$$;
revoke all on function ledger_balance_sheet(timestamptz, text, numeric) from public, anon;
grant execute on function ledger_balance_sheet(timestamptz, text, numeric) to authenticated;

-- the journal of a period, the oldest first (at most 3000 lines), each line
-- in its book's own dinars
drop function if exists ledger_journal(timestamptz, timestamptz);
create or replace function ledger_journal(
  p_from timestamptz, p_to timestamptz, p_book text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_out   jsonb;
begin
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  with j as materialized (
    select l.*, count(*) over () as total
      from _ledger_lines(v_admin, p_book, 1) l where l.at between p_from and p_to
     order by l.at, l.source_id
     limit 3000
  )
  select jsonb_build_object(
    'total', coalesce((select max(total) from j), 0),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'at', j.at, 'source', j.source, 'source_id', j.source_id, 'ref', j.ref,
               'memo', j.memo, 'account', j.account, 'name', _ledger_account_name(j.account),
               'amount', j.amount, 'book', j.book, 'exchange', ex.name, 'client', cl.name)
             order by j.at, j.source_id, j.book, j.amount desc)
        from j
        left join exchanges ex on ex.id = j.exchange_id
        left join clients cl on cl.id = j.client_id), '[]'::jsonb))
    into v_out;
  return v_out;
end;
$$;
revoke all on function ledger_journal(timestamptz, timestamptz, text) from public, anon;
grant execute on function ledger_journal(timestamptz, timestamptz, text) to authenticated;

-- A close seals the trial balance of BOTH books at factor 1 (seal version 2:
-- deterministic; the units are mixed, the per-book statements are rebuilt
-- from the same journal). A close made before 0093 (version 1) is checked
-- without 3300, which did not exist then.
create or replace function close_period(p_end timestamptz, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_trial jsonb;
  v_net   numeric;
  v_name  text;
  v_id    uuid;
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  -- at least five minutes back: a save still in flight is not cut in two
  if p_end is null or p_end > now() - interval '5 minutes' then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  if exists (select 1 from period_closes where owner_id = v_admin and period_end >= p_end) then
    raise exception 'period_already_closed' using errcode = 'P0001';
  end if;
  v_trial := ledger_trial_balance(p_end, null, 1);
  select coalesce(-sum(j.amount), 0) into v_net
    from _journal(v_admin) j
   where j.at <= p_end and j.at > coalesce(
           (select max(period_end) from period_closes where owner_id = v_admin), '-infinity')
     and j.account >= '4000';
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''), u.email)
    into v_name from auth.users u where u.id = v_admin;
  insert into period_closes (owner_id, period_end, trial, net_profit, seal, seal_version, note, closed_by)
  values (v_admin, p_end, v_trial, round(v_net, 2), _trial_seal(v_trial), 2,
          nullif(btrim(coalesce(p_note, '')), ''), v_name)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'net_profit', round(v_net, 2));
end;
$$;
revoke all on function close_period(timestamptz, text) from public, anon;
grant execute on function close_period(timestamptz, text) to authenticated;

create or replace function ledger_closes()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_out   jsonb;
begin
  with j as materialized (
    select l.at, l.account, l.amount from _journal(v_admin) l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'period_end', p.period_end, 'net_profit', p.net_profit,
           'note', p.note, 'closed_by', p.closed_by, 'created_at', p.created_at,
           'intact', p.seal = _trial_seal(coalesce((
             select jsonb_agg(jsonb_build_object('account', t.account,
                                                 'debit', t.debit, 'credit', t.credit))
               from (select j.account,
                            coalesce(sum(j.amount) filter (where j.amount > 0), 0) as debit,
                            coalesce(-sum(j.amount) filter (where j.amount < 0), 0) as credit
                       from j
                      where j.at <= p.period_end
                        and (p.seal_version >= 2 or j.account <> '3300')
                      group by j.account) t), '[]'::jsonb)))
         order by p.period_end desc), '[]'::jsonb)
    into v_out
    from period_closes p where p.owner_id = v_admin;
  return v_out;
end;
$$;
revoke all on function ledger_closes() from public, anon;
grant execute on function ledger_closes() to authenticated;

-- =============================================================================
-- M) backups, restores, the redaction and the wipe know the books
--    (copied from their latest definition, 0092). A backup made before 0093
--    restores: its rows have no book (read as above), its rates 'sell' / 'buy'
--    go to both books, and each account gets its books from its balance and
--    account_costs (all in the bank book, not split yet).
-- =============================================================================
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
    'customer_lyd_entries', 'period_closes', 'account_reconciliations',
    'account_books', 'book_transfers'
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

-- the rows of a backup table made ready for this version (internal)
create or replace function public._backup_rows_now(p_table text, p_rows jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_rows jsonb := coalesce(p_rows, '[]'::jsonb);
begin
  if p_table = 'employee_activity_logs' then
    select coalesce(jsonb_agg(elem - 'session_id'), '[]'::jsonb)
      into v_rows
      from jsonb_array_elements(v_rows) elem;
  end if;

  -- a backup made before 0091 has no lyd_paid: it was paid in full
  if p_table in ('transfers', 'currency_buys') then
    select coalesce(jsonb_agg(case when elem ? 'lyd_paid' then elem
             else elem || jsonb_build_object('lyd_paid', elem -> 'lyd_amount') end), '[]'::jsonb)
      into v_rows
      from jsonb_array_elements(v_rows) elem;
  end if;

  -- a backup made before 0093: one sell rate and one buy rate, for both books
  if p_table = 'last_exchange_rates' then
    select coalesce(jsonb_agg(x), '[]'::jsonb)
      into v_rows
      from (select elem as x from jsonb_array_elements(v_rows) elem
             where elem ->> 'kind' not in ('sell', 'buy')
            union all
            select elem || jsonb_build_object('kind', (elem ->> 'kind') || s.suffix)
              from jsonb_array_elements(v_rows) elem
             cross join (values ('_cash'), ('_bank')) s(suffix)
             where elem ->> 'kind' in ('sell', 'buy')
               and not exists (select 1 from jsonb_array_elements(v_rows) n
                                where n ->> 'owner_id' = elem ->> 'owner_id'
                                  and n ->> 'kind' = (elem ->> 'kind') || s.suffix)) z;
  end if;
  return v_rows;
end;
$$;
revoke all on function public._backup_rows_now(text, jsonb) from public, anon, authenticated;

-- the books of every account restored without them (a backup made before
-- 0093): all its dollars and its cost in the bank book, not split (internal)
create or replace function public._books_from_balances(p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_n integer;
begin
  insert into public.account_books (exchange_id, book, owner_id, balance, cost_rate)
  select e.id, b.book, c.owner_id,
         case b.book when 'bank' then e.balance else 0 end,
         case b.book when 'bank' then ac.cost_rate end
    from public.exchanges e
    join public.companies c on c.id = e.company_id
    cross join (values ('cash'), ('bank')) b(book)
    left join public.account_costs ac on ac.exchange_id = e.id
   where (p_owner is null or c.owner_id = p_owner)
     and not exists (select 1 from public.account_books x where x.exchange_id = e.id)
  on conflict (exchange_id, book) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public._books_from_balances(uuid) from public, anon, authenticated;

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
  delete from public.book_transfers where true;
  delete from public.account_books where true;
  delete from public.account_reconciliations where true;
  delete from public.period_closes where true;
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
    'customer_lyd_entries', 'period_closes', 'account_reconciliations',
    'account_books', 'book_transfers'
  ] loop
    v_rows := public._backup_rows_now(t, v_tables -> t);

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
      when 'account_reconciliations' then 'r.exchange_id in (select id from public.exchanges)'
      when 'account_books'          then 'r.exchange_id in (select id from public.exchanges)'
      when 'book_transfers'         then 'r.exchange_id in (select id from public.exchanges)'
      else                               'r.owner_id in (select id from public.profiles)'
    end;

    execute format(
      'insert into public.%1$I select r.* from jsonb_populate_recordset(null::public.%1$I, $1) r where %2$s',
      t, v_filter
    ) using v_rows;
    get diagnostics v_n = row_count;
    v_counts := v_counts || jsonb_build_object(t, v_n);
  end loop;

  -- accounts from a backup made before 0093: their books from their balances
  v_n := public._books_from_balances(null);
  if v_n > 0 then
    v_counts := v_counts || jsonb_build_object('account_books_from_balances', v_n);
  end if;
  -- and its customers' lines their book
  perform public._customer_entry_books(null);

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
                        'customer_lyd_entries', 'period_closes',
                        'account_reconciliations', 'account_books',
                        'book_transfers') then
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
  delete from public.book_transfers where owner_id = p_owner;
  delete from public.account_books where owner_id = p_owner;
  delete from public.account_reconciliations where owner_id = p_owner;
  delete from public.period_closes where owner_id = p_owner;
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
    'customer_lyd_entries', 'period_closes', 'account_reconciliations',
    'account_books', 'book_transfers'
  ] loop
    v_rows := public._backup_rows_now(t, v_tables -> t);

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

  -- accounts from a backup made before 0093: their books from their balances
  v_n := public._books_from_balances(p_owner);
  if v_n > 0 then
    v_counts := v_counts || jsonb_build_object('account_books_from_balances', v_n);
  end if;
  -- and its customers' lines their book
  perform public._customer_entry_books(p_owner);

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
  -- then their books, and the dinar treasury: nothing slips in meanwhile
  perform 1 from account_books where owner_id = v_owner order by exchange_id, book for update;
  perform 1 from lyd_treasury where owner_id = v_owner for update;

  -- A way back: a full snapshot before anything changes (the numbering too).
  v_backup := public._save_backup('pre_wipe');

  -- the numbering goes on after the last number used: every company starts
  -- again from the number it would have given next
  for r in select id from companies where owner_id = v_owner loop
    update companies set start_ref = _next_reference_for(v_owner, r.id) where id = r.id;
  end loop;

  -- the closes and reconciliations described what is being wiped
  delete from account_reconciliations where owner_id = v_owner;
  delete from period_closes where owner_id = v_owner;
  delete from book_transfers where owner_id = v_owner;
  delete from customer_lyd_entries where owner_id = v_owner;
  delete from lyd_counts where owner_id = v_owner;
  delete from lyd_movements where owner_id = v_owner;
  delete from lyd_treasury where owner_id = v_owner;
  delete from operation_costs where owner_id = v_owner;
  delete from account_cost_events where owner_id = v_owner;
  -- the books empty (nothing left to split), then the costs
  update account_books set balance = 0, cost_rate = null, updated_at = now()
   where owner_id = v_owner and (balance <> 0 or cost_rate is not null);
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
  update exchanges e set books_split_at = coalesce(e.books_split_at, now())
    from companies c
   where e.company_id = c.id and c.owner_id = v_owner;

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

commit;
