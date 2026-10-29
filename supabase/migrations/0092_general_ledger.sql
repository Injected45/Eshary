-- 0092_general_ledger.sql
-- Phase 2 of docs/accounting-audit-and-plan.md, part 2: the general ledger.
--
-- A double-entry journal in Libyan dinars, DERIVED from the app's records:
-- every one of them is append-only (an operation is never edited or deleted;
-- a cancellation, an adjustment, a cost change, a dinar movement are rows of
-- their own), so the same journal comes out every time and the save functions
-- are not touched. From it: the income statement (the full profit: sales,
-- adjustments, commissions, count differences), the balance sheet, the trial
-- balance and the journal itself.
--
-- The chart of accounts (dinars):
--   1100 الصندوق            1110 المصرف            1200 ذمم العملاء (صافي)
--   1300 مخزون الدولار بالتكلفة   1390 دولار غير مقيّم (عمليات قبل تحديد التكلفة)
--   3100 رأس المال والأرصدة الافتتاحية   3150 إعادة تقييم التكلفة
--   3200 نقدية خارج خزينة الدينار (قبل فتحها، أو عمليات بلا سعر)
--   4100 نتيجة بيع العملة (البيع − التكلفة)   4200 زيادة الجرد
--   4300 أرباح تسوية الأرصدة   5100 خسائر تسوية الأرصدة   5200 عجز الجرد
--   5300 العمولات   5900 فروق التقريب
--
-- Also: period closes (the trial balance sealed with a hash, so a later
-- change of the past — a restore — shows at once) and the reconciliation of
-- an account with the exchange company's statement.
--
-- Administrator only. Needs 0091. Safe to run more than once.

begin;

do $$
begin
  if to_regclass('public.customer_lyd_entries') is null then
    raise exception 'شغّل الترحيل 0091 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
  -- run again after 0093 it would bring back the ledger without the books and
  -- the backups, restores and wipe without them
  if to_regclass('public.account_books') is not null then
    raise exception 'هذا الملف (0092) طُبِّق سابقًا وتبعه 0093. لا تشغّله مرة أخرى. لم يتغير شيء.';
  end if;
end $$;

