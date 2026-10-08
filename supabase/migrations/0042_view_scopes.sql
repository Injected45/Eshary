-- 0042_view_scopes.sql
-- Clearer view scopes for employees (refines 0041):
--
--   * An employee who may EXECUTE (transfers_create / buys_create) always sees
--     the operations THEY made today, with no extra permission.
--   * view_own  = their own full history (today's and closed).
--   * view_all  = EVERYONE's operations, today's and closed (was view_all_daily,
--     which covered today's only). Without it an employee never sees other
--     people's operations.
--
-- Existing grants of 'view_all_daily' are carried over as 'view_all'.

begin;

create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own',
               'view_all', 'archive_transfers', 'archive_buys']
$$;

update sub_users
   set permissions = array_replace(permissions, 'view_all_daily', 'view_all')
 where 'view_all_daily' = any (permissions);

drop policy if exists emp_perm_gate on transfers;
create policy emp_perm_gate on transfers
  as restrictive for select to authenticated
  using (
    (select current_employee_id()) is null
    or (select employee_has_perm('view_all'))
    or (
      created_by_employee_id = (select current_employee_id())
      and (
        (select employee_has_perm('view_own'))
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
    or (
      created_by_employee_id = (select current_employee_id())
      and (
        (select employee_has_perm('view_own'))
        or ((select employee_has_perm('buys_create'))
            and status in ('daily', 'pending'))
      )
    )
  );

commit;
