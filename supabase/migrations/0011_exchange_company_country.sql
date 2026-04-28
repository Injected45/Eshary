-- 0011_exchange_company_country.sql
-- Adds optional country column to exchange_companies so the AddCompanyDialog
-- can cascade Country → Exchange Company.

begin;

alter table exchange_companies
  add column if not exists country text;

commit;