-- =============================================================================
-- A) the journal
-- =============================================================================
-- the account's cost price at moment [p_at] (the last change at or before it)
create or replace function _cost_at(p_exchange_id uuid, p_at timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public, extensions
as $$
  select cost_after from account_cost_events
   where exchange_id = p_exchange_id and created_at <= p_at
   order by created_at desc, id desc
   limit 1
$$;
revoke all on function _cost_at(uuid, timestamptz) from public, anon, authenticated;

-- every journal line of [p_owner]: amount > 0 is a debit, < 0 a credit; the
-- lines of one source (source_id + at) always add up to zero (internal)
create or replace function _journal(p_owner uuid)
returns table (
  at          timestamptz,
  source      text,
  source_id   uuid,
  ref         text,
  memo        text,
  exchange_id uuid,
  client_id   uuid,
  account     text,
  amount      numeric
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_start timestamptz;
begin
  select started_at into v_start from lyd_treasury where owner_id = p_owner;

  return query
  with
  -- the pocket an operation's dinars went through: the box or the bank once
  -- the dinar treasury is open, else outside it
  sales as (
    select t.*, oc.cost_before as c,
           case when v_start is null or t.created_at < v_start then '3200'
                when t.lyd_method = 'bank' then '1110' else '1100' end as pocket_at,
           -- the value its dollars came back with when it was cancelled: that
           -- cancel's cost change, else the account's cost at that moment
           -- (null: the account still has no cost)
           case when t.cancelled_at is null then null
                when sc.id is not null
                  then round(sc.balance_after * sc.cost_after, 2)
                     - round(sc.balance_before * coalesce(sc.cost_before, 0), 2)
                else round(t.amount * _cost_at(t.exchange_id, t.cancelled_at), 2)
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
           s.lyd_amount as lyd, s.amount, s.cancelled_at, s.ret
      from sales s
     where s.lyd_amount is not null
  ),
  buys as (
    select b.*,
           case when v_start is null or b.created_at < v_start then '3200'
                when b.lyd_method = 'bank' then '1110' else '1100' end as pocket_at,
           ev.balance_after * ev.cost_after as ev_after,
           ev.balance_before * coalesce(ev.cost_before, 0) as ev_before,
           ce.balance_after * ce.cost_after as ce_after,
           ce.balance_before * coalesce(ce.cost_before, 0) as ce_before,
           case when b.cancelled_at is null then null
                else _cost_at(b.exchange_id, b.cancelled_at) end as cost_then
      from currency_buys b
      left join account_cost_events ev
        on ev.operation_id = b.id and ev.kind = 'buy' and ev.owner_id = p_owner
      left join account_cost_events ce
        on ce.operation_id = b.id and ce.kind = 'buy_cancel' and ce.owner_id = p_owner
     where b.owner_id = p_owner and b.status = 'archived'
  ),
  buy_cancels as (
    -- the dollars out when a purchase is cancelled: its cost change, else the
    -- account's cost then; an account still without a cost: unvalued, at the
    -- dinars paid
    select b.*,
           case when b.ev_after is null and b.cost_then is null then '1390' else '1300' end as acct,
           case when b.ce_after is not null
                  then round(b.ce_before, 2) - round(b.ce_after, 2)
                when b.cost_then is not null then round(b.usd_amount * b.cost_then, 2)
                else b.lyd_amount end as val
      from buys b where b.cancelled_at is not null and b.lyd_amount is not null
  ),
  -- the "unvalued dollars" (1390) of each account, line by line: released into
  -- 1300 when the account is given its opening cost
  unval (exchange_id, at, amount) as (
    select l.exchange_id, l.at, -l.lyd from sale_lines l where l.cost_value is null
    union all
    select l.exchange_id, l.cancelled_at, l.lyd from sale_lines l
     where l.cancelled_at is not null and l.cost_value is null and l.ret is null
    union all
    select b.exchange_id, b.created_at, b.lyd_amount from buys b
     where b.lyd_amount is not null and b.ev_after is null
    union all
    select c.exchange_id, c.cancelled_at, -c.val from buy_cancels c where c.acct = '1390'
  ),
  openings as (
    select e.*,
           round(e.balance_after * e.cost_after, 2)
             - round(e.balance_before * coalesce(e.cost_before, 0), 2) as delta,
           coalesce((select sum(u.amount) from unval u
                      where u.exchange_id = e.exchange_id and u.at <= e.created_at
                        and u.at > coalesce((select max(p.created_at) from account_cost_events p
                                              where p.exchange_id = e.exchange_id and p.kind = 'opening'
                                                and p.created_at < e.created_at), '-infinity')), 0)
             as released
      from account_cost_events e
     where e.owner_id = p_owner and e.kind in ('opening', 'correction')
  ),
  lines (at, source, source_id, ref, memo, exchange_id, client_id, account, amount) as (
    ---------------------------------------------------------------- sales
    select l.at, 'sale'::text, l.id, l.reference, null::text, l.exchange_id, null::uuid, l.pocket, l.paid
      from sale_lines l where l.paid > 0
    union all
    select l.at, 'sale', l.id, l.reference, null, l.exchange_id, l.customer_id, '1200', l.unpaid
      from sale_lines l where l.unpaid > 0
    union all
    select l.at, 'sale', l.id, l.reference, null, l.exchange_id, null,
           case when l.cost_value is null then '1390' else '1300' end,
           -coalesce(l.cost_value, l.lyd)
      from sale_lines l
    union all
    select l.at, 'sale', l.id, l.reference, null, l.exchange_id, null, '4100', -(l.lyd - l.cost_value)
      from sale_lines l where l.cost_value is not null and l.lyd <> l.cost_value
    -- a sale without a rate (an older build): the dollars left at cost, the
    -- dinars are not known
    union all
    select s.created_at, 'sale', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '1300',
           -round(s.amount * s.c, 2)
      from sales s where s.lyd_amount is null and s.c is not null
    union all
    select s.created_at, 'sale', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '3200',
           round(s.amount * s.c, 2)
      from sales s where s.lyd_amount is null and s.c is not null
    ------------------------------------------- sale cancels: the dinars back, the dollars in
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, null, l.pocket, -l.paid
      from sale_lines l where l.cancelled_at is not null and l.paid > 0
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, l.customer_id, '1200', -l.unpaid
      from sale_lines l where l.cancelled_at is not null and l.unpaid > 0
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, null,
           case when l.ret is null then '1390' else '1300' end,
           coalesce(l.ret, l.lyd)
      from sale_lines l where l.cancelled_at is not null
    union all
    select l.cancelled_at, 'sale_cancel', l.id, l.reference, null, l.exchange_id, null, '4100', l.lyd - l.ret
      from sale_lines l where l.cancelled_at is not null and l.ret is not null and l.lyd <> l.ret
    union all
    select s.cancelled_at, 'sale_cancel', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '1300', s.ret
      from sales s where s.cancelled_at is not null and s.lyd_amount is null and s.ret is not null
    union all
    select s.cancelled_at, 'sale_cancel', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '3200',
           -coalesce(round(s.amount * s.c, 2), s.ret)
      from sales s where s.cancelled_at is not null and s.lyd_amount is null
       and (s.c is not null or s.ret is not null)
    union all
    select s.cancelled_at, 'sale_cancel', s.id, s.reference, 'بلا سعر', s.exchange_id, null, '4100',
           round(s.amount * s.c, 2) - s.ret
      from sales s where s.cancelled_at is not null and s.lyd_amount is null
       and s.c is not null and s.ret is not null and round(s.amount * s.c, 2) <> s.ret
    ---------------------------------------------------------------- buys
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, b.pocket_at, -b.lyd_paid
      from buys b where b.lyd_amount is not null and b.lyd_paid > 0
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, b.client_id, '1200',
           -(b.lyd_amount - b.lyd_paid)
      from buys b where b.lyd_amount is not null and b.lyd_amount > b.lyd_paid
    -- the dollars in, at the value the cost change gave them
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, '1300',
           round(b.ev_after, 2) - round(b.ev_before, 2)
      from buys b where b.lyd_amount is not null and b.ev_after is not null
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, '5900',
           b.lyd_amount - (round(b.ev_after, 2) - round(b.ev_before, 2))
      from buys b where b.lyd_amount is not null and b.ev_after is not null
       and b.lyd_amount <> round(b.ev_after, 2) - round(b.ev_before, 2)
    -- an account without a cost: the dinars paid, unvalued
    union all
    select b.created_at, 'buy', b.id, b.reference, null, b.exchange_id, null, '1390', b.lyd_amount
      from buys b where b.lyd_amount is not null and b.ev_after is null
    -- without a rate (an older build): in at the account's cost, dinars unknown
    union all
    select b.created_at, 'buy', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '1300',
           round(b.usd_amount * _cost_at(b.exchange_id, b.created_at), 2)
      from buys b where b.lyd_amount is null and _cost_at(b.exchange_id, b.created_at) is not null
    union all
    select b.created_at, 'buy', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '3200',
           -round(b.usd_amount * _cost_at(b.exchange_id, b.created_at), 2)
      from buys b where b.lyd_amount is null and _cost_at(b.exchange_id, b.created_at) is not null
    ------------------------------------------------- buy cancels: the dinars back, the dollars out
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, null, b.exchange_id, null, b.pocket_at, b.lyd_paid
      from buys b where b.cancelled_at is not null and b.lyd_amount is not null and b.lyd_paid > 0
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, null, b.exchange_id, b.client_id, '1200',
           b.lyd_amount - b.lyd_paid
      from buys b where b.cancelled_at is not null and b.lyd_amount is not null and b.lyd_amount > b.lyd_paid
    union all
    select c.cancelled_at, 'buy_cancel', c.id, c.reference, null, c.exchange_id, null, c.acct, -c.val
      from buy_cancels c
    union all
    select c.cancelled_at, 'buy_cancel', c.id, c.reference, null, c.exchange_id, null, '4100', c.val - c.lyd_amount
      from buy_cancels c where c.val <> c.lyd_amount
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '1300',
           -round(b.usd_amount * b.cost_then, 2)
      from buys b where b.cancelled_at is not null and b.lyd_amount is null and b.cost_then is not null
    union all
    select b.cancelled_at, 'buy_cancel', b.id, b.reference, 'بلا سعر', b.exchange_id, null, '3200',
           round(b.usd_amount * b.cost_then, 2)
      from buys b where b.cancelled_at is not null and b.lyd_amount is null and b.cost_then is not null
    ------------------------------------------------ the opening cost and its corrections
    union all
    select o.created_at, 'cost_' || o.kind, o.id, null, null, o.exchange_id, null, '1300', o.delta
      from openings o
    -- the account's unvalued dollars until now are now valued: out of 1390
    union all
    select o.created_at, 'cost_' || o.kind, o.id, null, null, o.exchange_id, null, '1390', -o.released
      from openings o where o.kind = 'opening' and o.released <> 0
    union all
    select o.created_at, 'cost_' || o.kind, o.id, null, null, o.exchange_id, null,
           case o.kind when 'opening' then '3100' else '3150' end,
           -(o.delta - case o.kind when 'opening' then o.released else 0 end)
      from openings o
    ------------------------------------------------ balance adjustments, at the cost of the day
    union all
    select a.created_at, 'adjustment', a.id, null, a.reason, a.exchange_id, null, '1300',
           round(a.delta * _cost_at(a.exchange_id, a.created_at), 2)
      from balance_adjustments a
     where a.owner_id = p_owner and coalesce(a.kind, 'adjust') = 'adjust'
       and _cost_at(a.exchange_id, a.created_at) is not null
    union all
    select a.created_at, 'adjustment', a.id, null, a.reason, a.exchange_id, null,
           case when a.delta > 0 then '4300' else '5100' end,
           -round(a.delta * _cost_at(a.exchange_id, a.created_at), 2)
      from balance_adjustments a
     where a.owner_id = p_owner and coalesce(a.kind, 'adjust') = 'adjust'
       and _cost_at(a.exchange_id, a.created_at) is not null
    ------------------------------------------------ commissions taken from an account
    union all
    select x.created_at, 'expense', x.id, x.code, x.note, x.exchange_id, null, '5300', x.v
      from (select e.*, round(e.amount * _cost_at(e.exchange_id, e.created_at), 2) as v
              from account_expenses e where e.owner_id = p_owner) x
     where x.v is not null
    union all
    select x.created_at, 'expense', x.id, x.code, x.note, x.exchange_id, null, '1300', -x.v
      from (select e.*, round(e.amount * _cost_at(e.exchange_id, e.created_at), 2) as v
              from account_expenses e where e.owner_id = p_owner) x
     where x.v is not null
    -- cancelled: the commission reversed as it was booked; the dollars back
    -- at the cost of that moment, the difference a revaluation
    union all
    select x.cancelled_at, 'expense_cancel', x.id, x.code, x.note, x.exchange_id, null, '5300', -x.v
      from (select e.*, round(e.amount * _cost_at(e.exchange_id, e.created_at), 2) as v
              from account_expenses e where e.owner_id = p_owner and e.cancelled_at is not null) x
     where x.v is not null
    union all
    select x.cancelled_at, 'expense_cancel', x.id, x.code, x.note, x.exchange_id, null, '1300', x.r
      from (select e.*, round(e.amount * _cost_at(e.exchange_id, e.cancelled_at), 2) as r
              from account_expenses e where e.owner_id = p_owner and e.cancelled_at is not null) x
     where x.r is not null
    union all
    select x.cancelled_at, 'expense_cancel', x.id, x.code, x.note, x.exchange_id, null,
           case when x.v is null then '3100' else '5900' end,
           coalesce(x.v, 0) - x.r
      from (select e.*, round(e.amount * _cost_at(e.exchange_id, e.created_at), 2) as v,
                   round(e.amount * _cost_at(e.exchange_id, e.cancelled_at), 2) as r
              from account_expenses e where e.owner_id = p_owner and e.cancelled_at is not null) x
     where x.r is not null and coalesce(x.v, 0) <> x.r
    ------------------------------------------------ customers: collections, payments, openings
    union all
    select e.created_at, 'customer_' || e.kind, e.id, null, e.note, null, e.client_id, '1200', e.amount
      from customer_lyd_entries e
     where e.owner_id = p_owner and e.kind in ('collect', 'pay', 'opening')
    union all
    select e.created_at, 'customer_' || e.kind, e.id, null, e.note, null, e.client_id,
           case when e.kind = 'opening' then '3100'
                when v_start is null or e.created_at < v_start then '3200'
                when e.pocket = 'bank' then '1110' else '1100' end,
           -e.amount
      from customer_lyd_entries e
     where e.owner_id = p_owner and e.kind in ('collect', 'pay', 'opening')
    ------------------------------------------------ the dinar treasury
    union all
    select t.started_at, 'lyd_opening', null::uuid, null, null, null, null, '1100', t.opening_cash
      from lyd_treasury t where t.owner_id = p_owner and t.opening_cash <> 0
    union all
    select t.started_at, 'lyd_opening', null, null, null, null, null, '1110', t.opening_bank
      from lyd_treasury t where t.owner_id = p_owner and t.opening_bank <> 0
    union all
    select t.started_at, 'lyd_opening', null, null, null, null, null, '3100',
           -(t.opening_cash + t.opening_bank)
      from lyd_treasury t where t.owner_id = p_owner and t.opening_cash + t.opening_bank <> 0
    union all
    select m.created_at, 'lyd_' || m.kind, m.id, null, m.note, null, null,
           case m.kind when 'in' then case m.pocket when 'bank' then '1110' else '1100' end
                       when 'out' then case m.pocket when 'bank' then '1110' else '1100' end
                       when 'cash_to_bank' then '1110'
                       when 'bank_to_cash' then '1100'
                       else '1100' end,
           case m.kind when 'in' then m.amount when 'out' then -m.amount
                       when 'count_short' then -m.amount else m.amount end
      from lyd_movements m where m.owner_id = p_owner
    union all
    select m.created_at, 'lyd_' || m.kind, m.id, null, m.note, null, null,
           case m.kind when 'in' then '3100' when 'out' then '3100'
                       when 'cash_to_bank' then '1100' when 'bank_to_cash' then '1110'
                       when 'count_over' then '4200' else '5200' end,
           case m.kind when 'in' then -m.amount when 'out' then m.amount
                       when 'count_short' then m.amount else -m.amount end
      from lyd_movements m where m.owner_id = p_owner
  )
  select l.* from lines l where l.amount is not null and l.amount <> 0;
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
    when '4100' then 'نتيجة بيع العملة'
    when '4200' then 'زيادة الجرد'
    when '4300' then 'أرباح تسوية الأرصدة'
    when '5100' then 'خسائر تسوية الأرصدة'
    when '5200' then 'عجز الجرد'
    when '5300' then 'العمولات'
    when '5900' then 'فروق التقريب'
    else p_code end
$$;

-- =============================================================================
-- B) the statements (administrator only)
-- =============================================================================
-- the cost changes found by their operation (the journal joins on it)
create index if not exists account_cost_events_operation_idx
  on account_cost_events (operation_id) where operation_id is not null;

create or replace function ledger_trial_balance(p_to timestamptz)
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
      from (select account,
                   coalesce(sum(amount) filter (where amount > 0), 0) as debit,
                   coalesce(-sum(amount) filter (where amount < 0), 0) as credit
              from _journal(v_admin) where at <= p_to
             group by account) j
  ), '[]'::jsonb);
