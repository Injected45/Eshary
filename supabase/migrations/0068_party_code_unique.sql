-- 0068_party_code_unique.sql
-- A saved party (sender / beneficiary) is identified by its COMPANY + CODE:
-- the same code may exist at two different companies (two different parties),
-- but never twice at the same company. Compared without case, spaces or the
-- difference between Arabic-Indic and Western digits (٥٥٢١ = 5521).
-- A party with no code is not constrained (the app still refuses the same
-- name twice on one company). Safe to run more than once; it refuses to run if
-- today's data already holds such a duplicate (the error names the code).

begin;

create or replace function _party_key(p text)
returns text
language sql
immutable
as $$
  select lower(regexp_replace(
    translate(coalesce(p, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'),
    '\s+', '', 'g'))
$$;

create unique index if not exists clients_owner_company_code_uq
  on clients (owner_id, _party_key(company), _party_key(code))
  where _party_key(code) <> '';

commit;
