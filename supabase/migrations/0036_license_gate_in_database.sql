-- 0036_license_gate_in_database.sql
-- SECURITY: enforce the licence in the DATABASE, not only in the app.
--
-- Until now the licence (pending / trial / active / expired / blocked) was only
-- checked by the Flutter router. The row-level-security policies on the business
-- tables looked at ownership only, so anyone could register (sign-up is open)
-- or be blocked and still read and write their own rows by calling the API
-- directly with their token, skipping the app entirely.
--
-- After this migration an account whose licence is not valid gets NOTHING from
-- the business tables, whatever client it uses:
--
--   * effective_admin_id() now returns NULL unless the account being acted on
--     (the admin itself, or an employee's parent admin) holds a valid licence.
--     That already blocks every read policy and every security-definer function
--     that resolves the owner through it (employee writes included).
--   * a RESTRICTIVE policy `license_gate` on each business table also blocks
--     direct inserts / updates / deletes (those policies use auth.uid()).
--
-- Valid = status 'active', or 'trial' that has not ended. Same rule as
-- current_license_status().is_valid.
--
-- Roll back (if ever needed):
--   do $$ declare t text; begin
--     foreach t in array array['companies','exchanges','clients','transfers',
--       'currency_buys','beneficiaries','exchange_companies','countries',
--       'branches','sub_users'] loop
--       execute format('drop policy if exists license_gate on public.%I', t);
--     end loop; end $$;
--   (and re-create effective_admin_id() from 0022).

begin;

-- The old resolver, unchanged, under a private name.
create or replace function _raw_admin_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_parent uuid;
begin
  if auth.uid() is null then
    return null;
  end if;

  select su.parent_admin_id
    into v_parent
    from employee_sessions es
    join sub_users su on su.id = es.sub_user_id
   where es.anonymous_user_id = auth.uid()
     and es.is_active = true
     and su.status = 'active'
   limit 1;

  return coalesce(v_parent, auth.uid());
end;
$$;
revoke all on function _raw_admin_id() from public, anon, authenticated;

-- Same name and signature as 0022, so every policy and function using it picks
-- the gate up with no other change.
create or replace function effective_admin_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _raw_admin_id();
begin
  if v_admin is null then
    return null;
  end if;

  if exists (
    select 1
      from account_licenses l
     where l.user_id = v_admin
       and (
         l.status = 'active'
         or (l.status = 'trial'
             and l.trial_ends_at is not null
             and l.trial_ends_at > now())
       )
  ) then
    return v_admin;
  end if;

  return null;
end;
$$;

create or replace function license_ok()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select effective_admin_id() is not null
$$;
revoke all on function license_ok() from public, anon;
grant execute on function license_ok() to authenticated;

-- A restrictive policy is ANDed with the existing permissive ones, so it can
-- only remove access, never grant any. It covers select / insert / update /
-- delete (for "all", the check clause defaults to the using clause).
do $$
declare
  t text;
begin
  foreach t in array array[
    'companies', 'exchanges', 'clients', 'transfers', 'currency_buys',
    'beneficiaries', 'exchange_companies', 'countries', 'branches', 'sub_users'
  ] loop
    if to_regclass('public.' || quote_ident(t)) is not null then
      execute format('drop policy if exists license_gate on public.%I', t);
      execute format(
        'create policy license_gate on public.%I as restrictive for all to authenticated using ((select license_ok()))',
        t
      );
    end if;
  end loop;
end;
$$;

commit;
