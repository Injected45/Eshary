-- 0044_scoped_close.sql
-- The daily close for an employee is now limited to THEIR OWN operations.
--
--   archive_transfers / archive_buys  close only the operations the employee made
--   archive_all (new)                 together with the above, closes EVERYONE's
--
-- Before this, an employee with archive_transfers closed every open transfer of
-- the company (the admin's and other employees' included). The admin is
-- unchanged: closing always covers everything.
--
-- The account balances move by the total of the rows actually closed, per
-- account, exactly as before.

begin;

create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'archive_transfers', 'archive_buys', 'archive_all',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all']
$$;

create or replace function archive_daily_transfers(p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_emp   uuid := current_employee_id();
  v_only  uuid;
  v_count integer;
begin
  if v_admin is null or p_owner is distinct from v_admin then
    raise exception 'not_authorized';
  end if;
  if v_emp is not null then
    if not employee_has_perm('archive_transfers') then
      raise exception 'permission_denied' using errcode = 'P0001';
    end if;
    -- only their own rows, unless they may close everyone's
    if not employee_has_perm('archive_all') then
      v_only := v_emp;
    end if;
  end if;

  with t_sums as (
    select exchange_id, sum(amount) as s
      from transfers
     where status = 'daily' and owner_id = p_owner
       and (v_only is null or created_by_employee_id = v_only)
     group by exchange_id
  )
  update exchanges e
     set balance = e.balance - t_sums.s
    from t_sums
   where e.id = t_sums.exchange_id;

  update transfers
     set status = 'archived', archived_at = now()
   where status = 'daily' and owner_id = p_owner
     and (v_only is null or created_by_employee_id = v_only);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function archive_daily_buys(p_owner uuid)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_emp   uuid := current_employee_id();
  v_only  uuid;
  v_pending_count integer;
  v_count integer;
begin
  if v_admin is null or p_owner is distinct from v_admin then
    raise exception 'not_authorized';
  end if;
  if v_emp is not null then
    if not employee_has_perm('archive_buys') then
      raise exception 'permission_denied' using errcode = 'P0001';
    end if;
    if not employee_has_perm('archive_all') then
      v_only := v_emp;
    end if;
  end if;

  select count(*) into v_pending_count
    from currency_buys
   where status = 'pending' and owner_id = p_owner
     and (v_only is null or created_by_employee_id = v_only);
  if v_pending_count > 0 then
    raise exception 'pending currency buy rows exist for owner: %',
      v_pending_count;
  end if;

  with b_sums as (
    select exchange_id, sum(usd_amount) as s
      from currency_buys
     where status = 'daily' and owner_id = p_owner
       and (v_only is null or created_by_employee_id = v_only)
     group by exchange_id
  )
  update exchanges e
     set balance = e.balance + b_sums.s
    from b_sums
   where e.id = b_sums.exchange_id;

  update currency_buys
     set status = 'archived', archived_at = now()
   where status = 'daily' and owner_id = p_owner
     and (v_only is null or created_by_employee_id = v_only);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

commit;
