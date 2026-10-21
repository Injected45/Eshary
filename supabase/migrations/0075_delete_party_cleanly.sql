-- 0075_delete_party_cleanly.sql
-- A name must never be deleted from one place and stay in another.
--
--  1) delete_party(id): deleting a saved party (customer / beneficiary) removes,
--     in the same transaction, the customer COMPANY that was added with it when
--     no other saved party uses that company any more. A party that has
--     operations cannot be deleted at all (client_has_operations).
--
--  2) A company in "شركات الصرافة" cannot be deleted while something still
--     carries its name: an account of mine (company_in_use_accounts) or a saved
--     party (company_in_use_parties). It is deleted once nothing uses it. This
--     stops the "account without a company" state, and is enforced here, so no
--     screen can bypass it. It does NOT stand in the way of deleting a whole
--     account (the owner's cascade) or of restoring a backup.
--
-- Safe to run more than once.

begin;

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

  -- the company that came with it, when nothing else uses it
  if nullif(btrim(coalesce(v_party.company, '')), '') is not null
     and not exists (
       select 1 from clients c
        where c.owner_id = v_owner and c.company = v_party.company) then
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
  return old;
end;
$$;
revoke all on function _exchange_company_in_use() from public, anon, authenticated;

drop trigger if exists exchange_company_in_use on exchange_companies;
create trigger exchange_company_in_use
  before delete on exchange_companies
  for each row execute function _exchange_company_in_use();

commit;
