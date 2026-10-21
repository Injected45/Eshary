-- 0073_exchange_company_rename.sql
-- An account (exchanges.name) and a saved party (clients.company) are linked to
-- their exchange company by NAME. Renaming the company in "شركات الصرافة" used
-- to leave them with the old name, so the exit / entry forms and "حساباتي"
-- stopped finding the account ("لا توجد شركة لديك فيها حساب") even though the
-- account and its operations were all there.
--
-- From now on, renaming an exchange company renames, in the same transaction,
-- that owner's accounts and saved parties that carried the old name.
-- Safe to run more than once.

begin;

create or replace function _exchange_company_renamed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.name is distinct from old.name then
    update exchanges e
       set name = new.name
      from companies c
     where c.id = e.company_id
       and c.owner_id = new.owner_id
       and e.name = old.name;
    update clients
       set company = new.name
     where owner_id = new.owner_id
       and company = old.name;
  end if;
  return new;
end;
$$;
revoke all on function _exchange_company_renamed() from public, anon, authenticated;

drop trigger if exists exchange_company_renamed on exchange_companies;
create trigger exchange_company_renamed
  after update of name on exchange_companies
  for each row execute function _exchange_company_renamed();

commit;