end;
$$;
revoke all on function ledger_trial_balance(timestamptz) from public, anon;
grant execute on function ledger_trial_balance(timestamptz) to authenticated;

create or replace function ledger_income_statement(p_from timestamptz, p_to timestamptz)
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
    from (select account, -sum(amount) as result   -- income is credit: shown positive
            from _journal(v_admin)
           where at between p_from and p_to and account >= '4000'
           group by account) x
   where x.result <> 0;
  return jsonb_build_object('lines', v_rows, 'net', v_net);
end;
$$;
revoke all on function ledger_income_statement(timestamptz, timestamptz) from public, anon;
grant execute on function ledger_income_statement(timestamptz, timestamptz) to authenticated;

create or replace function ledger_balance_sheet(p_at timestamptz)
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
    select account, amount, client_id, exchange_id
      from _journal(v_admin) where at <= p_at
  )
  select jsonb_build_object(
    -- every balance-sheet account; the profit to date stays in one line
    'balances', coalesce((
      select jsonb_object_agg(x.account, x.bal)
        from (select case when account >= '4000' then 'profit' else account end as account,
                     sum(amount) as bal
                from j group by 1) x), '{}'::jsonb),
    -- the customers: what they owe us and what we owe them, apart
    'receivable', coalesce((select sum(b) from (select sum(amount) as b from j
                             where account = '1200' group by client_id) c where b > 0), 0),
    'payable', coalesce((select -sum(b) from (select sum(amount) as b from j
                          where account = '1200' group by client_id) c where b < 0), 0),
    -- each account's dollars: the ledger's value against balance × cost now
    'inventory', coalesce((
      select jsonb_agg(jsonb_build_object(
               'exchange_id', e.id, 'company_name', co.name, 'account_name', e.name,
               'balance', e.balance, 'cost_rate', ac.cost_rate,
               'book_value', round(e.balance * ac.cost_rate, 2),
               'ledger_value', coalesce(v.v, 0)) order by co.name, e.name)
        from exchanges e
        join companies co on co.id = e.company_id and co.owner_id = v_admin
        left join account_costs ac on ac.exchange_id = e.id
        left join (select exchange_id, sum(amount) as v from j
                    where account = '1300' group by exchange_id) v on v.exchange_id = e.id
    ), '[]'::jsonb)
  ) into v_out;
  return v_out;
