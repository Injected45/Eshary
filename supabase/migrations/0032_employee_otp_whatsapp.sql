-- 0032_employee_otp_whatsapp.sql
-- Second factor for the QR sign-in: after the QR + e-mail check, a 6-digit
-- code is sent by WhatsApp to the phone number the admin registered for the
-- employee, and must be entered before the sign-in completes.
--
--   employee_request_otp(token, email)        send a code to the registered phone
--   employee_verify_otp(token, email, otp)    check it (non-raising, so attempts persist)
--   employee_login_qr(...)                    now refuses unless the OTP was verified
--
-- The WhatsApp gateway credentials live ONLY in app_secrets (no client access),
-- never in the app. Set them once, by hand, in the SQL editor (see the bottom
-- of this file). Delivery uses the pg_net extension (Database -> Extensions).
--
-- Limits: a code lives 5 minutes, allows 3 wrong tries (then the QR is burned),
-- one send per 45 s, max 3 sends per QR and 5 per employee per hour.

begin;

create extension if not exists pg_net;

-- -------------------------------------------------------------------------
create table if not exists app_secrets (
  key   text primary key,
  value text not null
);
alter table app_secrets enable row level security;
revoke all on app_secrets from anon, authenticated;

create or replace function _secret(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select s.value from app_secrets s where s.key = p_key
$$;
revoke all on function _secret(text) from public, anon, authenticated;

-- Libyan 09XXXXXXXX -> 2189XXXXXXXX@c.us (the DB already enforces ^09[0-9]{8}$).
create or replace function _wa_chat_id(p_phone text) returns text
language sql immutable as $$
  select '218' || substr(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 2) || '@c.us'
$$;

create or replace function _mask_phone(p_phone text) returns text
language sql immutable as $$
  select left(coalesce(p_phone, ''), 2) || '*****' || right(coalesce(p_phone, ''), 3)
$$;
revoke all on function _wa_chat_id(text), _mask_phone(text) from public, anon, authenticated;

-- -------------------------------------------------------------------------
create table if not exists employee_otps (
  id          uuid primary key default gen_random_uuid(),
  token_id    uuid not null references employee_qr_tokens(id) on delete cascade,
  sub_user_id uuid not null references sub_users(id) on delete cascade,
  code_hash   text not null,
  attempts    integer not null default 0,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  verified_at timestamptz
);
create index if not exists employee_otps_token_idx
  on employee_otps (token_id, created_at desc);
create index if not exists employee_otps_sub_user_idx
  on employee_otps (sub_user_id, created_at desc);
alter table employee_otps enable row level security;
revoke all on employee_otps from anon, authenticated;

-- -------------------------------------------------------------------------
create or replace function employee_request_otp(p_token text, p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t     employee_qr_tokens;
  v_su    sub_users;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_base  text := _secret('wa_base_url');
  v_sess  text := _secret('wa_session_id');
  v_key   text := _secret('wa_api_key');
  v_bytes bytea;
  v_code  text;
  v_last  timestamptz;
  v_sent  integer;
  v_hour  integer;
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
    return jsonb_build_object('ok', false, 'code', 'email_mismatch');
  end if;

  if v_base is null or v_sess is null or v_key is null then
    return jsonb_build_object('ok', false, 'code', 'sms_not_configured');
  end if;

  select max(o.created_at), count(*) into v_last, v_sent
    from employee_otps o where o.token_id = v_t.id;
  if v_last is not null and v_last > now() - interval '45 seconds' then
    return jsonb_build_object(
      'ok', false, 'code', 'too_soon',
      'wait', ceil(extract(epoch from (v_last + interval '45 seconds' - now())))::int);
  end if;
  if v_sent >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many_sends');
  end if;
  select count(*) into v_hour
    from employee_otps o
   where o.sub_user_id = v_su.id and o.created_at > now() - interval '1 hour';
  if v_hour >= 5 then
    return jsonb_build_object('ok', false, 'code', 'too_many_sends');
  end if;

  v_bytes := gen_random_bytes(4);
  v_code := lpad(((
      (get_byte(v_bytes, 0)::bigint * 16777216)
    + (get_byte(v_bytes, 1) * 65536)
    + (get_byte(v_bytes, 2) * 256)
    +  get_byte(v_bytes, 3)
  ) % 1000000)::text, 6, '0');

  begin
    insert into employee_otps (token_id, sub_user_id, code_hash, expires_at)
    values (
      v_t.id, v_su.id,
      encode(digest(v_code || ':' || v_t.id::text, 'sha256'), 'hex'),
      now() + interval '5 minutes'
    );

    perform net.http_post(
      url     := v_base || '/api/sessions/' || v_sess || '/messages/send-text',
      headers := jsonb_build_object(
                   'X-API-Key', v_key,
                   'Content-Type', 'application/json'),
      body    := jsonb_build_object(
                   'chatId', _wa_chat_id(v_su.phone_number),
                   'text',   'رمز التحقق لتطبيق إشاري: ' || v_code ||
                             E'\nصالح لمدة 5 دقائق. لا تشاركه مع أي شخص.')
    );
  exception when others then
    -- The insert above is rolled back with this block: a failed send costs nothing.
    return jsonb_build_object('ok', false, 'code', 'send_failed');
  end;

  return jsonb_build_object('ok', true, 'phone', _mask_phone(v_su.phone_number));
end;
$$;

-- -------------------------------------------------------------------------
create or replace function employee_verify_otp(
  p_token text,
  p_email text,
  p_otp   text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t     employee_qr_tokens;
  v_su    sub_users;
  v_o     employee_otps;
  v_email text := lower(trim(coalesce(p_email, '')));
  v_otp   text := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
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
    return jsonb_build_object('ok', false, 'code', 'email_mismatch');
  end if;

  select * into v_o
    from employee_otps o
   where o.token_id = v_t.id
   order by o.created_at desc
   limit 1
   for update;
  if not found or v_o.expires_at <= now() then
    return jsonb_build_object('ok', false, 'code', 'otp_expired');
  end if;
  if v_o.verified_at is not null then
    return jsonb_build_object('ok', true);
  end if;
  if v_o.attempts >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
  end if;

  if encode(digest(v_otp || ':' || v_t.id::text, 'sha256'), 'hex') = v_o.code_hash then
    update employee_otps o set verified_at = now() where o.id = v_o.id;
    return jsonb_build_object('ok', true);
  end if;

  update employee_otps o set attempts = o.attempts + 1 where o.id = v_o.id;
  if v_o.attempts + 1 >= 3 then
    -- Three wrong codes: the QR is burned, the admin must issue a new one.
    update employee_qr_tokens t set used_at = now() where t.id = v_t.id;
    return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
  end if;
  return jsonb_build_object(
    'ok', false, 'code', 'invalid_otp', 'left', 3 - (v_o.attempts + 1));
end;
$$;

-- -------------------------------------------------------------------------
-- employee_login_qr: same as 0030, plus the verified-OTP requirement.
-- -------------------------------------------------------------------------
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
    return;
  end if;

  -- Second factor: a code delivered to the registered phone was verified.
  if not exists (
    select 1 from employee_otps o
     where o.token_id = v_t.id
       and o.verified_at is not null
       and o.verified_at > now() - interval '10 minutes'
  ) then
    raise exception 'otp_required' using errcode = 'P0001';
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

revoke all on function employee_request_otp(text, text)      from public, anon;
revoke all on function employee_verify_otp(text, text, text) from public, anon;
grant execute on function employee_request_otp(text, text)      to authenticated;
grant execute on function employee_verify_otp(text, text, text) to authenticated;

commit;

-- ---------------------------------------------------------------------------
-- ONE-TIME SETUP, run by hand AFTER this migration (do not commit the key):
--
--   insert into app_secrets (key, value) values
--     ('wa_base_url',   'https://wa.rhalla.online'),
--     ('wa_session_id', 'ba104528-002c-4373-9aab-113db591e0fc'),
--     ('wa_api_key',    '<PUT THE API KEY HERE>')
--   on conflict (key) do update set value = excluded.value;
-- ---------------------------------------------------------------------------
