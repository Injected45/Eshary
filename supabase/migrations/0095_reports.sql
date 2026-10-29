-- 0095: the reports (phase 3). Computed in the database, so a phone never
-- downloads the history to add it up:
--
-- report_period(from, to): one period (a day is the end-of-day report) —
--   sales and purchases per book, the realized profit (as profit_report:
--   the dinars of a sale minus its dollars at the cost of that sale), the
--   dollars of each book and the dinars of the box and the bank at the start
--   and at the end, credit given / taken / collected / paid, cancellations,
--   per account, per day, per employee, and the previous period of the same
--   length for comparison.
-- report_debt_aging(): who owes us and since when (the oldest debts are paid
--   first), who is over his limit, and whom we owe.
--
-- Administrator only. Read only. Needs 0094. Safe to run more than once.

begin;

do $$
begin
  if to_regprocedure('public.admin_set_opening(uuid, text, numeric, numeric)') is null then
    raise exception 'شغّل الترحيل 0094 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- the dollars of an owner's [p_book] at a moment: what the books hold now
-- minus everything that moved them after it (as _balance_at, per book; the
-- dollars of a row saved before 0093 are the bank book's)
create or replace function _usd_book_at(p_owner uuid, p_book text, p_at timestamptz)
returns numeric
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce((select sum(b.balance) from account_books b
                    where b.owner_id = p_owner and b.book = p_book), 0)
       + coalesce((select sum(t.amount) from transfers t
                    where t.owner_id = p_owner and t.status = 'archived'
                      and coalesce(t.book, 'bank') = p_book and t.created_at > p_at), 0)
       - coalesce((select sum(t.amount) from transfers t
                    where t.owner_id = p_owner and t.status = 'archived'
                      and coalesce(t.book, 'bank') = p_book and t.cancelled_at > p_at), 0)
       - coalesce((select sum(c.usd_amount) from currency_buys c
                    where c.owner_id = p_owner and c.status = 'archived'
                      and coalesce(c.book, 'bank') = p_book and c.created_at > p_at), 0)
       + coalesce((select sum(c.usd_amount) from currency_buys c
                    where c.owner_id = p_owner and c.status = 'archived'
                      and coalesce(c.book, 'bank') = p_book and c.cancelled_at > p_at), 0)
       + coalesce((select sum(x.amount) from account_expenses x
                    where x.owner_id = p_owner
                      and coalesce(x.book, 'bank') = p_book and x.created_at > p_at), 0)
       - coalesce((select sum(x.amount) from account_expenses x
                    where x.owner_id = p_owner
                      and coalesce(x.book, 'bank') = p_book and x.cancelled_at > p_at), 0)
       - coalesce((select sum(a.delta) from balance_adjustments a
                    where a.owner_id = p_owner
                      and coalesce(a.book, 'bank') = p_book and a.created_at > p_at), 0)
       + coalesce((select sum(m.usd) from book_transfers m
                    where m.owner_id = p_owner and m.from_book = p_book and m.created_at > p_at), 0)
       - coalesce((select sum(m.usd) from book_transfers m
                    where m.owner_id = p_owner and m.to_book = p_book and m.created_at > p_at), 0)
$$;
revoke all on function _usd_book_at(uuid, text, timestamptz) from public, anon, authenticated;

create or replace function report_period(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_prev  timestamptz;
  v_open  boolean;
  v_lyd   jsonb;
  v_out   jsonb;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'period_invalid' using errcode = 'P0001';
  end if;
  if p_to - p_from > interval '400 days' then
    raise exception 'period_too_long' using errcode = 'P0001';
  end if;
  -- the previous period: as long, just before
  v_prev := p_from - (p_to - p_from);

  -- the dinars at the start and at the end: the ledger's box (1100) and bank
  -- (1110), which always equal the dinar treasury
  v_open := exists (select 1 from lyd_treasury where owner_id = v_admin);
  if v_open then
    select jsonb_build_object(
             'open', true,
             'cash_start', round(coalesce(sum(j.amount) filter (where j.account = '1100' and j.at < p_from), 0), 2),
             'cash_end',   round(coalesce(sum(j.amount) filter (where j.account = '1100' and j.at <= p_to), 0), 2),
             'bank_start', round(coalesce(sum(j.amount) filter (where j.account = '1110' and j.at < p_from), 0), 2),
             'bank_end',   round(coalesce(sum(j.amount) filter (where j.account = '1110' and j.at <= p_to), 0), 2))
      into v_lyd
      from _journal(v_admin) j
     where j.account in ('1100', '1110') and j.at <= p_to;
  else
    v_lyd := jsonb_build_object('open', false);
  end if;

  with s as (
    select (t.created_at at time zone 'Africa/Tripoli')::date as day,
           t.exchange_id, _book_of(t.book, t.lyd_method) as bk,
           t.amount as usd, t.lyd_amount as lyd,
           t.created_by_employee_id as emp,
           (t.rate is not null and oc.cost_after is not null) as priced,
           case when t.rate is not null and oc.cost_after is not null
                then round(t.amount * oc.cost_after, 2) end as cogs,
           greatest(coalesce(t.lyd_amount, 0) - coalesce(t.lyd_paid, t.lyd_amount, 0), 0) as unpaid,
           t.created_at >= p_from as cur
      from transfers t
      left join operation_costs oc on oc.operation_id = t.id and oc.kind = 'sell'
     where t.owner_id = v_admin and t.status = 'archived' and t.cancelled_at is null
       and t.created_at between v_prev and p_to
  ),
  b as (
    select (c.created_at at time zone 'Africa/Tripoli')::date as day,
           c.exchange_id, _book_of(c.book, c.lyd_method) as bk,
           c.usd_amount as usd, c.lyd_amount as lyd,
           c.created_by_employee_id as emp,
           greatest(coalesce(c.lyd_amount, 0) - coalesce(c.lyd_paid, c.lyd_amount, 0), 0) as unpaid,
           c.created_at >= p_from as cur
      from currency_buys c
     where c.owner_id = v_admin and c.status = 'archived' and c.cancelled_at is null
       and c.created_at between v_prev and p_to
  ),
  books(bk) as (values ('cash'), ('bank'))
  select jsonb_build_object(
    'from', p_from, 'to', p_to,
    -- per book
    'books', (
      select jsonb_agg(jsonb_build_object(
               'book', k.bk,
               'sale_n',     (select count(*) from s where s.cur and s.bk = k.bk),
               'sale_usd',   (select coalesce(sum(s.usd), 0) from s where s.cur and s.bk = k.bk),
               'sale_lyd',   (select coalesce(sum(s.lyd), 0) from s where s.cur and s.bk = k.bk),
               'sale_rated_usd', (select coalesce(sum(s.usd), 0) from s where s.cur and s.bk = k.bk and s.lyd is not null),
               'priced_usd', (select coalesce(sum(s.usd), 0) from s where s.cur and s.bk = k.bk and s.priced),
               'priced_lyd', (select coalesce(sum(s.lyd), 0) from s where s.cur and s.bk = k.bk and s.priced),
               'cogs',       (select coalesce(sum(s.cogs), 0) from s where s.cur and s.bk = k.bk and s.priced),
               'profit',     (select coalesce(sum(s.lyd - s.cogs), 0) from s where s.cur and s.bk = k.bk and s.priced),
               'unpriced_n', (select count(*) from s where s.cur and s.bk = k.bk and not s.priced),
               'buy_n',      (select count(*) from b where b.cur and b.bk = k.bk),
               'buy_usd',    (select coalesce(sum(b.usd), 0) from b where b.cur and b.bk = k.bk),
               'buy_lyd',    (select coalesce(sum(b.lyd), 0) from b where b.cur and b.bk = k.bk),
               'buy_rated_usd', (select coalesce(sum(b.usd), 0) from b where b.cur and b.bk = k.bk and b.lyd is not null),
               'usd_start',  _usd_book_at(v_admin, k.bk, p_from),
               'usd_end',    _usd_book_at(v_admin, k.bk, p_to))
             order by k.bk desc)
        from books k),
    'lyd', v_lyd,
    -- the previous period, for the comparison
    'previous', jsonb_build_object(
      'sale_n',   (select count(*) from s where not s.cur),
      'sale_usd', (select coalesce(sum(s.usd), 0) from s where not s.cur),
      'buy_n',    (select count(*) from b where not b.cur),
      'buy_usd',  (select coalesce(sum(b.usd), 0) from b where not b.cur),
      'profit',   (select coalesce(sum(s.lyd - s.cogs), 0) from s where not s.cur and s.priced)),
    'by_day', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', d.day, 'sale_n', d.sale_n, 'sale_usd', d.sale_usd, 'sale_lyd', d.sale_lyd,
               'buy_n', d.buy_n, 'buy_usd', d.buy_usd, 'buy_lyd', d.buy_lyd, 'profit', d.profit)
             order by d.day)
        from (
          select x.day,
                 count(*) filter (where x.k = 's') as sale_n,
                 coalesce(sum(x.usd) filter (where x.k = 's'), 0) as sale_usd,
                 coalesce(sum(x.lyd) filter (where x.k = 's'), 0) as sale_lyd,
                 count(*) filter (where x.k = 'b') as buy_n,
                 coalesce(sum(x.usd) filter (where x.k = 'b'), 0) as buy_usd,
                 coalesce(sum(x.lyd) filter (where x.k = 'b'), 0) as buy_lyd,
                 coalesce(sum(x.profit), 0) as profit
            from (select 's' as k, s.day, s.usd, s.lyd,
                         case when s.priced then s.lyd - s.cogs end as profit
                    from s where s.cur
                  union all
                  select 'b', b.day, b.usd, b.lyd, null from b where b.cur) x
           group by x.day) d), '[]'::jsonb),
    'by_account', coalesce((
      select jsonb_agg(jsonb_build_object(
               'exchange_id', a.exchange_id, 'company', co.name, 'account', e.name, 'book', a.bk,
               'sale_n', a.sale_n, 'sale_usd', a.sale_usd, 'sale_lyd', a.sale_lyd,
               'buy_n', a.buy_n, 'buy_usd', a.buy_usd, 'buy_lyd', a.buy_lyd, 'profit', a.profit)
             order by co.name, e.name, a.bk desc)
        from (
          select x.exchange_id, x.bk,
                 count(*) filter (where x.k = 's') as sale_n,
                 coalesce(sum(x.usd) filter (where x.k = 's'), 0) as sale_usd,
                 coalesce(sum(x.lyd) filter (where x.k = 's'), 0) as sale_lyd,
                 count(*) filter (where x.k = 'b') as buy_n,
                 coalesce(sum(x.usd) filter (where x.k = 'b'), 0) as buy_usd,
                 coalesce(sum(x.lyd) filter (where x.k = 'b'), 0) as buy_lyd,
                 coalesce(sum(x.profit), 0) as profit
            from (select 's' as k, s.exchange_id, s.bk, s.usd, s.lyd,
                         case when s.priced then s.lyd - s.cogs end as profit
                    from s where s.cur
                  union all
                  select 'b', b.exchange_id, b.bk, b.usd, b.lyd, null from b where b.cur) x
           group by x.exchange_id, x.bk) a
        join exchanges e on e.id = a.exchange_id
        join companies co on co.id = e.company_id), '[]'::jsonb),
    -- per employee (null = the administrator)
    'by_employee', coalesce((
      select jsonb_agg(jsonb_build_object(
               'employee_id', w.emp,
               'name', case when w.emp is null then 'المدير' else coalesce(su.employee_name, '—') end,
               'sale_n', w.sale_n, 'sale_usd', w.sale_usd, 'sale_lyd', w.sale_lyd,
               'buy_n', w.buy_n, 'buy_usd', w.buy_usd, 'buy_lyd', w.buy_lyd,
               'profit', w.profit, 'credit_given', w.credit_given,
               'cancelled_n', (select count(*) from operation_cancellations oc2
                                where oc2.owner_id = v_admin
                                  and oc2.operation_employee_id is not distinct from w.emp
                                  and oc2.cancelled_at between p_from and p_to))
             order by (w.sale_usd + w.buy_usd) desc)
        from (
          select x.emp,
                 count(*) filter (where x.k = 's') as sale_n,
                 coalesce(sum(x.usd) filter (where x.k = 's'), 0) as sale_usd,
                 coalesce(sum(x.lyd) filter (where x.k = 's'), 0) as sale_lyd,
                 count(*) filter (where x.k = 'b') as buy_n,
                 coalesce(sum(x.usd) filter (where x.k = 'b'), 0) as buy_usd,
                 coalesce(sum(x.lyd) filter (where x.k = 'b'), 0) as buy_lyd,
                 coalesce(sum(x.profit), 0) as profit,
                 coalesce(sum(x.unpaid) filter (where x.k = 's'), 0) as credit_given
            from (select 's' as k, s.emp, s.usd, s.lyd, s.unpaid,
                         case when s.priced then s.lyd - s.cogs end as profit
                    from s where s.cur
                  union all
                  select 'b', b.emp, b.usd, b.lyd, b.unpaid, null from b where b.cur) x
           group by x.emp) w
        left join sub_users su on su.id = w.emp), '[]'::jsonb),
    -- credit (customer dinars) during the period
    'credit', (
      select jsonb_build_object(
               'given',     coalesce(sum(e.amount) filter (where e.kind = 'sale'), 0),
               'taken',     coalesce(-sum(e.amount) filter (where e.kind = 'buy'), 0),
               'collected', coalesce(-sum(e.amount) filter (where e.kind = 'collect'), 0),
               'paid',      coalesce(sum(e.amount) filter (where e.kind = 'pay'), 0))
        from customer_lyd_entries e
       where e.owner_id = v_admin and e.created_at between p_from and p_to),
    -- what customers owe us / we owe them at the end of the period
    'credit_end', (
      select jsonb_build_object(
               'owed_to_us', coalesce(sum(x.bal) filter (where x.bal > 0), 0),
               'we_owe',     coalesce(-sum(x.bal) filter (where x.bal < 0), 0))
        from (select e.client_id, sum(e.amount) as bal
                from customer_lyd_entries e
               where e.owner_id = v_admin and e.created_at <= p_to
               group by e.client_id) x),
    'cancels', (
      select jsonb_build_object(
               'n', count(*),
               'sale_n', count(*) filter (where oc3.kind = 'transfer'),
               'sale_usd', coalesce(sum(oc3.amount) filter (where oc3.kind = 'transfer'), 0),
               'buy_n', count(*) filter (where oc3.kind = 'buy'),
               'buy_usd', coalesce(sum(oc3.amount) filter (where oc3.kind = 'buy'), 0))
        from operation_cancellations oc3
       where oc3.owner_id = v_admin and oc3.cancelled_at between p_from and p_to)
  ) into v_out;
  return v_out;
