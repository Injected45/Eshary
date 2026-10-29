-- 0096: «كشف المديونيات» — report_debt_aging (0095) for BOTH sides with the
-- same details, to follow every debt by name:
--   debtors   (they owe us)  and   creditors (we owe them),
-- each with the code, the cash and bank parts, the ageing (≤ 7 / 8–30 /
-- 31–90 / > 90 days; the oldest debts are taken as settled first), the
-- oldest open debt, the last settlement (a collection from a debtor, a
-- payment to a creditor), the last movement, and the limit (debtors).
-- The keys 0095 sent are kept, so 1.0.16 reads it as before.
--
-- Administrator only. Read only. Needs 0095. Safe to run more than once.

begin;

do $$
begin
  if to_regprocedure('public.report_debt_aging()') is null then
    raise exception 'شغّل الترحيل 0095 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

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
             sum(e.amount) as owed,             -- + they owe us, − we owe them
             coalesce(sum(e.amount) filter (where coalesce(e.book, 'bank') = 'cash'), 0) as cash,
             coalesce(sum(e.amount) filter (where coalesce(e.book, 'bank') = 'bank'), 0) as bank,
             max(e.created_at) filter (where e.kind = 'collect') as last_collect,
             max(e.created_at) filter (where e.kind = 'pay') as last_pay,
             max(e.created_at) as last_move
        from customer_lyd_entries e
       where e.owner_id = v_admin
       group by e.client_id
      having abs(sum(e.amount)) > 0.005
    ),
    -- the entries that made the balance, newest first, on its side only
    side as (
      select d.client_id, d.created_at, abs(d.amount) as amount,
             sum(abs(d.amount)) over (partition by d.client_id
                                      order by d.created_at desc, d.id desc) as cum
        from customer_lyd_entries d
        join bal on bal.client_id = d.client_id
       where d.owner_id = v_admin and sign(d.amount) = sign(bal.owed)
    ),
    open_part as (
      select s.client_id, s.created_at,
             least(s.amount, abs(bal.owed) - (s.cum - s.amount)) as part
        from side s join bal on bal.client_id = s.client_id
       where s.cum - s.amount < abs(bal.owed)
    ),
    aged as (
      select o.client_id,
             coalesce(sum(o.part) filter (where o.created_at > now() - interval '7 days'), 0) as d7,
             coalesce(sum(o.part) filter (where o.created_at <= now() - interval '7 days'
                                            and o.created_at > now() - interval '30 days'), 0) as d30,
             coalesce(sum(o.part) filter (where o.created_at <= now() - interval '30 days'
                                            and o.created_at > now() - interval '90 days'), 0) as d90,
             coalesce(sum(o.part) filter (where o.created_at <= now() - interval '90 days'), 0) as older,
             min(o.created_at) as oldest
        from open_part o
       group by o.client_id
    ),
    rows as (
      select c.id, c.name, c.company, c.code, c.credit_limit,
             bal.owed, bal.cash, bal.bank, bal.last_collect, bal.last_pay, bal.last_move,
             coalesce(a.d7, 0) as d7, coalesce(a.d30, 0) as d30,
             coalesce(a.d90, 0) as d90, coalesce(a.older, 0) as older, a.oldest
        from bal
        join clients c on c.id = bal.client_id
        left join aged a on a.client_id = bal.client_id
    )
    select jsonb_build_object(
      'debtors', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'client_id', r.id, 'name', r.name, 'company', r.company, 'code', r.code,
                 'limit', r.credit_limit, 'owed', round(r.owed, 2),
                 'cash', round(r.cash, 2), 'bank', round(r.bank, 2),
                 'd7', round(r.d7, 2), 'd30', round(r.d30, 2),
                 'd90', round(r.d90, 2), 'older', round(r.older, 2),
                 'oldest', r.oldest, 'last_collect', r.last_collect,
                 'last_settle', r.last_collect, 'last_move', r.last_move,
                 'over_limit', r.owed > coalesce(r.credit_limit, 0) + 0.005)
               order by r.older desc, r.d90 desc, r.owed desc)
          from rows r where r.owed > 0), '[]'::jsonb),
      'creditors', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'client_id', r.id, 'name', r.name, 'company', r.company, 'code', r.code,
                 'owed', round(-r.owed, 2),
                 'cash', round(-r.cash, 2), 'bank', round(-r.bank, 2),
                 'd7', round(r.d7, 2), 'd30', round(r.d30, 2),
                 'd90', round(r.d90, 2), 'older', round(r.older, 2),
                 'oldest', r.oldest, 'last_settle', r.last_pay, 'last_move', r.last_move)
               order by r.older desc, r.d90 desc, r.owed)
          from rows r where r.owed < 0), '[]'::jsonb)
    )
  );
end;
$$;
revoke all on function report_debt_aging() from public, anon;
grant execute on function report_debt_aging() to authenticated;

commit;
