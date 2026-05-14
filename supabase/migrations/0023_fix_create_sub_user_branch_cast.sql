-- 0023_fix_create_sub_user_branch_cast.sql
-- Bug fix: `create_sub_user` was written in 0019 when `sub_users.branch_id`
-- was a free-text column. Migration 0020 changed it to uuid (FK to branches)
-- but did not update the RPC, so any call with a non-null p_branch_id fails:
--
--   column "branch_id" is of type uuid but expression is of type text
--
-- This migration only replaces the function — table schema and RLS are
-- untouched.

begin;

create or replace function create_sub_user(
  p_employee_name text,
  p_phone_number  text,
  p_role          sub_user_role default 'both',
  p_branch_id     text default null
) returns table (
  id         uuid,
  plain_code text
) language plpgsql security invoker as $$
declare
  v_code text;
  v_id   uuid;
begin
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');

  insert into sub_users (
    parent_admin_id,
    employee_name,
    phone_number,
    login_code_hash,
    role,
    branch_id
  ) values (
    auth.uid(),
    trim(p_employee_name),
    trim(p_phone_number),
    crypt(v_code, gen_salt('bf')),
    p_role,
    -- Cast the optional text param to uuid; '' / null → null.
    nullif(trim(coalesce(p_branch_id, '')), '')::uuid
  )
  returning sub_users.id into v_id;

  return query select v_id, v_code;
end;
$$;

commit;