end;
$$;
revoke all on function ledger_balance_sheet(timestamptz) from public, anon;
grant execute on function ledger_balance_sheet(timestamptz) to authenticated;

-- the journal of a period, the oldest first (at most 3000 lines)
create or replace function ledger_journal(p_from timestamptz, p_to timestamptz)
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
    select *, count(*) over () as total
      from _journal(v_admin) where at between p_from and p_to
     order by at, source_id
     limit 3000
  )
  select jsonb_build_object(
    'total', coalesce((select max(total) from j), 0),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'at', j.at, 'source', j.source, 'source_id', j.source_id, 'ref', j.ref,
               'memo', j.memo, 'account', j.account, 'name', _ledger_account_name(j.account),
               'amount', j.amount, 'exchange', ex.name, 'client', cl.name)
             order by j.at, j.source_id, j.amount desc)
        from j
        left join exchanges ex on ex.id = j.exchange_id
        left join clients cl on cl.id = j.client_id), '[]'::jsonb))
    into v_out;
  return v_out;
end;
$$;
revoke all on function ledger_journal(timestamptz, timestamptz) from public, anon;
grant execute on function ledger_journal(timestamptz, timestamptz) to authenticated;

-- =============================================================================
-- C) period closes: the trial balance sealed
-- =============================================================================
create table if not exists period_closes (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references profiles (id) on delete cascade,
  period_end   timestamptz not null,
  trial        jsonb not null,
  net_profit   numeric(14,2) not null,
  seal         text not null,
  seal_version integer not null default 1,
  note         text check (note is null or char_length(note) <= 300),
  closed_by    text,
  created_at   timestamptz not null default now()
);
create index if not exists period_closes_owner_idx on period_closes (owner_id, period_end desc);
alter table period_closes enable row level security;
revoke all on table period_closes from anon, authenticated;

