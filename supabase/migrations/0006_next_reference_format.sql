-- 0006_next_reference_format.sql
-- Re-define next_reference() so the company's start_ref doubles as the
-- first reference. The trailing digits in start_ref become the seed
-- (with their padding width); the leading non-digit chars become the
-- prefix. Example: start_ref="RZ001" produces RZ001 (1st transfer),
-- RZ002 (2nd), RZ003 (3rd). Falls back to 3-digit lpad if start_ref
-- doesn't end in digits.

begin;

create or replace function next_reference(p_company_id uuid)
returns text
language plpgsql
security invoker
as $$
declare
  v_owner       uuid;
  v_start_ref   text;
  v_count       integer;
  v_match       text[];
  v_prefix      text;
  v_seed_text   text;
  v_seed_num    integer;
  v_pad_width   integer;
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

  select count(*) into v_count from transfers where owner_id = v_owner;

  v_match := regexp_match(coalesce(v_start_ref, ''), '^([^0-9]*)([0-9]+)$');
  if v_match is not null then
    v_prefix    := v_match[1];
    v_seed_text := v_match[2];
    v_seed_num  := v_seed_text::integer;
    v_pad_width := length(v_seed_text);
    return v_prefix
           || lpad((v_seed_num + v_count)::text, v_pad_width, '0');
  else
    return coalesce(v_start_ref, '')
           || lpad((v_count + 1)::text, 3, '0');
  end if;
end;
$$;

commit;