end;
$$;
revoke all on function report_period(timestamptz, timestamptz) from public, anon;
grant execute on function report_period(timestamptz, timestamptz) to authenticated;

-- who owes us and since when: the oldest debts are paid first, so what is
-- still owed is the most recent debts adding up to the balance
create or replace function report_debt_aging()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  return (
    with bal as (
      select e.client_id,
             sum(e.amount) as owed,
             coalesce(sum(e.amount) filter (where coalesce(e.book, 'bank') = 'cash'), 0) as cash,
             coalesce(sum(e.amount) filter (where coalesce(e.book, 'bank') = 'bank'), 0) as bank,
             max(e.created_at) filter (where e.kind = 'collect') as last_collect
        from customer_lyd_entries e
       where e.owner_id = v_admin
       group by e.client_id
    ),
    deb as (
      select d.client_id, d.created_at, d.amount,
             sum(d.amount) over (partition by d.client_id
                                 order by d.created_at desc, d.id desc) as cum
        from customer_lyd_entries d
        join bal on bal.client_id = d.client_id and bal.owed > 0.005
       where d.owner_id = v_admin and d.amount > 0
    ),
    left_owed as (
      select deb.client_id, deb.created_at,
             least(deb.amount, bal.owed - (deb.cum - deb.amount)) as part
        from deb join bal on bal.client_id = deb.client_id
       where deb.cum - deb.amount < bal.owed
    ),
    aged as (
      select l.client_id,
             coalesce(sum(l.part) filter (where l.created_at > now() - interval '7 days'), 0) as d7,
             coalesce(sum(l.part) filter (where l.created_at <= now() - interval '7 days'
                                            and l.created_at > now() - interval '30 days'), 0) as d30,
             coalesce(sum(l.part) filter (where l.created_at <= now() - interval '30 days'
                                            and l.created_at > now() - interval '90 days'), 0) as d90,
             coalesce(sum(l.part) filter (where l.created_at <= now() - interval '90 days'), 0) as older,
             min(l.created_at) as oldest
        from left_owed l
       group by l.client_id
    )
    select jsonb_build_object(
      'debtors', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'client_id', c.id, 'name', c.name, 'company', c.company,
                 'limit', c.credit_limit, 'owed', round(bal.owed, 2),
                 'cash', round(bal.cash, 2), 'bank', round(bal.bank, 2),
                 'd7', round(a.d7, 2), 'd30', round(a.d30, 2),
                 'd90', round(a.d90, 2), 'older', round(a.older, 2),
                 'oldest', a.oldest, 'last_collect', bal.last_collect,
                 'over_limit', bal.owed > coalesce(c.credit_limit, 0) + 0.005)
               order by a.older desc, a.d90 desc, bal.owed desc)
          from bal
          join clients c on c.id = bal.client_id
          left join aged a on a.client_id = bal.client_id
         where bal.owed > 0.005), '[]'::jsonb),
      'creditors', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'client_id', c.id, 'name', c.name, 'company', c.company,
                 'owed', round(-bal.owed, 2),
                 'cash', round(-bal.cash, 2), 'bank', round(-bal.bank, 2))
               order by bal.owed)
          from bal join clients c on c.id = bal.client_id
         where bal.owed < -0.005), '[]'::jsonb)
    )
  );
end;
$$;
revoke all on function report_debt_aging() from public, anon;
grant execute on function report_debt_aging() to authenticated;

commit;
