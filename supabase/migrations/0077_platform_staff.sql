-- 0077_platform_staff.sql
-- منصة إشاري الإدارية (admin-web): staff accounts, roles and a WhatsApp-verified
-- session.
--
-- A staff member is an ordinary Supabase user (so the password and the JWT are
-- the ones that already exist) with a row in platform_staff: role, the
-- WhatsApp number that receives the code, and an active flag.
--
--   super_admin  everything, including the staff list and the settings
--   admin        users, activation, notifications, audit
--   support      reads users and the dashboard
--   viewer       reads the dashboard and the users list
--
-- THE SECOND FACTOR IS ENFORCED HERE, NOT IN THE BROWSER. After the password,
-- the web server asks for a code (WhatsApp, through the gateway the app already
-- uses). Only a correct code writes a row in platform_sessions for the JWT's
-- session_id. _platform_role() answers a role ONLY when that row is live, so a
-- password alone (used against the API directly) opens nothing: every
-- platform_* function and the staff branch of is_caller_admin() depend on it.
--
-- The existing admin_* functions are reused as they are: is_caller_admin() now
-- also answers true for an active super_admin / admin with a live verified
-- session, and _audit() records that staff member as the actor.
--
-- A user flagged is_admin in account_licenses keeps working exactly as before
-- (the Flutter app's administrator); the code is asked of platform staff.

begin;

-- =========================================================================
-- 1) Staff and verified sessions
-- =========================================================================
create table if not exists platform_staff (
  user_id           uuid primary key references auth.users (id) on delete cascade,
  role              text not null
                    check (role in ('super_admin', 'admin', 'support', 'viewer')),
  full_name         text not null check (char_length(btrim(full_name)) between 2 and 80),
  phone             text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  phone_verified_at timestamptz,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  created_by        uuid
);
alter table platform_staff enable row level security;
revoke all on platform_staff from anon, authenticated;

create table if not exists platform_sessions (
  auth_session_id text primary key,
  user_id         uuid not null references platform_staff (user_id) on delete cascade,
  verified_at     timestamptz not null default now(),
  expires_at      timestamptz not null,
  revoked_at      timestamptz
);
create index if not exists platform_sessions_user_idx on platform_sessions (user_id);
alter table platform_sessions enable row level security;
revoke all on platform_sessions from anon, authenticated;

create table if not exists platform_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table platform_settings enable row level security;
revoke all on platform_settings from anon, authenticated;

-- The activation presets the platform offers (hours for a trial, days for a
-- paid period). Editable by a super_admin; the server still applies them.
insert into platform_settings (key, value) values
  ('trial_presets_hours', '[72, 168]'::jsonb),
  ('paid_presets_days',   '[30, 90, 365]'::jsonb),
  ('expiry_warning_days', '3'::jsonb),
  ('session_hours',       '12'::jsonb)
on conflict (key) do nothing;

-- The code for platform staff is a new purpose of the existing challenge table.
-- (account_delete comes from 0064: every purpose already in use must stay here.)
alter table wa_challenges drop constraint if exists wa_challenges_purpose_check;
alter table wa_challenges add constraint wa_challenges_purpose_check
  check (purpose in ('activation', 'login', 'phone_change', 'account_delete', 'platform_login'));

-- =========================================================================
-- 2) Who is the caller (only with a verified, live session)
-- =========================================================================
create or replace function _platform_role()
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$
  select s.role
    from platform_staff s
   where s.user_id = auth.uid()
     and s.active
     and exists (
       select 1 from platform_sessions p
        where p.user_id = s.user_id
          and p.auth_session_id = coalesce(auth.jwt() ->> 'session_id', '')
          and p.revoked_at is null
          and p.expires_at > _server_now())
$$;
revoke all on function _platform_role() from public, anon, authenticated;

