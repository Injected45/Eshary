-- 0084_cost_integrity.sql
-- Fixes from the review of 0081–0083 (the cost and the exchange rate):
--
--  1. Backups and restores keep the costs. A restore deleted the accounts and,
--     by cascade, every cost of every subscriber; backups never held them.
--     last_exchange_rates, account_costs, account_cost_events and the new
--     operation_costs are now in the backup, the restore and the redaction.
--  2. Employees could read the cost through transfers.cost_rate and
--     currency_buys.cost_before/after. Those columns move to operation_costs
--     (RLS on, no grant: the administrator's functions only) and are dropped.
--  3. Cancelling an entry that was never costed (saved before the opening
--     cost, or followed by an opening/correction) no longer moves the cost.
--  4. Cancelling an exit brings its dollars back at THEIR cost (the cost of
--     that exit), not at today's.
--  5. The placeholder rate 1 of the old entry screen is recognised even when
--     its dinars were rounded (100.555 → 100.56); a rate must be above 1 and
--     at most 100 dinars per dollar (a misplaced point is refused).
--  6. Dollars are rounded to the cent BEFORE they move a balance, so the
--     balance, the stored amount and the cost always agree.
--  7. The exit locks its account before it reads the cost.
--  8. A tiny balance left after a cancellation keeps the cost (no division by
--     a few cents).
--  9. The old single key "rate_edit" sent by the 1.0.6 build is accepted and
--     means both kinds; setting a cost needs a valid licence.
-- Needs 0083. Safe to run more than once.

begin;

do $$
begin
  if to_regclass('public.account_costs') is null
     or to_regprocedure('public._operation_rate(text, numeric)') is null
     or not ('rate_edit_sell' = any (public._employee_permission_keys())) then
    raise exception 'شغّل الترحيلات 0081 ثم 0082 ثم 0083 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- 1) the cost of each operation, out of the operation tables --------------------
create table if not exists operation_costs (
  operation_id uuid primary key,
  kind         text not null check (kind in ('sell', 'buy')),
  owner_id     uuid not null references profiles (id) on delete cascade,
  exchange_id  uuid not null references exchanges (id) on delete cascade,
  cost_before  numeric(16,6),
  cost_after   numeric(16,6) not null,
  created_at   timestamptz not null default now()
);
alter table operation_costs enable row level security;
revoke all on table operation_costs from anon, authenticated;

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'transfers'
                and column_name = 'cost_rate') then
    insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                                 cost_before, cost_after, created_at)
    select t.id, 'sell', t.owner_id, t.exchange_id, t.cost_rate, t.cost_rate, t.created_at
      from transfers t
     where t.cost_rate is not null
    on conflict (operation_id) do nothing;
    alter table transfers drop column cost_rate;
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'currency_buys'
                and column_name = 'cost_after') then
    insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                                 cost_before, cost_after, created_at)
    select b.id, 'buy', b.owner_id, b.exchange_id, b.cost_before, b.cost_after, b.created_at
      from currency_buys b
     where b.cost_after is not null
    on conflict (operation_id) do nothing;
    alter table currency_buys drop column cost_before;
    alter table currency_buys drop column cost_after;
  end if;
end $$;

-- the record of cost changes knows a cancelled exit too (every earlier value kept)
alter table account_cost_events drop constraint if exists account_cost_events_kind_check;
alter table account_cost_events add constraint account_cost_events_kind_check
  check (kind in ('opening', 'correction', 'buy', 'buy_cancel', 'sell_cancel'));

-- 2) the rate: a sensible range ---------------------------------------------------
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

  if current_employee_id() is not null
     and not employee_has_perm(
       case p_kind when 'sell' then 'rate_edit_sell' else 'rate_edit_buy' end
     ) then
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

-- 3) an entry moves the cost (unchanged formula; the cost of the entry is kept
--    in operation_costs instead of currency_buys) ---------------------------------
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
  insert into operation_costs (operation_id, kind, owner_id, exchange_id,
                               cost_before, cost_after)
  values (p_operation_id, 'buy', p_owner, p_exchange_id, cost_before, cost_after)
  on conflict (operation_id) do nothing;
end;
$$;
revoke all on function _apply_buy_cost(uuid, uuid, numeric, numeric, numeric, uuid)
  from public, anon, authenticated;

-- 4) cancelling an entry: only one that was costed, and not across a new opening
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
  if not exists (select 1 from operation_costs
                  where operation_id = new.id and kind = 'buy') then
    return new;                           -- it never moved the cost
  end if;
  if exists (select 1 from account_cost_events
              where exchange_id = new.exchange_id
                and kind in ('opening', 'correction')
                and created_at > new.created_at) then
    return new;                           -- the administrator re-set the cost since
  end if;
  -- admin_cancel_operation (0048) moved the balance back before stamping
  -- cancelled_at: this is the balance after the cancellation.
  select balance into v_bal from exchanges where id = new.exchange_id;
  select cost_rate into v_cost from account_costs
   where exchange_id = new.exchange_id for update;
  if v_cost is null then
    return new;
  end if;

  v_value := (v_bal + v_q) * v_cost - v_q * new.rate;
  if v_bal < 1 or v_value <= 0 then
    v_new := v_cost;                      -- nothing meaningful left to average
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

-- 5) cancelling an exit: its dollars come back at the cost they left at ---------
create or replace function _cost_on_sell_cancel()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
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
                and kind in ('opening', 'correction')
                and created_at > new.created_at) then
    return new;
  end if;
  -- the balance is already the one after the cancellation (see above)
  select balance into v_bal from exchanges where id = new.exchange_id;
  select cost_rate into v_cost from account_costs
   where exchange_id = new.exchange_id for update;
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

  update account_costs set cost_rate = v_new, updated_at = now()
   where exchange_id = new.exchange_id;
  insert into account_cost_events (
    owner_id, exchange_id, kind, operation_id, balance_before, cost_before,
    usd_amount, rate, balance_after, cost_after
  ) values (
    new.owner_id, new.exchange_id, 'sell_cancel', new.id, v_before, v_cost,
    v_q, v_exit, v_bal, v_new
  );
  return new;
