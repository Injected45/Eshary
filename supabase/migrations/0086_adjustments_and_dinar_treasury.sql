-- 0086_adjustments_and_dinar_treasury.sql
-- Two things, administrator only:
--
-- A) A documented balance adjustment (تسوية رصيد) instead of editing a
--    balance by hand. admin_adjust_balance(account, new balance, reason,
--    password) moves the dollar balance, keeps the line in
--    balance_adjustments (append-only, shown in the account statement) and
--    leaves the cost price alone (the dollars move AT COST). Changing a
--    balance directly from the app is now refused (the edit screen used to
--    send back the balance it had read, wiping any operation saved meanwhile).
--
-- B) The dinar treasury (خزينة الدينار): one cash box and one bank account.
--    Every exit and entry with a rate now says how its dinars moved
--    (lyd_method: cash / bank; an older build that sends nothing = cash).
--    From the opening the administrator types:
--      cash = opening cash + exits paid in cash − entries paid in cash
--             ± deposits / withdrawals / transfers / count differences
--      bank = the same with "bank"
--    (cancelled operations and operations before the opening do not count).
--    The end-of-day count compares the cash counted with the cash expected,
--    keeps both, and may post the difference (surplus / shortage).
-- Needs 0085. Safe to run more than once.

begin;

do $$
begin
  if to_regprocedure('public.profit_report(timestamptz, timestamptz)') is null then
    raise exception 'شغّل الترحيل 0085 أولًا (الأرباح)، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- =============================================================================
-- A) balance adjustments
-- =============================================================================
create table if not exists balance_adjustments (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null references profiles (id) on delete cascade,
  exchange_id       uuid not null references exchanges (id) on delete cascade,
  balance_before    numeric(14,2) not null,
  balance_after     numeric(14,2) not null check (balance_after >= 0),
  delta             numeric(14,2) not null check (delta <> 0),
  reason            text not null check (char_length(reason) between 3 and 500),
  adjusted_by_name  text,
  created_at        timestamptz not null default now()
);
create index if not exists balance_adjustments_exchange_idx
  on balance_adjustments (exchange_id, created_at);
alter table balance_adjustments enable row level security;
revoke all on table balance_adjustments from anon, authenticated;
grant select on table balance_adjustments to authenticated;
drop policy if exists balance_adjustments_own on balance_adjustments;
create policy balance_adjustments_own on balance_adjustments
  for select to authenticated using (owner_id = (select auth.uid()));

-- a balance moves only inside the database's own functions
create or replace function _block_direct_balance_edit()
returns trigger
language plpgsql
as $$
begin
  if new.balance is distinct from old.balance
     and current_user in ('authenticated', 'anon') then
    raise exception 'balance_direct_edit' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_block_direct_balance_edit on exchanges;
create trigger trg_block_direct_balance_edit
  before update of balance on exchanges
  for each row execute function _block_direct_balance_edit();

create or replace function admin_adjust_balance(
  p_exchange_id  uuid,
  p_new_balance  numeric,
  p_reason       text,
  p_password     text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_new    numeric := round(coalesce(p_new_balance, -1), 2);
  v_hash   text;
  v_name   text;
  v_fails  integer;
  v_before numeric;
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

  -- the password, with the lock the cancellations use (5 wrong in 15 minutes)
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
    into v_hash, v_name
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

  select e.balance into v_before
    from exchanges e join companies c on c.id = e.company_id
   where e.id = p_exchange_id and c.owner_id = v_admin
     for update of e;
  if not found then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if v_new = v_before then
    raise exception 'adjust_no_change' using errcode = 'P0001';
  end if;

  update exchanges set balance = v_new where id = p_exchange_id;
  insert into balance_adjustments (
    owner_id, exchange_id, balance_before, balance_after, delta, reason,
    adjusted_by_name
  ) values (
    v_admin, p_exchange_id, v_before, v_new, v_new - v_before, v_reason, v_name
  );
  return jsonb_build_object('ok', true, 'balance_before', v_before,
                            'balance_after', v_new);
end;
$$;
revoke all on function admin_adjust_balance(uuid, numeric, text, text) from public, anon;
grant execute on function admin_adjust_balance(uuid, numeric, text, text) to authenticated;

-- =============================================================================
-- B) the dinar treasury
-- =============================================================================
alter table transfers add column if not exists lyd_method text;
alter table currency_buys add column if not exists lyd_method text;
alter table transfers drop constraint if exists transfers_lyd_method_check;
alter table transfers add constraint transfers_lyd_method_check
  check (lyd_method is null or lyd_method in ('cash', 'bank'));
