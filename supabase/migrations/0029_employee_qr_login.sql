-- 0029_employee_qr_login.sql
-- Employee sign-in by QR code issued by the admin.
--
--   admin_create_employee_qr(sub_user_id, reset_device)  admin: issue a QR token
--   employee_qr_preview(token)                           employee: name + phone behind a QR
--   employee_login_qr(token, device_id)                  employee: sign in with the QR
--   employee_set_google_email(email)                     employee: attach the Google e-mail
--
-- Security model:
--   * The token is 256 random bits, stored only as a SHA-256 hash.
--   * Single use, valid for 10 minutes, and revoked as soon as the admin
--     issues a newer QR or regenerates the employee's login code.
--   * Only the owning admin can issue one; the employee must be active.
--   * Device binding works exactly like the phone + code login: the first
--     sign-in binds the device, any other device gets 'device_mismatch'
--     (and the token is NOT consumed). The admin can pass reset_device to
--     move the employee to a new phone in the same step.
--   * The Google e-mail is an identification label for the admin, supplied
--     by the client: it is not verified server-side and grants nothing.
--   * employee_qr_tokens has RLS on and no policies, so it is reachable only
--     through the functions below.

begin;

alter table sub_users
  add column if not exists google_email    text,
  add column if not exists google_email_at timestamptz;

create table if not exists employee_qr_tokens (
  id           uuid primary key default gen_random_uuid(),
  sub_user_id  uuid not null references sub_users(id) on delete cascade,
  token_hash   text not null unique,
  -- Snapshot of sub_users.login_code_hash: regenerating the code changes the
  -- hash, which silently revokes any outstanding QR.
  code_hash    text not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  used_at      timestamptz
);

create index if not exists employee_qr_tokens_sub_user_idx
  on employee_qr_tokens (sub_user_id);

alter table employee_qr_tokens enable row level security;
revoke all on employee_qr_tokens from anon, authenticated;

-- -------------------------------------------------------------------------
-- Admin: issue a QR token for one of their employees.
-- -------------------------------------------------------------------------
create or replace function admin_create_employee_qr(
  p_sub_user_id  uuid,
  p_reset_device boolean default false
) returns table (token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_su    sub_users;
  v_token text;
  v_exp   timestamptz := now() + interval '10 minutes';
begin
  select * into v_su
    from sub_users s
   where s.id = p_sub_user_id
     and s.parent_admin_id = auth.uid();
  if not found then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;
  if v_su.status <> 'active' then
    raise exception 'sub_user_disabled' using errcode = 'P0001';
  end if;

  if p_reset_device then
    update sub_users s
       set device_id          = null,
           login_code_used    = false,
           login_code_used_at = null,
           updated_at         = now()
     where s.id = v_su.id;
    update employee_sessions es
       set is_active = false,
           ended_at  = now()
     where es.sub_user_id = v_su.id
       and es.is_active;
  end if;

  -- Revoke earlier unused QRs and tidy expired ones.
  delete from employee_qr_tokens t
   where t.sub_user_id = v_su.id
     and (t.used_at is null or t.expires_at < now());

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into employee_qr_tokens (sub_user_id, token_hash, code_hash, expires_at)
  values (
    v_su.id,
    encode(digest(v_token, 'sha256'), 'hex'),
    v_su.login_code_hash,
    v_exp
  );

  return query select v_token, v_exp;
end;
$$;

-- -------------------------------------------------------------------------
-- Employee: look at who a QR belongs to before confirming the sign-in.
-- -------------------------------------------------------------------------
create or replace function employee_qr_preview(p_token text)
returns table (employee_name text, phone_number text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t  employee_qr_tokens;
  v_su sub_users;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;

  select * into v_t
    from employee_qr_tokens t
   where t.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and t.used_at is null
     and t.expires_at > now();
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  select * into v_su
    from sub_users s
   where s.id = v_t.sub_user_id
     and s.status = 'active'
     and s.login_code_hash = v_t.code_hash;
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  return query select v_su.employee_name, v_su.phone_number;
end;
$$;

-- -------------------------------------------------------------------------
-- Employee: sign in with the QR. Same result shape and side effects as
-- employee_login (session row, device binding, 'login' activity log).
-- -------------------------------------------------------------------------
create or replace function employee_login_qr(
  p_token     text,
  p_device_id text
) returns table (
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  session_id      uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t          employee_qr_tokens;
  v_su         sub_users;
  v_session_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'device_id_required' using errcode = 'P0001';
  end if;

  select * into v_t
    from employee_qr_tokens t
   where t.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and t.used_at is null
     and t.expires_at > now()
   for update;
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  select * into v_su
    from sub_users s
   where s.id = v_t.sub_user_id
     and s.status = 'active'
     and s.login_code_hash = v_t.code_hash
   for update;
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  if v_su.device_id is null then
    update sub_users s
       set device_id          = p_device_id,
           login_code_used    = true,
           login_code_used_at = now(),
           last_login_at      = now(),
           updated_at         = now()
     where s.id = v_su.id;
  elsif v_su.device_id = p_device_id then
    update sub_users s
       set last_login_at = now(),
           updated_at    = now()
     where s.id = v_su.id;
  else
    -- Raising rolls the whole call back, so the token stays unused.
    raise exception 'device_mismatch' using errcode = 'P0001';
  end if;

  update employee_qr_tokens t
     set used_at = now()
   where t.id = v_t.id;

  update employee_sessions es
     set is_active = false,
         ended_at  = now()
   where es.sub_user_id = v_su.id
     and es.is_active;

  insert into employee_sessions (sub_user_id, anonymous_user_id, device_id)
  values (v_su.id, auth.uid(), p_device_id)
  returning id into v_session_id;

  insert into employee_activity_logs (
    parent_admin_id, sub_user_id, session_id, event_type, device_id
  ) values (
    v_su.parent_admin_id, v_su.id, v_session_id, 'login', p_device_id
  );

  return query select
    v_su.id,
    v_su.parent_admin_id,
    v_su.employee_name,
    v_session_id;
end;
$$;

-- -------------------------------------------------------------------------
-- Employee: attach the Google e-mail picked on the device to the employee
-- record, so the admin can see who is behind the device. Informational only.
-- -------------------------------------------------------------------------
create or replace function employee_set_google_email(p_email text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if length(v_email) > 254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email' using errcode = 'P0001';
  end if;

  update sub_users s
     set google_email    = v_email,
         google_email_at = now()
   where s.id = (
     select es.sub_user_id
       from employee_sessions es
      where es.anonymous_user_id = auth.uid()
        and es.is_active
      limit 1
   );
end;
$$;

revoke all on function admin_create_employee_qr(uuid, boolean)  from public, anon;
revoke all on function employee_qr_preview(text)                from public, anon;
revoke all on function employee_login_qr(text, text)            from public, anon;
revoke all on function employee_set_google_email(text)          from public, anon;

grant execute on function admin_create_employee_qr(uuid, boolean) to authenticated;
grant execute on function employee_qr_preview(text)               to authenticated;
grant execute on function employee_login_qr(text, text)           to authenticated;
grant execute on function employee_set_google_email(text)         to authenticated;

commit;