-- the seal (version 1) of a trial balance: its accounts and amounts only —
-- renaming an account never breaks it
create or replace function _trial_seal(p_trial jsonb)
returns text
language sql
immutable
as $$
  select md5(coalesce(string_agg(
           (e ->> 'account') || ':'
             || round(coalesce((e ->> 'debit')::numeric, 0), 2)::text || ':'
             || round(coalesce((e ->> 'credit')::numeric, 0), 2)::text,
           '|' order by e ->> 'account'), ''))
    from jsonb_array_elements(coalesce(p_trial, '[]'::jsonb)) e
$$;

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
  v_trial := ledger_trial_balance(p_end);
  select coalesce(-sum(amount), 0) into v_net
    from _journal(v_admin)
   where at <= p_end and at > coalesce(
           (select max(period_end) from period_closes where owner_id = v_admin), '-infinity')
     and account >= '4000';
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''), u.email)
    into v_name from auth.users u where u.id = v_admin;
  insert into period_closes (owner_id, period_end, trial, net_profit, seal, note, closed_by)
  values (v_admin, p_end, v_trial, round(v_net, 2), _trial_seal(v_trial),
          nullif(btrim(coalesce(p_note, '')), ''), v_name)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'net_profit', round(v_net, 2));
end;
$$;
revoke all on function close_period(timestamptz, text) from public, anon;
grant execute on function close_period(timestamptz, text) to authenticated;