alter table currency_buys drop constraint if exists currency_buys_lyd_method_check;
alter table currency_buys add constraint currency_buys_lyd_method_check
  check (lyd_method is null or lyd_method in ('cash', 'bank'));
-- what was saved with a rate before this: paid in cash
update transfers set lyd_method = 'cash' where rate is not null and lyd_method is null;
update currency_buys set lyd_method = 'cash' where rate is not null and lyd_method is null;

create table if not exists lyd_treasury (
  owner_id      uuid primary key references profiles (id) on delete cascade,
  started_at    timestamptz not null default now(),
  opening_cash  numeric(14,2) not null check (opening_cash >= 0),
  opening_bank  numeric(14,2) not null check (opening_bank >= 0)
);
alter table lyd_treasury enable row level security;
revoke all on table lyd_treasury from anon, authenticated;

create table if not exists lyd_movements (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  kind        text not null check (kind in ('in', 'out', 'cash_to_bank',
                                            'bank_to_cash', 'count_over',
                                            'count_short')),
  pocket      text check (pocket is null or pocket in ('cash', 'bank')),
  amount      numeric(14,2) not null check (amount > 0),
  note        text check (note is null or char_length(note) <= 300),
  count_id    uuid,
  created_at  timestamptz not null default now(),
  check (kind not in ('in', 'out') or pocket is not null)
);
create index if not exists lyd_movements_owner_idx on lyd_movements (owner_id, created_at);
alter table lyd_movements enable row level security;
revoke all on table lyd_movements from anon, authenticated;

create table if not exists lyd_counts (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references profiles (id) on delete cascade,
  expected    numeric(14,2) not null,
  counted     numeric(14,2) not null check (counted >= 0),
  difference  numeric(14,2) not null,
  posted      boolean not null default false,
  note        text check (note is null or char_length(note) <= 300),
  created_at  timestamptz not null default now()
);
create index if not exists lyd_counts_owner_idx on lyd_counts (owner_id, created_at desc);
alter table lyd_counts enable row level security;
revoke all on table lyd_counts from anon, authenticated;

-- the cash and bank balances of an owner now (internal)
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

  select cash + coalesce(sum(t.lyd_amount) filter (where t.lyd_method = 'cash'), 0),
         bank + coalesce(sum(t.lyd_amount) filter (where t.lyd_method = 'bank'), 0)
    into cash, bank
    from transfers t
   where t.owner_id = p_owner and t.status = 'archived' and t.cancelled_at is null
     and t.lyd_amount is not null and t.created_at >= v_t.started_at;

  select cash - coalesce(sum(b.lyd_amount) filter (where b.lyd_method = 'cash'), 0),
         bank - coalesce(sum(b.lyd_amount) filter (where b.lyd_method = 'bank'), 0)
    into cash, bank
    from currency_buys b
   where b.owner_id = p_owner and b.status = 'archived' and b.cancelled_at is null
     and b.lyd_amount is not null and b.created_at >= v_t.started_at;
end;
$$;
revoke all on function _lyd_position(uuid) from public, anon, authenticated;

create or replace function _lyd_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  return auth.uid();
end;
$$;
revoke all on function _lyd_admin() from public, anon, authenticated;

-- the opening (once)
create or replace function lyd_open(p_cash numeric, p_bank numeric)
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
  if p_cash is null or p_bank is null or p_cash < 0 or p_bank < 0
     or p_cash > 999999999999.99 or p_bank > 999999999999.99 then
    raise exception 'lyd_amount_invalid' using errcode = 'P0001';
  end if;
  insert into lyd_treasury (owner_id, opening_cash, opening_bank)
  values (v_admin, round(p_cash, 2), round(p_bank, 2))
  on conflict (owner_id) do nothing;
  if not found then
    raise exception 'lyd_already_open' using errcode = 'P0001';
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function lyd_open(numeric, numeric) from public, anon;
grant execute on function lyd_open(numeric, numeric) to authenticated;

