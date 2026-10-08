-- 0030_employee_registered_email.sql
-- The admin registers each employee's e-mail with their name and phone. A QR
-- then works only from a device signed in with that e-mail.
--
--   admin_set_employee_email(sub_user_id, email)   admin: register / change the e-mail
--   admin_create_employee_qr(...)                  now requires a registered e-mail
--   employee_qr_preview(token, email)              replaces the 1-arg version
--   employee_login_qr(token, device_id, email)     replaces the 2-arg version
--
-- Both employee functions return NO ROWS when the e-mail does not match the
-- registered one (the client reports 'email_mismatch'). Each mismatch is
-- counted on the token; after 3 the token is burned. A mismatch reveals
-- nothing about the employee (no name, no phone).
--
-- Limit: the e-mail is reported by the app, not verified by the server (that
-- needs a server-side Google ID-token check). The one-time QR remains the
-- secret; the e-mail check adds a second factor the QR holder must know.

begin;

alter table sub_users
  add column if not exists registered_email text;

alter table employee_qr_tokens
  add column if not exists failed_attempts integer not null default 0;

-- -------------------------------------------------------------------------
create or replace function admin_set_employee_email(
  p_sub_user_id uuid,
  p_email       text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if length(v_email) > 254
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email' using errcode = 'P0001';
  end if;

  update sub_users s
     set registered_email = v_email,
         updated_at       = now()
   where s.id = p_sub_user_id
     and s.parent_admin_id = auth.uid();
  if not found then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  -- A different e-mail invalidates any QR issued for the previous one.
  delete from employee_qr_tokens t where t.sub_user_id = p_sub_user_id;
end;
$$;

-- -------------------------------------------------------------------------
-- Same as 0029, plus: the employee must have a registered e-mail.
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
  if v_su.registered_email is null then
    raise exception 'email_required' using errcode = 'P0001';
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
drop function if exists employee_qr_preview(text);
drop function if exists employee_login_qr(text, text);

create or replace function employee_qr_preview(p_token text, p_email text)
returns table (employee_name text, phone_number text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t     employee_qr_tokens;
  v_su    sub_users;
  v_email text := lower(trim(coalesce(p_email, '')));
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
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
     and s.login_code_hash = v_t.code_hash;
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  if v_su.registered_email is null or v_su.registered_email <> v_email then
    update employee_qr_tokens t
       set failed_attempts = t.failed_attempts + 1,
           used_at = case when t.failed_attempts + 1 >= 3 then now() else null end
     where t.id = v_t.id;
    return;  -- no rows → 'email_mismatch' on the client
  end if;

  return query select v_su.employee_name, v_su.phone_number;
end;
$$;

create or replace function employee_login_qr(
  p_token     text,
  p_device_id text,
  p_email     text
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
  v_email      text := lower(trim(coalesce(p_email, '')));
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

  if v_su.registered_email is null or v_su.registered_email <> v_email then
    update employee_qr_tokens t
       set failed_attempts = t.failed_attempts + 1,
           used_at = case when t.failed_attempts + 1 >= 3 then now() else null end
     where t.id = v_t.id;
    return;  -- no rows → 'email_mismatch' on the client
  end if;

  if v_su.device_id is null then
    update sub_users s
       set device_id          = p_device_id,
           login_code_used    = true,
           login_code_used_at = now(),
           last_login_at      = now(),
           google_email       = v_email,
           google_email_at    = now(),
           updated_at         = now()
     where s.id = v_su.id;
  elsif v_su.device_id = p_device_id then
    update sub_users s
       set last_login_at   = now(),
           google_email    = v_email,
           google_email_at = now(),
           updated_at      = now()
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

revoke all on function admin_set_employee_email(uuid, text)    from public, anon;
revoke all on function employee_qr_preview(text, text)         from public, anon;
revoke all on function employee_login_qr(text, text, text)     from public, anon;

grant execute on function admin_set_employee_email(uuid, text) to authenticated;
grant execute on function employee_qr_preview(text, text)      to authenticated;
grant execute on function employee_login_qr(text, text, text)  to authenticated;

commit;
