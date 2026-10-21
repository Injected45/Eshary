-- 0074_exchange_company_kind.sql
-- "شركات الصرافة" mixed two different things in one list:
--   mine    the exchange companies where I hold accounts (بهاروز ...): the
--           exit / entry forms offer them as MY company, and "حساباتي" opens
--           accounts under them;
--   client  the companies of my customers (the sender's / beneficiary's
--           company: الصحراء ...), chosen when a customer is saved.
-- A customer's company must never be offered as my own, so each name now says
-- which kind it is. The app keeps them in two separate lists.
--
-- Existing names are sorted once, when the column is created: a name that has a
-- saved customer and no account of mine becomes 'client'; everything else stays
-- 'mine'. Running the file again changes nothing. Safe to run more than once.

begin;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'exchange_companies'
       and column_name = 'kind'
  ) then
    alter table exchange_companies
      add column kind text not null default 'mine'
      check (kind in ('mine', 'client'));

    update exchange_companies ec
       set kind = 'client'
     where exists (
             select 1 from clients cl
              where cl.owner_id = ec.owner_id and cl.company = ec.name)
       and not exists (
             select 1 from exchanges e
               join companies c on c.id = e.company_id
              where c.owner_id = ec.owner_id and e.name = ec.name);
  end if;
end;
$$;

commit;