-- the closes, each checked against the ledger as it is now (the journal is
-- read once for all of them)
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
    select at, account, amount from _journal(v_admin)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'period_end', p.period_end, 'net_profit', p.net_profit,
           'note', p.note, 'closed_by', p.closed_by, 'created_at', p.created_at,
           'intact', p.seal = _trial_seal(coalesce((
             select jsonb_agg(jsonb_build_object('account', t.account,
                                                 'debit', t.debit, 'credit', t.credit))
               from (select account,
                            coalesce(sum(amount) filter (where amount > 0), 0) as debit,
                            coalesce(-sum(amount) filter (where amount < 0), 0) as credit
                       from j where at <= p.period_end group by account) t), '[]'::jsonb)))
         order by p.period_end desc), '[]'::jsonb)
    into v_out
    from period_closes p where p.owner_id = v_admin;
  return v_out;
end;
$$;
revoke all on function ledger_closes() from public, anon;
grant execute on function ledger_closes() to authenticated;

-- =============================================================================
-- D) reconciling an account with the exchange company's statement
-- =============================================================================
create table if not exists account_reconciliations (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references profiles (id) on delete cascade,
  exchange_id   uuid not null references exchanges (id) on delete cascade,
  at            timestamptz not null,
  their_balance numeric(14,2) not null,
  our_balance   numeric(14,2) not null,
  difference    numeric(14,2) not null,
  note          text check (note is null or char_length(note) <= 300),
  created_at    timestamptz not null default now()
);
create index if not exists account_reconciliations_idx
  on account_reconciliations (exchange_id, at desc);
