-- 0040_otp_four_digits.sql
-- The WhatsApp verification code is now 4 digits instead of 6 (member sign-up /
-- sign-in and the employee QR sign-in). Only the generator changes; everything
-- else is as before: 5 minutes of validity, 3 wrong tries burn the code, one
-- send per 45 s, 3 sends per phone / per QR and 5 per e-mail / per employee per
-- hour, 60 sends per hour overall.
--
-- Trade-off: 10,000 possible codes instead of 1,000,000. With only 3 tries per
-- code a guesser succeeds with probability 3/10,000 per issued code, and the
-- send limits above cap how many codes can be issued, plus the attacker first
-- needs the e-mail+phone pair (members) or a valid single-use QR (employees).
--
-- Replaces member_request_otp (0035) and employee_request_otp (0033). The
-- checking functions are unchanged (they compare whatever digits were issued).
-- The employee's temporary login code from the admin stays 6 digits.

begin;

create or replace function _new_otp4() returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
  v_bytes bytea := gen_random_bytes(4);
begin
  return lpad(((
      (get_byte(v_bytes, 0)::bigint * 16777216)
    + (get_byte(v_bytes, 1) * 65536)
    + (get_byte(v_bytes, 2) * 256)
    +  get_byte(v_bytes, 3)
  ) % 10000)::text, 4, '0');
end;
$$;
revoke all on function _new_otp4() from public, anon, authenticated;

-- -------------------------------------------------------------------------
create or replace function member_request_otp(p_email text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_base  text := _secret('wa_base_url');
  v_sess  text := _secret('wa_session_id');
  v_key   text := _secret('wa_api_key');
  v_id    jsonb;
  v_last  timestamptz;
  v_n     integer;
  v_code  text;
  v_oid   uuid := gen_random_uuid();
begin
  if length(v_email) > 254
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_email');
  end if;
  if v_phone !~ '^09[0-9]{8}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if v_base is null or v_sess is null or v_key is null then
    return jsonb_build_object('ok', false, 'code', 'sms_not_configured');
  end if;

  v_id := _member_check_identity(v_email, v_phone);
  if (v_id ->> 'ok')::boolean is not true then
    return v_id;
  end if;

  select max(o.created_at) into v_last from member_otps o where o.phone = v_phone;
  if v_last is not null and v_last > now() - interval '45 seconds' then
    return jsonb_build_object(
      'ok', false, 'code', 'too_soon',
      'wait', ceil(extract(epoch from (v_last + interval '45 seconds' - now())))::int);
  end if;
  select count(*) into v_n from member_otps o
   where o.phone = v_phone and o.created_at > now() - interval '1 hour';
  if v_n >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many_sends');
  end if;
  select count(*) into v_n from member_otps o
   where o.email = v_email and o.created_at > now() - interval '1 hour';
  if v_n >= 5 then
    return jsonb_build_object('ok', false, 'code', 'too_many_sends');
  end if;
  select count(*) into v_n from member_otps o
   where o.created_at > now() - interval '1 hour';
  if v_n >= 60 then
    return jsonb_build_object('ok', false, 'code', 'busy');
  end if;

  v_code := _new_otp4();

  begin
    insert into member_otps (id, email, phone, code_hash, expires_at)
    values (
      v_oid, v_email, v_phone,
      encode(digest(v_code || ':' || v_oid::text, 'sha256'), 'hex'),
      now() + interval '5 minutes'
    );

    perform net.http_post(
      url     := v_base || '/api/sessions/' || v_sess || '/messages/send-text',
      headers := jsonb_build_object(
                   'X-API-Key', v_key,
                   'Content-Type', 'application/json'),
      body    := jsonb_build_object(
                   'chatId', _wa_chat_id(v_phone),
                   'text',   'رمز الدخول لتطبيق إشاري: ' || v_code ||
                             E'\nصالح لمدة 5 دقائق. لا تشاركه مع أي شخص.')
    );
  exception when others then
    return jsonb_build_object('ok', false, 'code', 'send_failed');
  end;

  return jsonb_build_object(
    'ok', true,
    'phone', _mask_phone(v_phone),
    'isNew', (v_id -> 'userId') = 'null'::jsonb,
    'needsEmail', (v_id ->> 'needsEmail')::boolean);
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

  v_code := _new_otp4();

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

commit;
