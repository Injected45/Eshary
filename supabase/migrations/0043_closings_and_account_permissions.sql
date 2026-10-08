-- 0043_closings_and_account_permissions.sql
-- Four more employee permissions, so the whole app is covered:
--
--   closings_own   الإقفالات: tab visible; sees only the closed operations THEY made
--   closings_all   الإقفالات: tab visible; sees every closed operation
--   accounts_own   حسابي: tab visible; sees only a summary of what THEY did, per account
--   accounts_all   حسابي: tab visible; sees the whole account (all accounts and balances)
--
-- Row-level security (restrictive, only ever removes access) becomes:
--   transfers / currency_buys visible to an employee when
--     view_all                                         -> everything
--     closings_all                                     -> every closed row
--     created by them AND ( view_own | accounts_own
--                           | closings_own (closed rows)
--                           | transfers_create / buys_create (today's rows) )
--   lookup tables (companies, accounts, parties, ...) are readable when the
--   employee may execute, view closings, or has accounts_all. accounts_own does
--   NOT open them: that employee gets employee_my_account(), a summary of their
--   own work, instead of the account tables.
--
-- Known limit: anyone allowed to read the account tables (to execute, to view
-- closings, or accounts_all) can also read the balances at the API level; the
-- app only DISPLAYS them with accounts_all or on the execution screens.

begin;

create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'archive_transfers', 'archive_buys',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all']
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'companies', 'exchanges', 'clients', 'beneficiaries',
    'exchange_companies', 'countries', 'branches'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format('drop policy if exists emp_perm_gate on public.%I', t);
      execute format(
        'create policy emp_perm_gate on public.%I as restrictive for select to authenticated '
        'using ((select current_employee_id()) is null '
        'or (select employee_has_any_perm(array[''transfers_create'',''buys_create'','
        '''closings_own'',''closings_all'',''accounts_all''])))',
        t);
    end if;
  end loop;
end;
$$;

drop policy if exists emp_perm_gate on transfers;
create policy emp_perm_gate on transfers
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or (select employee_has_perm('view_all'))
    or ((select employee_has_perm('closings_all')) and status = 'archived')
    or (
      created_by_employee_id = (select current_employee_id())
      and (
        (select employee_has_perm('view_own'))
        or (select employee_has_perm('accounts_own'))
        or ((select employee_has_perm('closings_own')) and status = 'archived')
        or ((select employee_has_perm('transfers_create')) and status = 'daily')
      )
    )
  );

drop policy if exists emp_perm_gate on currency_buys;
create policy emp_perm_gate on currency_buys
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or (select employee_has_perm('view_all'))
    or ((select employee_has_perm('closings_all')) and status = 'archived')
    or (
      created_by_employee_id = (select current_employee_id())
      and (
        (select employee_has_perm('view_own'))
        or (select employee_has_perm('accounts_own'))
        or ((select employee_has_perm('closings_own')) and status = 'archived')
        or ((select employee_has_perm('buys_create'))
            and status in ('daily', 'pending'))
      )
    )
  );

-- -------------------------------------------------------------------------
-- accounts_own: what THIS employee did, per account. Reads only their own rows
-- and exposes no balance.
-- -------------------------------------------------------------------------
create or replace function employee_my_account()
returns table (
  company_name     text,
  exchange_name    text,
  our_code         text,
  out_open_count   integer,
  out_open_total   numeric,
  out_closed_count integer,
  out_closed_total numeric,
  in_open_count    integer,
  in_open_total    numeric,
  in_closed_count  integer,
  in_closed_total  numeric
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_emp   uuid := current_employee_id();
  v_admin uuid := effective_admin_id();
begin
  if v_emp is null or v_admin is null then
    raise exception 'not_authorized';
  end if;
  if not employee_has_perm('accounts_own') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;

  return query
  with mine_t as (
    select t.exchange_id, t.company_id, t.status::text as status, t.amount
      from transfers t
     where t.owner_id = v_admin and t.created_by_employee_id = v_emp
  ),
  mine_b as (
    select b.exchange_id, b.my_company_id as company_id, b.status::text as status,
           b.usd_amount as amount
      from currency_buys b
     where b.owner_id = v_admin and b.created_by_employee_id = v_emp
  ),
  keys as (
    select m.exchange_id, m.company_id from mine_t m
    union
    select m.exchange_id, m.company_id from mine_b m
  )
  select
    c.name::text,
    e.name::text,
    e.our_code::text,
    (select count(*)::int from mine_t m
      where m.exchange_id = k.exchange_id and m.status = 'daily'),
    (select coalesce(sum(m.amount), 0) from mine_t m
      where m.exchange_id = k.exchange_id and m.status = 'daily'),
    (select count(*)::int from mine_t m
      where m.exchange_id = k.exchange_id and m.status = 'archived'),
    (select coalesce(sum(m.amount), 0) from mine_t m
      where m.exchange_id = k.exchange_id and m.status = 'archived'),
    (select count(*)::int from mine_b m
      where m.exchange_id = k.exchange_id and m.status in ('daily', 'pending')),
    (select coalesce(sum(m.amount), 0) from mine_b m
      where m.exchange_id = k.exchange_id and m.status in ('daily', 'pending')),
    (select count(*)::int from mine_b m
      where m.exchange_id = k.exchange_id and m.status = 'archived'),
    (select coalesce(sum(m.amount), 0) from mine_b m
      where m.exchange_id = k.exchange_id and m.status = 'archived')
  from keys k
  join exchanges e on e.id = k.exchange_id
  join companies c on c.id = k.company_id
  order by c.name, e.name;
end;
$$;
revoke all on function employee_my_account() from public, anon;
grant execute on function employee_my_account() to authenticated;

commit;