alter table account_reconciliations enable row level security;
revoke all on table account_reconciliations from anon, authenticated;

-- an account's dollar balance at moment [p_at]: today's balance less
-- everything that moved it since
create or replace function _balance_at(p_exchange_id uuid, p_at timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public, extensions
as $$
  select e.balance
       + coalesce((select sum(t.amount) from transfers t
                    where t.exchange_id = e.id and t.status = 'archived' and t.created_at > p_at), 0)
       - coalesce((select sum(t.amount) from transfers t
                    where t.exchange_id = e.id and t.status = 'archived' and t.cancelled_at > p_at), 0)
       - coalesce((select sum(b.usd_amount) from currency_buys b
                    where b.exchange_id = e.id and b.status = 'archived' and b.created_at > p_at), 0)
       + coalesce((select sum(b.usd_amount) from currency_buys b
                    where b.exchange_id = e.id and b.status = 'archived' and b.cancelled_at > p_at), 0)
       + coalesce((select sum(x.amount) from account_expenses x
                    where x.exchange_id = e.id and x.created_at > p_at), 0)
       - coalesce((select sum(x.amount) from account_expenses x
                    where x.exchange_id = e.id and x.cancelled_at > p_at), 0)
       - coalesce((select sum(a.delta) from balance_adjustments a
                    where a.exchange_id = e.id and a.created_at > p_at), 0)
    from exchanges e where e.id = p_exchange_id
$$;
revoke all on function _balance_at(uuid, timestamptz) from public, anon, authenticated;

create or replace function reconcile_account(
  p_exchange_id uuid, p_at timestamptz, p_their_balance numeric, p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _lyd_admin();
  v_ours  numeric;
  v_theirs numeric := round(p_their_balance, 2);
begin
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from exchanges e join companies c on c.id = e.company_id
     where e.id = p_exchange_id and c.owner_id = v_admin
  ) then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_at is null or p_at > now() or v_theirs is null or abs(v_theirs) > 999999999999.99 then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  v_ours := round(_balance_at(p_exchange_id, p_at), 2);
  insert into account_reconciliations (owner_id, exchange_id, at, their_balance,
                                       our_balance, difference, note)
  values (v_admin, p_exchange_id, p_at, v_theirs, v_ours, v_theirs - v_ours,
          nullif(btrim(coalesce(p_note, '')), ''));
  return jsonb_build_object('ok', true, 'our_balance', v_ours,
                            'their_balance', v_theirs, 'difference', v_theirs - v_ours);
end;
$$;
revoke all on function reconcile_account(uuid, timestamptz, numeric, text) from public, anon;
grant execute on function reconcile_account(uuid, timestamptz, numeric, text) to authenticated;

create or replace function account_reconciliations_list(p_exchange_id uuid)
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
             'id', r.id, 'at', r.at, 'their_balance', r.their_balance,
             'our_balance', r.our_balance, 'difference', r.difference,
             'note', r.note, 'created_at', r.created_at) order by r.at desc, r.created_at desc)
      from account_reconciliations r
     where r.owner_id = v_admin and r.exchange_id = p_exchange_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function account_reconciliations_list(uuid) from public, anon;
grant execute on function account_reconciliations_list(uuid) to authenticated;

-- =============================================================================

-- E) backups, restores, the redaction and the wipe know the two new tables

--    (copied from their latest definition, 0091)

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
    'customer_lyd_entries', 'period_closes', 'account_reconciliations'
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
    'customer_lyd_entries', 'period_closes', 'account_reconciliations'
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
      when 'account_reconciliations' then 'r.exchange_id in (select id from public.exchanges)'
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
                        'customer_lyd_entries', 'period_closes',
                        'account_reconciliations') then
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
    'customer_lyd_entries', 'period_closes', 'account_reconciliations'
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

  -- the closes and reconciliations described what is being wiped
  delete from account_reconciliations where owner_id = v_owner;
  delete from period_closes where owner_id = v_owner;
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

commit;
