-- 0024_reset_sub_user_device.sql
-- Adds an admin-only RPC to unbind an employee from their current device
-- without rotating the login code. Use case: employee got a new phone but
-- still remembers their original code. The admin clicks "إعادة ضبط الجهاز"
-- in إدارة الموظفين and the employee can log in fresh on the new device.
--
-- This is distinct from `regenerate_sub_user_code` (which also rotates
-- the code) and lets the admin choose the right tool for the situation.

begin;

create or replace function reset_sub_user_device(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_rows int;
begin
  -- Caller must own the sub_user (security definer bypasses RLS so we
  -- enforce ownership manually here).
  update sub_users
     set device_id          = null,
         login_code_used    = false,
         login_code_used_at = null,
         updated_at         = now()
   where id = p_id
     and parent_admin_id = auth.uid();

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  -- Bounce the employee out of any active session so their current
  -- device loses access immediately.
  update employee_sessions es
     set is_active = false,
         ended_at  = now()
   where es.sub_user_id = p_id
     and es.is_active;
end;
$$;

grant execute on function reset_sub_user_device(uuid) to authenticated;

commit;
