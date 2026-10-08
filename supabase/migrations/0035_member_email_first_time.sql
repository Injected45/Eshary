-- 0035_member_email_first_time.sql
-- The e-mail becomes a ONE-TIME verification for member accounts (no password):
--   * first time  (no phone linked yet): the person must prove BOTH the e-mail
--     (a code Supabase mails to it) and the phone (the WhatsApp code). After
--     that the account is bound to that e-mail and that phone.
--   * every later sign-in: e-mail + the linked phone + the WhatsApp code only.
--
-- Replaces member_request_otp / member_consume_otp from 0034. The Edge Function
-- `member-session` (updated) does the e-mail check with Supabase Auth and only
-- then finishes the sign-in.
--
-- Identity rules (_member_check_identity):
--   * unknown e-mail                        -> new account, e-mail proof needed
--   * known e-mail, phone already linked    -> must be the same phone, no e-mail proof
--   * known e-mail, no phone linked yet     -> e-mail proof needed (not for admins)
--   * a phone linked to another account     -> refused
--   * platform admin accounts never use this door

begin;

create or replace function _member_check_identity(p_email text, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_user  uuid;
  v_known text;
begin
  select u.id into v_user from auth.users u where lower(u.email) = p_email limit 1;

  if v_user is null then
    if exists (select 1 from member_phones mp where mp.phone = p_phone) then
      return jsonb_build_object('ok', false, 'code', 'phone_taken');
    end if;
    return jsonb_build_object('ok', true, 'userId', null, 'needsEmail', true);
  end if;

  if coalesce((select l.is_admin from account_licenses l where l.user_id = v_user), false) then
    return jsonb_build_object('ok', false, 'code', 'identity_mismatch');
  end if;

  select mp.phone into v_known from member_phones mp where mp.user_id = v_user;
  if v_known is not null then
    if v_known <> p_phone then
      return jsonb_build_object('ok', false, 'code', 'identity_mismatch');
    end if;
    return jsonb_build_object('ok', true, 'userId', v_user, 'needsEmail', false);
  end if;

  if exists (select 1 from member_phones mp where mp.phone = p_phone) then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
  end if;
  return jsonb_build_object('ok', true, 'userId', v_user, 'needsEmail', true);
end;
$$;
revoke all on function _member_check_identity(text, text) from public, anon, authenticated;

-- -------------------------------------------------------------------------
drop function if exists member_consume_otp(text, text, text);

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
  v_bytes bytea;
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

  v_bytes := gen_random_bytes(4);
  v_code := lpad(((
      (get_byte(v_bytes, 0)::bigint * 16777216)
    + (get_byte(v_bytes, 1) * 65536)
    + (get_byte(v_bytes, 2) * 256)
    +  get_byte(v_bytes, 3)
  ) % 1000000)::text, 6, '0');

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
-- Service role only. p_commit = false only CHECKS the code (a wrong code still
-- counts an attempt and burns after three) so the Edge Function can verify the
-- e-mail code in between; p_commit = true also marks it used.
-- -------------------------------------------------------------------------
create or replace function member_consume_otp(
  p_email  text,
  p_phone  text,
  p_otp    text,
  p_commit boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_otp   text := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
  v_o     member_otps;
  v_id    jsonb;
begin
  select * into v_o
    from member_otps o
   where o.email = v_email
     and o.phone = v_phone
     and o.consumed_at is null
     and o.expires_at > now()
   order by o.created_at desc
   limit 1
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'otp_expired');
  end if;
  if v_o.attempts >= 3 then
    return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
  end if;

  if encode(digest(v_otp || ':' || v_o.id::text, 'sha256'), 'hex') <> v_o.code_hash then
    update member_otps o set attempts = o.attempts + 1,
           consumed_at = case when o.attempts + 1 >= 3 then now() else null end
     where o.id = v_o.id;
    if v_o.attempts + 1 >= 3 then
      return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
    end if;
    return jsonb_build_object(
      'ok', false, 'code', 'invalid_otp', 'left', 3 - (v_o.attempts + 1));
  end if;

  -- Same identity rules as the request, checked again at the moment of use.
  v_id := _member_check_identity(v_email, v_phone);
  if (v_id ->> 'ok')::boolean is not true then
    return v_id;
  end if;

  if p_commit then
    update member_otps o set consumed_at = now() where o.id = v_o.id;
  end if;
  return v_id;
end;
$$;

revoke all on function member_request_otp(text, text)                     from public;
revoke all on function member_consume_otp(text, text, text, boolean)      from public, anon, authenticated;
grant execute on function member_request_otp(text, text)                  to anon, authenticated;
grant execute on function member_consume_otp(text, text, text, boolean)   to service_role;

commit;
