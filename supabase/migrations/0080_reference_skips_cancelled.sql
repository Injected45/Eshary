-- 0080_reference_skips_cancelled.sql
-- A cancelled transfer no longer uses up its reference number. The companies
-- we send to number our transfers in sequence and never see a cancelled one:
-- cancel RH0102, send the next one as RH0103, and their statement records it
-- as 0102. So:
--
--   * the LAST transfer was cancelled  -> the next transfer gets its number
--     again (the cancelled row keeps it too, marked cancelled);
--   * an EARLIER one was cancelled while later ones are still active -> the
--     numbering never goes back and never repeats an active number: it goes
--     on after the highest active number.
--
-- next = greatest(start + active transfers, highest active number + 1)
--
-- With no cancellation this is exactly the old formula (start + every
-- transfer, counted across all the administrator's companies, as
-- project_web.html:711). Only next_reference changes; no row is touched.
-- Safe to run more than once.

begin;

create or replace function next_reference(p_company_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_id    uuid := effective_admin_id();
  v_owner       uuid;
  v_start_ref   text;
  v_count       integer;
  v_match       text[];
  v_prefix      text;
  v_first       numeric;
  v_pad_width   integer;
  v_max         numeric;
begin
  if v_admin_id is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select owner_id, start_ref
    into v_owner, v_start_ref
    from companies
   where id = p_company_id;

  if v_owner is null then
    raise exception 'company % not found', p_company_id;
  end if;
  if v_owner <> v_admin_id then
    raise exception 'not_authorized: company does not belong to caller';
  end if;

  -- active transfers only: a cancelled one gives its number back
  select count(*) into v_count
    from transfers
   where owner_id = v_owner
     and cancelled_at is null;

  v_match := regexp_match(coalesce(v_start_ref, ''), '^([^0-9]*)([0-9]+)$');
  if v_match is not null then
    v_prefix    := v_match[1];
    v_first     := v_match[2]::numeric;
    v_pad_width := length(v_match[2]);
  else
    -- no digits in start_ref: <start_ref>001, <start_ref>002, ...
    v_prefix    := coalesce(v_start_ref, '');
    v_first     := 1;
    v_pad_width := 3;
  end if;

  -- the highest number already on an active transfer with the same letters
  select max(substr(reference, length(v_prefix) + 1)::numeric)
    into v_max
    from transfers
   where owner_id = v_owner
     and cancelled_at is null
     and left(reference, length(v_prefix)) = v_prefix
     and substr(reference, length(v_prefix) + 1) ~ '^[0-9]{1,30}$';

  return v_prefix || lpad(
    greatest(v_first + v_count, coalesce(v_max + 1, 0))::text,
    v_pad_width,
    '0'
  );
end;
$$;

commit;