-- a deposit, a withdrawal or a transfer between the box and the bank
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
  if not exists (select 1 from lyd_treasury where owner_id = v_admin) then
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
revoke all on function lyd_add_movement(text, text, numeric, text) from public, anon;
grant execute on function lyd_add_movement(text, text, numeric, text) to authenticated;

-- the end-of-day count of the cash box
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
  select cash into v_expected from _lyd_position(v_admin);
  if v_expected is null then
    raise exception 'lyd_not_open' using errcode = 'P0001';
  end if;
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
revoke all on function lyd_record_count(numeric, text, boolean) from public, anon;
grant execute on function lyd_record_count(numeric, text, boolean) to authenticated;

-- what the dinar screen shows: the balances now, a period's flows, its
-- movements and the last counts
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
    'sales_cash', coalesce((select sum(lyd_amount) from transfers
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'cash' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'sales_bank', coalesce((select sum(lyd_amount) from transfers
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'bank' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'buys_cash', coalesce((select sum(lyd_amount) from currency_buys
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'cash' and created_at between greatest(p_from, v_t.started_at) and p_to), 0),
    'buys_bank', coalesce((select sum(lyd_amount) from currency_buys
        where owner_id = v_admin and status = 'archived' and cancelled_at is null
          and lyd_method = 'bank' and created_at between greatest(p_from, v_t.started_at) and p_to), 0)
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
revoke all on function lyd_summary(timestamptz, timestamptz) from public, anon;
grant execute on function lyd_summary(timestamptz, timestamptz) to authenticated;

-- the save functions: one more argument, how the dinars moved -----------------
drop function if exists record_transfer(uuid, uuid, text, text, text, numeric, text, numeric);
create or replace function record_transfer(
  p_company_id                    uuid,
  p_exchange_id                   uuid,
  p_beneficiary_name              text,
  p_beneficiary_account_company   text,
  p_beneficiary_code              text,
  p_amount                        numeric,
  p_reference                     text,
  p_rate                          numeric default null,
  p_lyd_method                    text default null
)
returns transfers
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_employee_id uuid := current_employee_id();
  v_rate        numeric;
  v_cost        numeric;
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

  p_amount := round(p_amount, 2);
  v_rate := _operation_rate('sell', p_rate);

  perform 1 from exchanges where id = p_exchange_id for update;
  select cost_rate into v_cost from account_costs where exchange_id = p_exchange_id;

  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, archived_at, created_by_employee_id,
    rate, lyd_amount, lyd_method
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'archived', now(), v_employee_id,
    v_rate, round(p_amount * v_rate, 2),
    case when v_rate is null then null else coalesce(p_lyd_method, 'cash') end
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

drop function if exists record_currency_buy(uuid, uuid, uuid, text, numeric, numeric, numeric, text);
create or replace function record_currency_buy(
  p_my_company_id uuid, p_exchange_id uuid, p_client_id uuid,
  p_client_from_account text, p_usd_amount numeric, p_rate numeric,
  p_lyd_amount numeric, p_reference text default '',
  p_lyd_method text default null
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
  select c.cost_before, c.cost_after into v_cost_before, v_cost_after
    from _apply_buy_cost(v_admin_id, p_exchange_id, v_balance, p_usd_amount,
                         v_rate, v_id) c;

  insert into currency_buys (
    id, owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id, lyd_method
  ) values (
    v_id, v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, round(p_usd_amount * v_rate, 2), 'archived', now(), p_reference,
    v_employee_id,
    case when v_rate is null then null else coalesce(p_lyd_method, 'cash') end
  )
  returning * into v_inserted;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

-- =============================================================================
-- C) backups, restores and the redaction keep the new tables
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
    'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts'
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
    'balance_adjustments', 'lyd_treasury', 'lyd_movements', 'lyd_counts'
  ] loop
    v_rows := coalesce(v_tables -> t, '[]'::jsonb);

    if t = 'employee_activity_logs' then
      select coalesce(jsonb_agg(elem - 'session_id'), '[]'::jsonb)
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
                        'lyd_treasury', 'lyd_movements', 'lyd_counts') then
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

commit;
