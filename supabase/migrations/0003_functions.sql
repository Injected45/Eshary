-- 0003_functions.sql
-- Business logic functions: archival + reference generator.
-- All functions are SECURITY INVOKER and explicitly check the caller's
-- ownership against auth.uid(); RLS still applies on top.

begin;

-- =========================================================================
-- archive_daily_transfers(p_owner uuid)
-- Flips every transfer with status='daily' belonging to p_owner to
-- 'archived', stamping archived_at = now(). Returns the affected row count.
-- Mirrors archiveAllDailyTransfers() (project_web.html:588).
-- =========================================================================

create or replace function archive_daily_transfers(p_owner uuid)
returns integer
language plpgsql
security invoker
as $$
declare
  v_count integer;
begin
  if p_owner is null or p_owner <> auth.uid() then
    raise exception 'not authorized: p_owner must equal auth.uid()';
  end if;

  update transfers
     set status      = 'archived',
         archived_at = now()
   where owner_id = p_owner
     and status   = 'daily';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- =========================================================================
-- archive_daily_buys(p_owner uuid)
-- Flips every currency_buy with status='daily' belonging to p_owner to
-- 'archived'. Refuses to run when the caller still has any pending buys —
-- the source UI displays pending rows but never blocks archival; we enforce
-- the block here as required by the Phase 1 spec.
-- Mirrors archiveAllDailyBuy() (project_web.html:598).
-- =========================================================================

create or replace function archive_daily_buys(p_owner uuid)
returns integer
language plpgsql
security invoker
as $$
declare
  v_count   integer;
  v_pending integer;
begin
  if p_owner is null or p_owner <> auth.uid() then
    raise exception 'not authorized: p_owner must equal auth.uid()';
  end if;

  select count(*) into v_pending
    from currency_buys
   where owner_id = p_owner
     and status   = 'pending';

  if v_pending > 0 then
    raise exception 'cannot archive: % pending currency buy(s) must be resolved first', v_pending
      using errcode = 'check_violation';
  end if;

  update currency_buys
     set status      = 'archived',
         archived_at = now()
   where owner_id = p_owner
     and status   = 'daily';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- =========================================================================
-- next_reference(p_company_id uuid)
-- Returns the next reference string for a transfer, in the form
-- '{start_ref}-{N}'.
--
-- Faithfully ports project_web.html:711:
--   company.startRef + "-" + (db.dailyTransfers.length
--                             + db.globalSold.length + 101)
-- The JS counts ALL of the user's transfers (both 'daily' and 'archived'),
-- not only those belonging to the selected company. We preserve that
-- behavior: N = (count of every transfer owned by the company's owner) + 101.
-- The selected company only contributes its start_ref prefix.
-- =========================================================================

create or replace function next_reference(p_company_id uuid)
returns text
language plpgsql
security invoker
as $$
declare
  v_owner     uuid;
  v_start_ref text;
  v_count     integer;
begin
  select owner_id, start_ref
    into v_owner, v_start_ref
    from companies
   where id = p_company_id;

  if v_owner is null then
    raise exception 'company % not found', p_company_id;
  end if;

  if v_owner <> auth.uid() then
    raise exception 'not authorized: company does not belong to auth.uid()';
  end if;

  select count(*) into v_count
    from transfers
   where owner_id = v_owner;

  return v_start_ref || '-' || (v_count + 101)::text;
end;
$$;

commit;
