-- 0022_effective_admin_id.sql
-- Phase 3a of the Employee Management module — security foundation only.
-- Introduces `effective_admin_id()` and switches SELECT policies on the
-- workflow tables to use it. INSERT/UPDATE/DELETE policies stay on
-- `auth.uid()` so employees cannot write directly — Phase 3b will add
-- security-definer RPCs to handle their writes with proper attribution.
--
-- Result after this migration:
--   - Admin: behaves exactly as before (effective_admin_id() = auth.uid()).
--   - Employee (anonymous w/ active session): can READ their admin's data
--     but cannot INSERT/UPDATE/DELETE anything directly.
--   - Unsigned visitor: still sees nothing.

begin;

-- ============================================================================
-- effective_admin_id(): the uid whose data the caller is currently acting on.
--   - For admins: their own auth.uid().
--   - For employees (anonymous JWT with active employee_session): the
--     parent_admin_id of the linked sub_user.
--   - Otherwise: null (denies everything via owner_id = null).
--
-- SECURITY DEFINER so it can read employee_sessions + sub_users despite
-- their RLS policies. STABLE because the same JWT yields the same answer
-- for the duration of a query, letting Postgres cache it.
-- ============================================================================
create or replace function effective_admin_id()
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

  -- No active employee session → caller is the admin (or some other
  -- authenticated user with no employee link → their own uid).
  return coalesce(v_parent, auth.uid());
end;
$$;

grant execute on function effective_admin_id() to authenticated;

-- ============================================================================
-- Workflow tables: replace SELECT policies only. INSERT/UPDATE/DELETE
-- policies are intentionally left on auth.uid() so an employee's
-- anonymous JWT cannot write directly. Phase 3b adds RPCs for writes.
-- ============================================================================

-- companies -----------------------------------------------------------------
drop policy if exists companies_select_own on companies;
create policy companies_select_own on companies
  for select using (owner_id = effective_admin_id());

-- exchanges (ownership cascades via companies) -------------------------------
drop policy if exists exchanges_select_own on exchanges;
create policy exchanges_select_own on exchanges
  for select using (
    exists (
      select 1 from companies c
       where c.id = exchanges.company_id
         and c.owner_id = effective_admin_id()
    )
  );

-- clients --------------------------------------------------------------------
drop policy if exists clients_select_own on clients;
create policy clients_select_own on clients
  for select using (owner_id = effective_admin_id());

-- transfers ------------------------------------------------------------------
drop policy if exists transfers_select_own on transfers;
create policy transfers_select_own on transfers
  for select using (owner_id = effective_admin_id());

-- currency_buys --------------------------------------------------------------
drop policy if exists currency_buys_select_own on currency_buys;
create policy currency_buys_select_own on currency_buys
  for select using (owner_id = effective_admin_id());

-- beneficiaries --------------------------------------------------------------
drop policy if exists beneficiaries_select_own on beneficiaries;
create policy beneficiaries_select_own on beneficiaries
  for select using (owner_id = effective_admin_id());

-- exchange_companies ---------------------------------------------------------
drop policy if exists ec_select_own on exchange_companies;
create policy ec_select_own on exchange_companies
  for select using (owner_id = effective_admin_id());

-- countries ------------------------------------------------------------------
drop policy if exists countries_select_own on countries;
create policy countries_select_own on countries
  for select using (owner_id = effective_admin_id());

-- branches (already uses parent_admin_id as the ownership column) ------------
drop policy if exists branches_select_own on branches;
create policy branches_select_own on branches
  for select to authenticated
  using (parent_admin_id = effective_admin_id());

commit;
