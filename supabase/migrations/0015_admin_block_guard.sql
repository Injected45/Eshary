-- 0015_admin_block_guard.sql
-- Hardens admin_block() to refuse blocking any admin row, regardless of
-- caller. The previous self-block guard (`v_target = auth.uid()`) silently
-- passed when invoked from the SQL editor, where auth.uid() is NULL — that
-- let an admin accidentally block themselves via Studio.

begin;

create or replace function admin_block(p_user_email text)
returns account_licenses
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target       uuid;
  v_target_admin boolean;
  v_row          account_licenses;
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;

  select id into v_target from auth.users
   where lower(email) = lower(trim(p_user_email))
   limit 1;
  if v_target is null then
    raise exception 'user not found';
  end if;

  -- Reject blocking any admin (including yourself). NULL-safe — works
  -- from both the app (auth.uid() set) and the SQL editor (auth.uid() NULL).
  select coalesce(is_admin, false) into v_target_admin
    from account_licenses where user_id = v_target;
  if v_target_admin then
    raise exception 'cannot block an admin user';
  end if;

  insert into account_licenses (user_id, status, activated_at, activated_by)
  values (v_target, 'blocked', now(), auth.uid())
  on conflict (user_id) do update
    set status       = 'blocked',
        activated_at = now(),
        activated_by = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

commit;
