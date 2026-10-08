-- 0033_qr_otp_without_email.sql
-- The registered e-mail is no longer part of the QR sign-in. The phone number
-- the admin registered is the identity check instead: the QR alone is not
-- enough, a 6-digit code must be typed that was sent by WhatsApp to THAT number.
--
-- Replaces the e-mail-taking versions from 0030 / 0032 with:
--   admin_create_employee_qr(sub_user_id, reset_device)   no e-mail required
--   employee_qr_preview(token)
--   employee_request_otp(token)
--   employee_verify_otp(token, otp)
--   employee_login_qr(token, device_id)                   still needs a verified OTP
--
-- Unchanged and still in place: single use, 10 minutes, revoked when a newer QR
-- or a new code is issued, device binding, OTP limits (5 min, 3 tries -> QR
-- burned, 45 s between sends, 3 sends per QR, 5 per employee per hour), the
-- audit rows from 0031. admin_set_employee_email and the registered_email
-- column stay in the database, unused.

begin;

drop function if exists employee_qr_preview(text, text);
drop function if exists employee_request_otp(text, text);
drop function if exists employee_verify_otp(text, text, text);
drop function if exists employee_login_qr(text, text, text);

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
  v_su         sub_users;
  v_token      text;
  v_exp        timestamptz := now() + interval '10 minutes';
  v_old_device text;
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
    v_old_device := v_su.device_id;
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
    insert into employee_activity_logs (
      parent_admin_id, sub_user_id, event_type, device_id
    ) values (
      auth.uid(), v_su.id, 'device_reset', v_old_device
    );
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

  insert into employee_activity_logs (
    parent_admin_id, sub_user_id, event_type
  ) values (
    auth.uid(), v_su.id, 'qr_issued'
  );

  return query select v_token, v_exp;
end;
$$;

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
create or replace function employee_request_otp(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t     employee_qr_tokens;
  v_su    sub_users;
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
    return jsonb_build_object('ok', false, 'code', 'send_failed');
  end;

  return jsonb_build_object('ok', true, 'phone', _mask_phone(v_su.phone_number));
end;
$$;

-- -------------------------------------------------------------------------
create or replace function employee_verify_otp(p_token text, p_otp text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t   employee_qr_tokens;
  v_su  sub_users;
  v_o   employee_otps;
  v_otp text := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
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
create or replace function employee_login_qr(p_token text, p_device_id text)
returns table (
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

  -- The identity check: a code delivered to the registered phone was verified.
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

revoke all on function admin_create_employee_qr(uuid, boolean) from public, anon;
revoke all on function employee_qr_preview(text)               from public, anon;
revoke all on function employee_request_otp(text)              from public, anon;
revoke all on function employee_verify_otp(text, text)         from public, anon;
revoke all on function employee_login_qr(text, text)           from public, anon;

grant execute on function admin_create_employee_qr(uuid, boolean) to authenticated;
grant execute on function employee_qr_preview(text)               to authenticated;
grant execute on function employee_request_otp(text)              to authenticated;
grant execute on function employee_verify_otp(text, text)         to authenticated;
grant execute on function employee_login_qr(text, text)           to authenticated;

commit;
