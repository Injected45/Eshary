-- 0071_party_letters_permission.sql
-- A new employee permission, "party_letters": the administrator may let an
-- employee set the letters a saved sender's reference numbers always start
-- with (TRC ...). Nothing else about a party changes: an employee still cannot
-- add, rename or delete one. Only the letters, only for a party of their own
-- administrator, only with the permission.
-- Safe to run more than once.

begin;

create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all',
               'party_letters']
$$;

create or replace function employee_set_party_letters(
  p_client_id uuid,
  p_letters   text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_emp    uuid := current_employee_id();
  v_parent uuid;
  v_text   text := nullif(btrim(coalesce(p_letters, '')), '');
begin
  -- only employees come through here (the administrator edits the party)
  if v_emp is null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not employee_has_perm('party_letters') then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;
  if v_text is not null and char_length(v_text) > 20 then
    raise exception 'letters_too_long' using errcode = 'P0001';
  end if;
  select su.parent_admin_id into v_parent from sub_users su where su.id = v_emp;
  update clients
     set ref_prefix = v_text
   where id = p_client_id
     and owner_id = v_parent;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function employee_set_party_letters(uuid, text) from public, anon;
grant execute on function employee_set_party_letters(uuid, text) to authenticated;

commit;
