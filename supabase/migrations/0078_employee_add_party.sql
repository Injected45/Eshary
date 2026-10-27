-- 0078_employee_add_party.sql
-- A new employee permission, "clients_add": the administrator may let an
-- employee ADD a saved party (a sender or a beneficiary) from the entry and the
-- exit screens. Nothing else about the parties changes for that employee: they
-- still cannot rename or delete one, and cannot touch the administrator's
-- exchange companies.
--
-- The party is always created for the employee's OWN administrator, through
-- this function only (an employee has no direct write on clients).
-- Safe to run more than once.

begin;

-- the list of keys the administrator may grant: every key of the earlier
-- migrations (0071 added party_letters) plus the new one
create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all',
               'party_letters', 'clients_add']
$$;

create or replace function employee_add_party(
  p_name       text,
  p_company    text default null,
  p_code       text default null,
  p_ref_prefix text default null
) returns clients
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_emp     uuid := current_employee_id();
  v_parent  uuid;
  v_name    text := btrim(coalesce(p_name, ''));
  v_company text := nullif(btrim(coalesce(p_company, '')), '');
  v_code    text := nullif(btrim(coalesce(p_code, '')), '');
  v_letters text := nullif(btrim(coalesce(p_ref_prefix, '')), '');
  v_row     clients;
begin
  -- only employees come through here (the administrator inserts directly)
  if v_emp is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not employee_has_perm('clients_add') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if v_name = '' or char_length(v_name) > 120 then
    raise exception 'party_name_invalid' using errcode = 'P0001';
  end if;
  if char_length(coalesce(v_company, '')) > 120
     or char_length(coalesce(v_code, '')) > 60 then
    raise exception 'party_text_too_long' using errcode = 'P0001';
  end if;
  if v_letters is not null and char_length(v_letters) > 20 then
    raise exception 'letters_too_long' using errcode = 'P0001';
  end if;

  select su.parent_admin_id into v_parent from sub_users su where su.id = v_emp;
  if v_parent is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;

  begin
    insert into clients (owner_id, name, company, code, ref_prefix)
    values (v_parent, v_name, v_company, v_code, v_letters)
    returning * into v_row;
  exception when unique_violation then
    -- the same code at the same company (0068)
    raise exception 'party_code_exists' using errcode = 'P0001';
  end;
  return v_row;
end;
$$;

revoke all on function employee_add_party(text, text, text, text) from public, anon;
grant execute on function employee_add_party(text, text, text, text) to authenticated;

commit;
