-- 0008_exchange_country.sql
-- Adds an optional country text column to exchanges so the UI can label
-- each exchange office with its country (e.g., "تركيا").

begin;

alter table exchanges add column if not exists country text;

commit;
