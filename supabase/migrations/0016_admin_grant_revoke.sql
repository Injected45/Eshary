-- 0016_admin_grant_revoke.sql
-- Adds two admin RPCs to promote / demote other users:
--   admin_grant_admin(p_user_email)  -> sets is_admin=true
--   admin_revoke_admin(p_user_email) -> sets is_admin=false
-- Self-protection: an admin cannot revoke their own admin via this RPC
-- (would instantly lock themselves out of admin tools). To remove your own
-- admin role, hand-edit the row in Studio.

begin;

create or replace function admin_grant_admin(p_user_email text)
returns account_licenses
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target uuid;
  v_row    account_licenses;
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

  -- Ensure a license row exists for the target before flipping is_admin.
  insert into account_licenses (user_id, status, is_admin)
  values (v_target, 'pending', true)
  on conflict (user_id) do update
    set is_admin = true
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function admin_revoke_admin(p_user_email text)
returns account_licenses
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target uuid;
  v_row    account_licenses;
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

  -- Self-protection: NULL-safe equality so the SQL-editor caller (where
  -- auth.uid() is NULL) does not bypass this guard. Hand-edit the row in
  -- Studio if you genuinely need to revoke your own admin.
  if v_target is not distinct from auth.uid() then
    raise exception 'cannot revoke your own admin';
  end if;

  update account_licenses
     set is_admin = false
   where user_id = v_target
  returning * into v_row;

  if v_row.user_id is null then
    raise exception 'user has no license row';
  end if;
  return v_row;
end;
$$;

revoke all on function admin_grant_admin(text)  from public, anon;
revoke all on function admin_revoke_admin(text) from public, anon;

grant execute on function admin_grant_admin(text)  to authenticated;
grant execute on function admin_revoke_admin(text) to authenticated;

commit;