-- The existing administrator check, widened to platform staff who may
-- administer. The old rule (is_admin in account_licenses) is unchanged.
create or replace function is_caller_admin()
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select coalesce(
           (select is_admin from account_licenses where user_id = auth.uid()),
           false)
      or coalesce(_platform_role() in ('super_admin', 'admin'), false);
$$;

-- Raises unless the caller has one of the roles (and a verified session).
create or replace function _platform_need(variadic p_roles text[])
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_role text := _platform_role();
begin
  if v_role is null or not (v_role = any (p_roles)) then
    raise exception 'platform_forbidden' using errcode = 'P0001';
  end if;
  return v_role;
end;
$$;
revoke all on function _platform_need(text[]) from public, anon, authenticated;

-- A direct audit row for events that have no auth.uid() (the login steps are
-- done by the web server with the service key).
create or replace function _platform_audit(
  p_actor uuid, p_kind text, p_note text default null,
  p_new jsonb default null, p_ip text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into audit_log (at, actor, actor_email, kind, subject_type, subject_id,
                         new_value, note, ip_hash)
  values (_server_now(), p_actor,
          (select u.email from auth.users u where u.id = p_actor),
          p_kind, 'platform_staff', p_actor::text, p_new, p_note, _ip_hash(p_ip));
end;
$$;
revoke all on function _platform_audit(uuid, text, text, jsonb, text) from public, anon, authenticated;

-- =========================================================================
-- 3) Sign-in steps (the web server, with the service key)
-- =========================================================================
create or replace function platform_staff_lookup(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  s platform_staff;
begin
  select * into s from platform_staff where user_id = p_user;
  if not found then
    return jsonb_build_object('found', false);
  end if;
  return jsonb_build_object(
    'found', true, 'active', s.active, 'role', s.role, 'name', s.full_name,
    'phoneMasked', _mask_e164(s.phone), 'phoneVerified', s.phone_verified_at is not null);
end;
$$;
revoke all on function platform_staff_lookup(uuid) from public, anon, authenticated;
grant execute on function platform_staff_lookup(uuid) to service_role;

-- Step 1 done (the password is right): send the code.
create or replace function platform_login_start(p_user uuid, p_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s platform_staff;
  r jsonb;
begin
  select * into s from platform_staff where user_id = p_user and active;
  if not found then
    perform _platform_audit(p_user, 'platform_login_denied', 'not_staff', null, p_ip);
    return jsonb_build_object('ok', false, 'code', 'not_staff');
  end if;
  r := _issue_challenge(
    'platform_login', null, s.user_id, s.phone, null,
    'دخول منصة إشاري الإدارية. ', _ip_hash(p_ip));
  perform _platform_audit(
    p_user,
    case when (r ->> 'ok')::boolean then 'platform_code_sent' else 'platform_code_refused' end,
    r ->> 'code', null, p_ip);
  return r || jsonb_build_object('phoneMasked', _mask_e164(s.phone));
end;
$$;
revoke all on function platform_login_start(uuid, text) from public, anon, authenticated;
grant execute on function platform_login_start(uuid, text) to service_role;

-- Step 2: the code. Three wrong tries cancel it. Only a right code opens the
-- session for this JWT session_id.
create or replace function platform_login_verify(
  p_user uuid, p_code text, p_auth_session text, p_ip text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s     platform_staff;
  c     wa_challenges;
  chk   jsonb;
  v_h   integer;
  v_end timestamptz;
begin
  if coalesce(btrim(p_auth_session), '') = '' then
    return jsonb_build_object('ok', false, 'code', 'no_session');
  end if;
  select * into s from platform_staff where user_id = p_user and active;
  if not found then
    perform _platform_audit(p_user, 'platform_login_denied', 'not_staff', null, p_ip);
    return jsonb_build_object('ok', false, 'code', 'not_staff');
  end if;

  -- at most 3 tries per code (the shared check allows 5)
  select * into c
    from wa_challenges w
   where w.purpose = 'platform_login' and w.phone = s.phone
     and w.consumed_at is null and w.revoked_at is null and w.expires_at > now()
   order by w.created_at desc limit 1;
  if found and c.attempts >= 3 then
    update wa_challenges set revoked_at = now() where id = c.id;
    perform _platform_audit(p_user, 'platform_login_failed', 'too_many_attempts', null, p_ip);
    return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
  end if;

  chk := _check_challenge('platform_login', s.phone, p_code, 'platform:' || p_user::text, null);
  if not (chk ->> 'ok')::boolean then
    update wa_challenges set revoked_at = coalesce(revoked_at, now())
     where id = c.id and attempts >= 3;
    perform _platform_audit(p_user, 'platform_login_failed', chk ->> 'code', null, p_ip);
    return chk;
  end if;

  update wa_challenges set consumed_at = now() where id = (chk ->> 'challengeId')::uuid;
  update platform_staff set phone_verified_at = coalesce(phone_verified_at, _server_now())
   where user_id = s.user_id;

  v_h := coalesce((select (value #>> '{}')::integer from platform_settings
                    where key = 'session_hours'), 12);
  v_end := _server_now() + make_interval(hours => greatest(1, least(v_h, 72)));
  insert into platform_sessions (auth_session_id, user_id, verified_at, expires_at)
  values (p_auth_session, s.user_id, _server_now(), v_end)
  on conflict (auth_session_id) do update
     set verified_at = excluded.verified_at, expires_at = excluded.expires_at,
         revoked_at = null
   where platform_sessions.user_id = excluded.user_id;
  perform _platform_audit(p_user, 'platform_login_ok', s.role, null, p_ip);
  return jsonb_build_object('ok', true, 'role', s.role, 'name', s.full_name,
                            'expiresAt', v_end);
end;
$$;
revoke all on function platform_login_verify(uuid, text, text, text) from public, anon, authenticated;
grant execute on function platform_login_verify(uuid, text, text, text) to service_role;

-- Counts one try against a limit (per address, per e-mail...) and says whether
-- it is still allowed. The web server asks before it checks a password.
create or replace function platform_throttle(
  p_kind text, p_key text, p_limit integer, p_minutes integer
) returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select _rate_ok('platform:' || left(coalesce(p_kind, ''), 40),
                  left(coalesce(p_key, ''), 200),
                  greatest(1, least(coalesce(p_limit, 10), 1000)),
                  make_interval(mins => greatest(1, least(coalesce(p_minutes, 15), 1440))))
$$;
revoke all on function platform_throttle(text, text, integer, integer) from public, anon, authenticated;
grant execute on function platform_throttle(text, text, integer, integer) to service_role;

-- Records a refused password (the server tells us; nothing else changes).
create or replace function platform_login_rejected(p_email text, p_ip text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into audit_log (at, kind, subject_type, subject_id, note, ip_hash)
  values (_server_now(), 'platform_login_failed', 'platform_staff',
          left(lower(btrim(coalesce(p_email, ''))), 120), 'bad_password', _ip_hash(p_ip));
end;
$$;
revoke all on function platform_login_rejected(text, text) from public, anon, authenticated;
grant execute on function platform_login_rejected(text, text) to service_role;

-- The caller ends the session (the browser signs out too).
create or replace function platform_logout()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update platform_sessions set revoked_at = _server_now()
   where auth_session_id = coalesce(auth.jwt() ->> 'session_id', '')
     and user_id = auth.uid() and revoked_at is null;
  if found then
    perform _platform_audit(auth.uid(), 'platform_logout');
  end if;
end;
$$;
revoke all on function platform_logout() from public, anon;
grant execute on function platform_logout() to authenticated;

-- Who am I (with a verified session): null when not signed in properly.
create or replace function platform_me()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_role text := _platform_role();
  s      platform_staff;
begin
  if v_role is null then
    return null;
  end if;
  select * into s from platform_staff where user_id = auth.uid();
  return jsonb_build_object('userId', s.user_id, 'role', s.role, 'name', s.full_name);
end;
$$;
revoke all on function platform_me() from public, anon;
grant execute on function platform_me() to authenticated;

-- =========================================================================
-- 4) Staff accounts
-- =========================================================================
-- The first super_admin is created once, by the bootstrap script (the service
-- key, p_by null); after that only an active super_admin can add staff, and the
-- web server calls this with the caller's id after checking the role.
create or replace function platform_staff_add(
  p_user uuid, p_role text, p_name text, p_phone text, p_by uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := _e164_clean(p_phone);
begin
  if p_role not in ('super_admin', 'admin', 'support', 'viewer') then
    raise exception 'invalid_role' using errcode = 'P0001';
  end if;
  if not _e164_ok(v_phone) then
    raise exception 'invalid_phone' using errcode = 'P0001';
  end if;
  if p_by is null then
    if exists (select 1 from platform_staff where role = 'super_admin') then
      raise exception 'bootstrap_done' using errcode = 'P0001';
    end if;
    if p_role <> 'super_admin' then
      raise exception 'bootstrap_needs_super_admin' using errcode = 'P0001';
    end if;
  else
    if not exists (select 1 from platform_staff
                    where user_id = p_by and active and role = 'super_admin') then
      raise exception 'platform_forbidden' using errcode = 'P0001';
    end if;
  end if;
  insert into platform_staff (user_id, role, full_name, phone, created_by)
  values (p_user, p_role, btrim(p_name), v_phone, p_by);
  perform _platform_audit(coalesce(p_by, p_user), 'platform_staff_added',
                          p_user::text, jsonb_build_object('role', p_role), null);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function platform_staff_add(uuid, text, text, text, uuid) from public, anon, authenticated;
grant execute on function platform_staff_add(uuid, text, text, text, uuid) to service_role;

create or replace function platform_staff_list()
returns table (
  user_id uuid, email text, full_name text, role text, phone_masked text,
  phone_verified boolean, active boolean, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin');
  return query
  select s.user_id, u.email::text, s.full_name, s.role, _mask_e164(s.phone),
         s.phone_verified_at is not null, s.active, s.created_at
    from platform_staff s join auth.users u on u.id = s.user_id
   order by s.created_at;
end;
$$;
revoke all on function platform_staff_list() from public, anon;
grant execute on function platform_staff_list() to authenticated;

-- Changes the role or switches an account off. Nobody changes themselves, and
-- the last active super_admin always stays. Switching off ends the sessions at
-- once (the role check needs an active row).
create or replace function platform_staff_set(
  p_user uuid, p_role text default null, p_active boolean default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s platform_staff;
begin
  perform _platform_need('super_admin');
  if p_user = auth.uid() then
    raise exception 'cannot_change_self' using errcode = 'P0001';
  end if;
  select * into s from platform_staff where user_id = p_user for update;
  if not found then
    raise exception 'staff_not_found' using errcode = 'P0001';
  end if;
  if p_role is not null and p_role not in ('super_admin', 'admin', 'support', 'viewer') then
    raise exception 'invalid_role' using errcode = 'P0001';
  end if;
  if s.role = 'super_admin'
     and (coalesce(p_role, s.role) <> 'super_admin' or coalesce(p_active, s.active) = false)
     and (select count(*) from platform_staff where role = 'super_admin' and active) <= 1 then
    raise exception 'last_super_admin' using errcode = 'P0001';
  end if;
  update platform_staff
     set role = coalesce(p_role, role), active = coalesce(p_active, active)
   where user_id = p_user;
  if p_active is false or (p_role is not null and p_role <> s.role) then
    update platform_sessions set revoked_at = _server_now()
     where user_id = p_user and revoked_at is null;
  end if;
  perform _audit('platform_staff_changed', 'platform_staff', p_user::text,
                 jsonb_build_object('role', s.role, 'active', s.active),
                 jsonb_build_object('role', coalesce(p_role, s.role),
                                    'active', coalesce(p_active, s.active)));
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function platform_staff_set(uuid, text, boolean) from public, anon;
grant execute on function platform_staff_set(uuid, text, boolean) to authenticated;

-- =========================================================================
-- 5) Dashboard, users, system status
-- =========================================================================
create or replace function platform_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v      jsonb;
  v_days integer := coalesce((select (value #>> '{}')::integer from platform_settings
                               where key = 'expiry_warning_days'), 3);
begin
  perform _platform_need('super_admin', 'admin', 'support', 'viewer');
  select jsonb_build_object(
    'total',    count(*),
    'active',   count(*) filter (where l.status = 'active'),
    'trial',    count(*) filter (where l.status = 'trial'),
    'pending',  count(*) filter (where l.status = 'pending'),
    'expired',  count(*) filter (where l.status = 'expired'),
    'blocked',  count(*) filter (where l.status = 'blocked'),
    'expiringSoon', count(*) filter (
       where (l.status = 'trial' and l.trial_ends_at between _server_now()
                 and _server_now() + make_interval(days => v_days))
          or (l.status = 'active' and l.paid_until between _server_now()
                 and _server_now() + make_interval(days => v_days)))
  ) into v
  from account_licenses l
  where not coalesce(l.is_admin, false)
    and not exists (select 1 from platform_staff s where s.user_id = l.user_id)
    and not exists (select 1 from auth.users u where u.id = l.user_id and u.is_anonymous);

  return v || jsonb_build_object(
    'pendingRequests', (select count(*) from trial_requests
                         where status in ('pending_review', 'needs_info')),
    'notificationsSent', (select count(*) from notifications),
    'unreadAlerts', (select count(*) from platform_alerts where read_at is null),
    'serverNow', _server_now(),
    'expiryWarningDays', v_days,
    -- the app does not report activity or support tickets yet
    'activeNow', null,
    'openTickets', null);
end;
$$;
revoke all on function platform_dashboard() from public, anon;
grant execute on function platform_dashboard() to authenticated;

create or replace function platform_users_list(
  p_search text default null, p_status text default null,
  p_limit integer default 25, p_offset integer default 0
) returns table (
  user_id uuid, display_name text, phone text, status text, license_type text,
  trial_ends_at timestamptz, paid_until timestamptz, created_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_q text := nullif(btrim(coalesce(p_search, '')), '');
begin
  perform _platform_need('super_admin', 'admin', 'support', 'viewer');
  return query
  select l.user_id,
         coalesce(sa.business_name || ' — ' || sa.manager_name, u.email::text),
         coalesce(sa.phone, mp.phone),
         l.status, l.license_type, l.trial_ends_at, l.paid_until, u.created_at,
         count(*) over ()
    from account_licenses l
    join auth.users u on u.id = l.user_id
    left join subscriber_accounts sa on sa.user_id = l.user_id
    left join member_phones mp on mp.user_id = l.user_id
   where not coalesce(l.is_admin, false)
     and not coalesce(u.is_anonymous, false)
     and not exists (select 1 from platform_staff s where s.user_id = l.user_id)
     and (p_status is null or l.status = p_status)
     and (v_q is null
          or l.user_id::text = v_q
          or u.email ilike '%' || v_q || '%'
          or sa.business_name ilike '%' || v_q || '%'
          or sa.manager_name ilike '%' || v_q || '%'
          or coalesce(sa.phone, mp.phone) like '%' || regexp_replace(v_q, '[^0-9+]', '', 'g') || '%')
   order by u.created_at desc
   limit greatest(1, least(coalesce(p_limit, 25), 100))
   offset greatest(0, coalesce(p_offset, 0));
end;
$$;
revoke all on function platform_users_list(text, text, integer, integer) from public, anon;
grant execute on function platform_users_list(text, text, integer, integer) to authenticated;

create or replace function platform_user_detail(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v jsonb;
begin
  perform _platform_need('super_admin', 'admin', 'support', 'viewer');
  select jsonb_build_object(
    'userId', l.user_id,
    'displayName', coalesce(sa.business_name || ' — ' || sa.manager_name, u.email::text),
    'email', u.email,
    'phone', coalesce(sa.phone, mp.phone),
    'status', l.status, 'licenseType', l.license_type,
    'trialEndsAt', l.trial_ends_at, 'paidUntil', l.paid_until,
    'activatedAt', l.activated_at, 'suspendedAt', l.suspended_at,
    'suspendedReason', l.suspended_reason, 'paidReference', l.paid_reference,
    'notes', l.notes, 'createdAt', u.created_at,
    'lastSignInAt', u.last_sign_in_at)
    into v
    from account_licenses l
    join auth.users u on u.id = l.user_id
    left join subscriber_accounts sa on sa.user_id = l.user_id
    left join member_phones mp on mp.user_id = l.user_id
   where l.user_id = p_user and not coalesce(l.is_admin, false);
  if v is null then
    raise exception 'user_not_found' using errcode = 'P0001';
  end if;
  return v || jsonb_build_object('history', coalesce((
    select jsonb_agg(jsonb_build_object(
             'at', a.at, 'kind', a.kind, 'by', a.actor_email, 'note', a.note,
             'old', a.old_value, 'new', a.new_value) order by a.at desc)
      from (select * from audit_log
             where subject_type = 'account' and subject_id = p_user::text
             order by at desc limit 50) a), '[]'::jsonb));
end;
$$;
revoke all on function platform_user_detail(uuid) from public, anon;
grant execute on function platform_user_detail(uuid) to authenticated;

-- The administrators' own notes on a user (kept in account_licenses.notes).
create or replace function platform_user_set_notes(p_user uuid, p_notes text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old text;
begin
  perform _platform_need('super_admin', 'admin');
  select notes into v_old from account_licenses where user_id = p_user and not coalesce(is_admin, false);
  if not found then
    raise exception 'user_not_found' using errcode = 'P0001';
  end if;
  update account_licenses set notes = nullif(left(btrim(coalesce(p_notes, '')), 2000), '')
   where user_id = p_user;
  perform _audit('user_notes_changed', 'account', p_user::text,
                 jsonb_build_object('notes', v_old),
                 jsonb_build_object('notes', nullif(left(btrim(coalesce(p_notes, '')), 2000), '')));
end;
$$;
revoke all on function platform_user_set_notes(uuid, text) from public, anon;
grant execute on function platform_user_set_notes(uuid, text) to authenticated;

create or replace function platform_audit_list(
  p_limit integer default 50, p_offset integer default 0, p_kind text default null
) returns table (
  id bigint, at timestamptz, actor_email text, kind text, subject_type text,
  subject_id text, note text, new_value jsonb
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin', 'admin');
  return query
  select a.id, a.at, a.actor_email, a.kind, a.subject_type, a.subject_id, a.note, a.new_value
    from audit_log a
   where p_kind is null or a.kind = p_kind
   order by a.at desc, a.id desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
   offset greatest(0, coalesce(p_offset, 0));
end;
$$;
revoke all on function platform_audit_list(integer, integer, text) from public, anon;
grant execute on function platform_audit_list(integer, integer, text) to authenticated;

-- Server-side health: nothing here is reported by a browser.
create or replace function platform_system_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_wa_sent   integer;
  v_wa_failed integer;
  v_cron      timestamptz;
begin
  perform _platform_need('super_admin', 'admin', 'support', 'viewer');
  select count(*) filter (where send_status = 'sent'),
         count(*) filter (where send_status = 'failed')
    into v_wa_sent, v_wa_failed
    from wa_challenges where created_at > now() - interval '1 hour';
  begin
    execute 'select max(start_time) from cron.job_run_details d '
            'join cron.job j on j.jobid = d.jobid where j.jobname = ''eshary-tick'''
       into v_cron;
  exception when others then
    v_cron := null;
  end;
  return jsonb_build_object(
    'database', true,
    'serverNow', _server_now(),
    'timeTrusted', _time_trusted(),
    'whatsappSentLastHour', v_wa_sent,
    'whatsappFailedLastHour', v_wa_failed,
    'schedulerLastRun', v_cron,
    'unreadAlerts', (select count(*) from platform_alerts where read_at is null),
    'recentAlerts', coalesce((
       select jsonb_agg(jsonb_build_object('at', a.created_at, 'kind', a.kind, 'body', a.body)
                        order by a.created_at desc)
         from (select * from platform_alerts order by created_at desc limit 8) a), '[]'::jsonb),
    'activeStaffSessions', (select count(*) from platform_sessions
                             where revoked_at is null and expires_at > _server_now()));
end;
$$;
revoke all on function platform_system_status() from public, anon;
grant execute on function platform_system_status() to authenticated;

-- =========================================================================
-- 6) Notifications and settings
-- =========================================================================
create or replace function platform_notifications_list()
returns table (id uuid, title text, body text, is_active boolean, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin', 'admin');
  return query
  select n.id, n.title, n.body, n.is_active, n.created_at
    from notifications n order by n.created_at desc limit 100;
end;
$$;
revoke all on function platform_notifications_list() from public, anon;
grant execute on function platform_notifications_list() to authenticated;

create or replace function platform_notification_create(p_title text, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_body text := btrim(coalesce(p_body, ''));
begin
  perform _platform_need('super_admin', 'admin');
  if char_length(v_body) < 2 or char_length(v_body) > 600 then
    raise exception 'invalid_body' using errcode = 'P0001';
  end if;
  insert into notifications (title, body, is_active, created_by)
  values (nullif(left(btrim(coalesce(p_title, '')), 120), ''), v_body, true, auth.uid())
  returning id into v_id;
  perform _audit('notification_created', 'notification', v_id::text, null,
                 jsonb_build_object('title', p_title));
  return v_id;
end;
$$;
revoke all on function platform_notification_create(text, text) from public, anon;
grant execute on function platform_notification_create(text, text) to authenticated;

create or replace function platform_notification_set_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin', 'admin');
  update notifications set is_active = p_active where id = p_id;
  if not found then
    raise exception 'notification_not_found' using errcode = 'P0001';
  end if;
  perform _audit('notification_toggled', 'notification', p_id::text, null,
                 jsonb_build_object('active', p_active));
end;
$$;
revoke all on function platform_notification_set_active(uuid, boolean) from public, anon;
grant execute on function platform_notification_set_active(uuid, boolean) to authenticated;

create or replace function platform_settings_get()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin', 'admin');
  return coalesce((select jsonb_object_agg(key, value) from platform_settings), '{}'::jsonb);
end;
$$;
revoke all on function platform_settings_get() from public, anon;
grant execute on function platform_settings_get() to authenticated;

create or replace function platform_setting_set(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform _platform_need('super_admin');
  if p_key not in ('trial_presets_hours', 'paid_presets_days',
                   'expiry_warning_days', 'session_hours') then
    raise exception 'unknown_setting' using errcode = 'P0001';
  end if;
  if p_key in ('trial_presets_hours', 'paid_presets_days') then
    if jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) not between 1 and 8
       or exists (select 1 from jsonb_array_elements(p_value) e
                   where jsonb_typeof(e) <> 'number' or (e #>> '{}')::numeric not between 1 and 3650) then
      raise exception 'invalid_setting' using errcode = 'P0001';
    end if;
  elsif jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric not between 1 and 72 then
    raise exception 'invalid_setting' using errcode = 'P0001';
  end if;
  insert into platform_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, _server_now(), auth.uid())
  on conflict (key) do update
     set value = excluded.value, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
  perform _audit('platform_setting_changed', 'platform_setting', p_key, null, p_value);
end;
$$;
revoke all on function platform_setting_set(text, jsonb) from public, anon;
grant execute on function platform_setting_set(text, jsonb) to authenticated;

commit;
