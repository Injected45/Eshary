-- 0085_profit_and_loss.sql
-- Profit and loss of the dollar, for the administrator only (built on the cost
-- of 0082 — the ideas of bureau-de-change systems: realized P&L on cost of goods
-- sold, unrealized P&L on revaluation, break-even rate, cost history).
--
--   realized   every exit not cancelled, with a sell rate and a cost:
--                profit = lyd_amount − round(amount × cost, 2)
--              (cost = the account's cost AT THAT EXIT, kept in operation_costs)
--   unrealized what the dollars held would earn or lose if sold now, at the
--              administrator's last sell rate:
--                round(balance × (last sell rate − cost), 2)
--   break-even the account's cost: selling below it loses money.
-- Exits without a rate or a cost (before 0081/0082, older builds, accounts
-- with no opening cost) are counted apart, never guessed.
-- Needs 0084. Safe to run more than once.

begin;

do $$
begin
  if to_regclass('public.operation_costs') is null then
    raise exception 'شغّل الترحيل 0084 أولًا (إصلاحات التكلفة)، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- 1) the treasury, with the revaluation ------------------------------------------
drop function if exists treasury_positions();
create function treasury_positions()
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
declare
  v_market numeric;
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select rate into v_market from last_exchange_rates
   where owner_id = auth.uid() and kind = 'sell';
  return query
    select e.id, c.name, e.name, e.balance, k.cost_rate,
           case when k.cost_rate is null then null
                else round(e.balance * k.cost_rate, 2) end,
           k.updated_at,
           v_market,
           case when k.cost_rate is null or v_market is null then null
                else round(e.balance * (v_market - k.cost_rate), 2) end
      from exchanges e
      join companies c on c.id = e.company_id
      left join account_costs k on k.exchange_id = e.id
     where c.owner_id = auth.uid()
     order by c.name, e.name;
end;
$$;
revoke all on function treasury_positions() from public, anon;
grant execute on function treasury_positions() to authenticated;

-- 2) realized profit of a period, per account -----------------------------------
create or replace function profit_report(p_from timestamptz, p_to timestamptz)
returns table (
  exchange_id     uuid,
  company_name    text,
  account_name    text,
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
begin
  if auth.uid() is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  return query
    with ex as (
      select t.exchange_id,
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
      select b.exchange_id, b.usd_amount, b.lyd_amount
        from currency_buys b
       where b.owner_id = auth.uid()
         and b.status = 'archived'
         and b.cancelled_at is null
         and b.rate is not null
         and b.created_at between p_from and p_to
    ),
    s as (
      select ex.exchange_id,
             coalesce(sum(ex.amount) filter (where priced), 0)      as sold_usd,
             coalesce(sum(ex.lyd_amount) filter (where priced), 0)  as sales_lyd,
             coalesce(sum(ex.cogs) filter (where priced), 0)        as cost_lyd,
             count(*) filter (where priced)::integer                as exits_priced,
             count(*) filter (where not priced)::integer            as exits_unpriced,
             coalesce(sum(ex.amount) filter (where not priced), 0)  as unpriced_usd
        from ex group by ex.exchange_id
    ),
    b as (
      select en.exchange_id,
             sum(en.usd_amount) as bought_usd,
             sum(en.lyd_amount) as bought_lyd,
             count(*)::integer  as entries_priced
        from en group by en.exchange_id
    )
    select e.id, c.name, e.name,
           coalesce(s.sold_usd, 0), coalesce(s.sales_lyd, 0),
           coalesce(s.cost_lyd, 0),
           coalesce(s.sales_lyd, 0) - coalesce(s.cost_lyd, 0),
           coalesce(s.exits_priced, 0), coalesce(s.exits_unpriced, 0),
           coalesce(s.unpriced_usd, 0),
           coalesce(b.bought_usd, 0), coalesce(b.bought_lyd, 0),
           coalesce(b.entries_priced, 0)
      from exchanges e
      join companies c on c.id = e.company_id
      left join s on s.exchange_id = e.id
      left join b on b.exchange_id = e.id
     where c.owner_id = auth.uid()
       and (s.exchange_id is not null or b.exchange_id is not null)
     order by c.name, e.name;
end;
$$;
revoke all on function profit_report(timestamptz, timestamptz) from public, anon;
grant execute on function profit_report(timestamptz, timestamptz) to authenticated;

-- 3) the history of an account's cost -------------------------------------------
create or replace function account_cost_history(p_exchange_id uuid)
returns table (
  kind           text,
  operation_id   uuid,
  balance_before numeric,
  cost_before    numeric,
  usd_amount     numeric,
  rate           numeric,
  balance_after  numeric,
  cost_after     numeric,
  created_at     timestamptz
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
    select v.kind, v.operation_id, v.balance_before, v.cost_before, v.usd_amount,
           v.rate, v.balance_after, v.cost_after, v.created_at
      from account_cost_events v
     where v.exchange_id = p_exchange_id
       and v.owner_id = auth.uid()
     order by v.created_at desc
     limit 500;
end;
$$;
revoke all on function account_cost_history(uuid) from public, anon;
grant execute on function account_cost_history(uuid) to authenticated;

commit;