end;
$$;

drop trigger if exists trg_cost_on_sell_cancel on transfers;
create trigger trg_cost_on_sell_cancel
  after update of cancelled_at on transfers
  for each row
  when (old.cancelled_at is null and new.cancelled_at is not null)
  execute function _cost_on_sell_cancel();

-- 6) setting a cost: a valid licence and a sensible rate -------------------------
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
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_rate is null or p_rate <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;
  if p_rate <= 1 or p_rate > 100 then
    raise exception 'rate_out_of_range' using errcode = 'P0001';
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

-- 7) the save functions ---------------------------------------------------------
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

  p_amount := round(p_amount, 2);         -- the cent that is stored is the one that moves
  v_rate := _operation_rate('sell', p_rate);

  -- the account first, then its cost: no entry can change it in between
  perform 1 from exchanges where id = p_exchange_id for update;
  select cost_rate into v_cost from account_costs where exchange_id = p_exchange_id;

  -- The trigger checks the balance before the insert.
  insert into transfers (
    owner_id, company_id, exchange_id,
    beneficiary_name, beneficiary_account_company, beneficiary_code,
    amount, reference, status, archived_at, created_by_employee_id,
    rate, lyd_amount
  ) values (
    v_admin_id, p_company_id, p_exchange_id,
    p_beneficiary_name, p_beneficiary_account_company, p_beneficiary_code,
    p_amount, p_reference, 'archived', now(), v_employee_id,
    v_rate, round(p_amount * v_rate, 2)
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

  p_usd_amount := round(p_usd_amount, 2);
  -- the old entry screen sent a hidden rate of 1 with dinars = dollars (shown
  -- rounded: 100.555 → 100.56): that is "no rate"
  v_rate := _operation_rate(
    'buy',
    case when p_rate = 1 and p_lyd_amount is not null
              and abs(p_lyd_amount - p_usd_amount) < 0.01
         then null else p_rate end
  );

  -- the account, locked: its balance before this entry averages the cost
  select balance into v_balance from exchanges where id = p_exchange_id for update;
  select c.cost_before, c.cost_after into v_cost_before, v_cost_after
    from _apply_buy_cost(v_admin_id, p_exchange_id, v_balance, p_usd_amount,
                         v_rate, v_id) c;

  insert into currency_buys (
    id, owner_id, my_company_id, exchange_id, client_id, client_from_account,
    usd_amount, rate, lyd_amount, status, archived_at, reference,
    created_by_employee_id
  ) values (
    v_id, v_admin_id, p_my_company_id, p_exchange_id, p_client_id, p_client_from_account,
    p_usd_amount, v_rate, round(p_usd_amount * v_rate, 2), 'archived', now(), p_reference,
    v_employee_id
  )
  returning * into v_inserted;

  update exchanges set balance = balance + p_usd_amount where id = p_exchange_id;

  perform log_employee_activity('currency_buy_created', v_inserted.id, p_usd_amount);
  return v_inserted;
end;
$$;

-- 8) the 1.0.6 build still sends "rate_edit": both kinds ------------------------
create or replace function admin_set_employee_permissions(
  p_sub_user_id uuid,
  p_permissions text[]
) returns text[]
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_perms text[];
begin
  -- Retired keys sent by an older screen are ignored, not an error;
  -- rate_edit (0081) became rate_edit_sell + rate_edit_buy (0083).
  select coalesce(array_agg(distinct k order by k), '{}')
    into v_perms
    from (
      select unnest(case when x = 'rate_edit'
                         then array['rate_edit_sell', 'rate_edit_buy']
                         else array[x] end) as k
        from unnest(coalesce(p_permissions, '{}')) as x
       where x not in ('archive_transfers', 'archive_buys', 'archive_all')
    ) s;

  if exists (select 1 from unnest(v_perms) k where k <> all (_employee_permission_keys())) then
    raise exception 'invalid_permission' using errcode = 'P0001';
  end if;

  update sub_users s
     set permissions = v_perms,
         updated_at  = now()
   where s.id = p_sub_user_id
     and s.parent_admin_id = auth.uid();
  if not found then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  insert into employee_activity_logs (parent_admin_id, sub_user_id, event_type)
  values (auth.uid(), p_sub_user_id, 'permissions_changed');

  return v_perms;
end;
$$;
revoke all on function admin_set_employee_permissions(uuid, text[]) from public, anon;
grant execute on function admin_set_employee_permissions(uuid, text[]) to authenticated;

-- 9) backups, restores and the redaction of a deleted subscriber ---------------
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
    'operation_costs'
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
  -- backup made before 0081–0084 simply has no rows for the newer tables.
  foreach t in array array[
    'branches', 'sub_users',
    'companies', 'exchanges', 'clients', 'beneficiaries', 'countries',
    'exchange_companies', 'transfers', 'currency_buys',
    'employee_activity_logs',
    'cancellation_requests', 'operation_cancellations',
    'account_expenses',
    'last_exchange_rates', 'account_costs', 'account_cost_events',
    'operation_costs'
  ] loop
    v_rows := coalesce(v_tables -> t, '[]'::jsonb);

    -- The activity log points at login sessions, which are not part of a
    -- backup and were deleted with the employees. Restoring the log with its
    -- session ids fails on the foreign key, so restore it without them.
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
                        'operation_costs') then
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
