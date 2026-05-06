-- 0014_admin_role.sql
-- In-app admin role + admin RPCs for activating / blocking other users.
-- Admin status is stored as a boolean column on account_licenses; the
-- existing license RLS already restricts each user to their own row, so
-- admins gain power only through the security-definer RPCs below.

begin;

-- =========================================================================
-- is_admin column + index
-- =========================================================================

alter table account_licenses
  add column if not exists is_admin boolean not null default false;

create index if not exists account_licenses_is_admin_idx
  on account_licenses (is_admin)
  where is_admin = true;

-- =========================================================================
-- is_caller_admin() — used by every admin_* RPC as the gatekeeping check.
-- =========================================================================

create or replace function is_caller_admin()
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select coalesce(
    (select is_admin from account_licenses where user_id = auth.uid()),
    false
  );
$$;

grant execute on function is_caller_admin() to authenticated;

-- =========================================================================
-- current_license_status() — extended to also return is_admin so the app
-- can render the admin entry point in settings without a second roundtrip.
-- =========================================================================

drop function if exists current_license_status();

create or replace function current_license_status()
returns table (
  status         text,
  license_type   text,
  trial_ends_at  timestamptz,
  is_valid       boolean,
  is_admin       boolean
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authorized: no auth.uid()';
  end if;

  return query
  select l.status,
         l.license_type,
         l.trial_ends_at,
         (l.status = 'active'
            or (l.status = 'trial' and l.trial_ends_at is not null and l.trial_ends_at > now()))
           as is_valid,
         coalesce(l.is_admin, false) as is_admin
    from account_licenses l
   where l.user_id = v_uid;
end;
$$;

grant execute on function current_license_status() to authenticated;

-- =========================================================================
-- Admin RPCs callable by authenticated users. Each one self-guards via
-- is_caller_admin() before doing anything. Email lookup is case-insensitive.
-- =========================================================================

create or replace function admin_activate_trial(p_user_email text)
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

  insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
  values (v_target, 'trial', 'trial', now() + interval '3 days', now(), auth.uid())
  on conflict (user_id) do update
    set status        = 'trial',
        license_type  = 'trial',
        trial_ends_at = now() + interval '3 days',
        activated_at  = now(),
        activated_by  = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function admin_activate_lifetime(p_user_email text)
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

  insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
  values (v_target, 'active', 'lifetime', null, now(), auth.uid())
  on conflict (user_id) do update
    set status        = 'active',
        license_type  = 'lifetime',
        trial_ends_at = null,
        activated_at  = now(),
        activated_by  = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function admin_block(p_user_email text)
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

  -- Lockout protection: an admin must not block themselves.
  if v_target = auth.uid() then
    raise exception 'cannot block yourself';
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

create or replace function admin_set_pending(p_user_email text)
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

  insert into account_licenses (user_id, status)
  values (v_target, 'pending')
  on conflict (user_id) do update
    set status        = 'pending',
        license_type  = null,
        trial_ends_at = null,
        activated_at  = null,
        activated_by  = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function admin_list_users()
returns table (
  user_id        uuid,
  email          text,
  status         text,
  license_type   text,
  trial_ends_at  timestamptz,
  is_admin       boolean,
  created_at     timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;

  return query
  select u.id          as user_id,
         u.email::text  as email,
         coalesce(l.status, 'pending') as status,
         l.license_type,
         l.trial_ends_at,
         coalesce(l.is_admin, false)   as is_admin,
         u.created_at
    from auth.users u
    left join account_licenses l on l.user_id = u.id
   order by u.created_at desc;
end;
$$;

-- Lock down execution: anon must never see these. Authenticated callers
-- get through the door; the internal is_caller_admin() check enforces the
-- actual permission boundary.
revoke all on function admin_activate_trial(text)    from public, anon;
revoke all on function admin_activate_lifetime(text) from public, anon;
revoke all on function admin_block(text)             from public, anon;
revoke all on function admin_set_pending(text)       from public, anon;
revoke all on function admin_list_users()            from public, anon;

grant execute on function admin_activate_trial(text)    to authenticated;
grant execute on function admin_activate_lifetime(text) to authenticated;
grant execute on function admin_block(text)             to authenticated;
grant execute on function admin_set_pending(text)       to authenticated;
grant execute on function admin_list_users()            to authenticated;

commit;
