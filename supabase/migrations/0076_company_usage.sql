-- 0076_company_usage.sql
-- A company of "شركات الصرافة" that anything is recorded on cannot be deleted,
-- and the app does not even show the delete button for it. Only a name that was
-- registered and never used can be deleted.
--
--   exchange_company_usage()   for each of the owner's companies: how many
--       accounts, saved parties and FINANCIAL OPERATIONS carry its name. The app
--       shows the delete button only when all three are zero.
--   The delete itself is refused by the database too (company_in_use_operations
--       besides the two of 0075), so no screen can bypass it.
--   delete_party(): the company that came with a party is removed only when no
--       operation was recorded on it; otherwise the party goes and the company
--       stays.
--
-- An operation is recorded "on" a company when
--   * it is one of my exchange companies: an exit or an entry on one of my
--     accounts there;
--   * it is a customer's company: an exit to that beneficiary company, or an
--     entry from a saved party of that company.
-- Safe to run more than once.

begin;

create or replace function exchange_company_usage()
returns table (name text, accounts integer, parties integer, operations integer)
language sql
stable
security definer
set search_path = public
as $$
  select ec.name,
         (select count(*)::int
            from exchanges e join companies c on c.id = e.company_id
           where c.owner_id = ec.owner_id and e.name = ec.name),
         (select count(*)::int
            from clients cl
           where cl.owner_id = ec.owner_id and cl.company = ec.name),
         (select count(*)::int
            from transfers t
           where t.owner_id = ec.owner_id
             and (t.beneficiary_account_company = ec.name
                  or t.exchange_id in (
                       select e.id from exchanges e join companies c on c.id = e.company_id
                        where c.owner_id = ec.owner_id and e.name = ec.name)))
         +
         (select count(*)::int
            from currency_buys b
           where b.owner_id = ec.owner_id
             and (b.exchange_id in (
                       select e.id from exchanges e join companies c on c.id = e.company_id
                        where c.owner_id = ec.owner_id and e.name = ec.name)
                  or b.client_id in (
                       select cl.id from clients cl
                        where cl.owner_id = ec.owner_id and cl.company = ec.name)))
    from exchange_companies ec
   where ec.owner_id = auth.uid()
     and current_employee_id() is null
$$;
revoke all on function exchange_company_usage() from public, anon;
grant execute on function exchange_company_usage() to authenticated;

create or replace function _exchange_company_in_use()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- a restore replaces everything
  if coalesce(current_setting('eshary.restoring', true), '') = 'on' then
    return old;
  end if;
  -- the owner is being deleted: everything of theirs goes
  if not exists (select 1 from profiles where id = old.owner_id) then
    return old;
  end if;
  if exists (
    select 1
      from exchanges e
      join companies c on c.id = e.company_id
     where c.owner_id = old.owner_id and e.name = old.name) then
    raise exception 'company_in_use_accounts' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from clients cl
     where cl.owner_id = old.owner_id and cl.company = old.name) then
    raise exception 'company_in_use_parties' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from transfers t
     where t.owner_id = old.owner_id
       and t.beneficiary_account_company = old.name) then
    raise exception 'company_in_use_operations' using errcode = 'P0001';
  end if;
  return old;
end;
$$;
revoke all on function _exchange_company_in_use() from public, anon, authenticated;

create or replace function delete_party(p_client_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner   uuid := auth.uid();
  v_party   clients;
  v_removed text;
begin
  if v_owner is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  select * into v_party from clients
   where id = p_client_id and owner_id = v_owner
     for update;
  if not found then
    raise exception 'party_not_found' using errcode = 'P0001';
  end if;
  if exists (select 1 from currency_buys where client_id = p_client_id) then
    raise exception 'client_has_operations' using errcode = 'P0001';
  end if;

  delete from clients where id = p_client_id;

  -- the company that came with it, when nothing else uses it and nothing was
  -- ever recorded on it
  if nullif(btrim(coalesce(v_party.company, '')), '') is not null
     and not exists (
       select 1 from clients c
        where c.owner_id = v_owner and c.company = v_party.company)
     and not exists (
       select 1 from transfers t
        where t.owner_id = v_owner
          and t.beneficiary_account_company = v_party.company) then
    delete from exchange_companies ec
     where ec.owner_id = v_owner
       and ec.name = v_party.company
       and ec.kind = 'client'
    returning ec.name into v_removed;
  end if;

  return jsonb_build_object('ok', true, 'company_removed', v_removed);
end;
$$;
revoke all on function delete_party(uuid) from public, anon;
grant execute on function delete_party(uuid) to authenticated;

commit;
