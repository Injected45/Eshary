-- 0021_employee_auth.sql
-- Phase 2 of the Employee Management module: actual login mechanism for
-- sub_users using Supabase Anonymous Auth + verification RPCs.
--
-- Flow:
--   1. App calls supabase.auth.signInAnonymously() → anonymous auth.users row
--   2. App calls employee_login(phone, code, device_id) RPC
--   3. RPC verifies bcrypt hash, checks device binding, creates session row
--   4. Subsequent reads use current_employee_session() to identify the employee
--
-- Anonymous JWT carries no admin privileges → sub_users / transfers RLS
-- continue to require parent_admin = auth.uid(). Phase 3 will add RPCs
-- the employee invokes through their anonymous session to write data
-- attributed to their parent admin.

begin;

create table employee_sessions (
  id                uuid primary key default gen_random_uuid(),
  sub_user_id       uuid not null references sub_users(id) on delete cascade,
  anonymous_user_id uuid not null references auth.users(id) on delete cascade,
  device_id         text not null,
  started_at        timestamptz not null default now(),
  ended_at          timestamptz,
  is_active         boolean not null default true
);

create index employee_sessions_anon_uid_active_idx
  on employee_sessions(anonymous_user_id)
  where is_active;

create index employee_sessions_sub_user_idx on employee_sessions(sub_user_id);

alter table employee_sessions enable row level security;

-- An anonymous (employee) user can only see their own session row.
create policy employee_sessions_select_self on employee_sessions
  for select to authenticated
  using (anonymous_user_id = auth.uid());

-- Parent admins can audit their employees' sessions.
create policy employee_sessions_select_admin on employee_sessions
  for select to authenticated
  using (sub_user_id in (
    select id from sub_users where parent_admin_id = auth.uid()
  ));

-- employee_login(phone, code, device_id)
--
-- Returns (sub_user_id, parent_admin_id, employee_name, session_id) on success.
-- Raises 'invalid_credentials' if no sub_user matches phone+code, or
-- 'device_mismatch' if the sub_user is already bound to a different device.
-- Same error for "no such phone" and "wrong code" → no info leak.
--
-- SECURITY DEFINER: the calling anonymous user has no SELECT on sub_users
-- (RLS limits to parent_admin), so we run as the function owner and
-- carefully scope what the function reveals.
create or replace function employee_login(
  p_phone     text,
  p_code      text,
  p_device_id text
) returns table (
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  session_id      uuid
) language plpgsql security definer set search_path = public, extensions as $$
declare
  v_sub_user sub_users;
  v_session_id uuid;
  v_matched boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'device_id_required' using errcode = 'P0001';
  end if;

  -- Phone numbers are unique per admin but a given phone could theoretically
  -- exist under multiple admins. Iterate all active matches and pick the
  -- first whose hash verifies.
  for v_sub_user in
    select * from sub_users
    where phone_number = trim(p_phone)
      and status = 'active'
  loop
    if v_sub_user.login_code_hash = crypt(p_code, v_sub_user.login_code_hash) then
      v_matched := true;
      if v_sub_user.device_id is null then
        -- First login binds this device.
        update sub_users set
          device_id = p_device_id,
          login_code_used = true,
          login_code_used_at = now(),
          last_login_at = now(),
          updated_at = now()
        where id = v_sub_user.id;
      elsif v_sub_user.device_id = p_device_id then
        update sub_users set
          last_login_at = now(),
          updated_at = now()
        where id = v_sub_user.id;
      else
        raise exception 'device_mismatch' using errcode = 'P0001';
      end if;

      -- Only one active session per sub_user at a time. Column names are
      -- qualified with the table alias because OUT parameters like
      -- `sub_user_id` would otherwise shadow them inside the function body.
      update employee_sessions es set
        is_active = false,
        ended_at = now()
      where es.sub_user_id = v_sub_user.id and es.is_active;

      insert into employee_sessions (
        sub_user_id, anonymous_user_id, device_id
      ) values (
        v_sub_user.id, auth.uid(), p_device_id
      ) returning id into v_session_id;

      return query select
        v_sub_user.id,
        v_sub_user.parent_admin_id,
        v_sub_user.employee_name,
        v_session_id;
      return;
    end if;
  end loop;

  if not v_matched then
    raise exception 'invalid_credentials' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function employee_login(text, text, text) from public;
grant execute on function employee_login(text, text, text) to authenticated;

-- employee_logout: closes the current session for the calling anonymous user.
create or replace function employee_logout()
returns void language plpgsql security invoker as $$
begin
  update employee_sessions set
    is_active = false,
    ended_at = now()
  where anonymous_user_id = auth.uid() and is_active;
end;
$$;

grant execute on function employee_logout() to authenticated;

-- current_employee_session: identity helper for the app. Returns a single
-- row describing who the calling anonymous user is acting as, or no rows
-- if the session was closed or the sub_user was disabled.
--
-- SECURITY DEFINER so it can read sub_users despite RLS.
create or replace function current_employee_session()
returns table (
  session_id      uuid,
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  role            sub_user_role,
  branch_id       uuid
) language plpgsql security definer set search_path = public, extensions as $$
begin
  return query
  select
    es.id,
    su.id,
    su.parent_admin_id,
    su.employee_name,
    su.role,
    su.branch_id
  from employee_sessions es
  join sub_users su on su.id = es.sub_user_id
  where es.anonymous_user_id = auth.uid()
    and es.is_active = true
    and su.status = 'active'
  limit 1;
end;
$$;

grant execute on function current_employee_session() to authenticated;

commit;
