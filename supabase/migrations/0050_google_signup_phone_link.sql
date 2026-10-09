-- 0050_google_signup_phone_link.sql
-- Creating an account is done with Google; the phone is then proven with ONE
-- WhatsApp code. No e-mail code and no typed e-mail.
--
--   1. The person taps "إنشاء حساب جديد" and chooses a Google account on the
--      phone. Google signs the e-mail address; Supabase verifies that signature
--      (signInWithIdToken), so the address is proven to belong to them.
--   2. They type their phone number; a 4-digit code is sent by WhatsApp to it.
--   3. They enter the code: the phone is linked to the account. The account then
--      waits for the administrator's approval like any new account.
--
-- The caller is already signed in, so these functions need no Edge Function and
-- take the e-mail from the session (auth.uid()), never from the request.
--
--   member_needs_phone()               true while a NEW account (licence still
--                                      'pending') has no phone linked
--   member_request_phone_otp(phone)    validates, rate-limits, sends the code
--   member_confirm_phone(phone, otp)   checks the code, links the phone
--
-- Accounts that already work (active / trial / blocked / expired licences),
-- platform admins, and employees (anonymous sessions) are never asked.
--
-- The old door (e-mail + phone + code, 0034–0049) now serves only RETURNING
-- members: an e-mail that is not registered is refused with `use_google`,
-- because nothing proves it belongs to the person (this supersedes 0049).
--
-- Needs 0032 (_secret, _wa_chat_id, _mask_phone), 0034 (member_phones,
-- member_otps) and 0040 (_new_otp4).

begin;

-- -------------------------------------------------------------------------
-- 1) A brand-new e-mail can no longer open an account through the old door
-- -------------------------------------------------------------------------
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
    -- New accounts are created with Google, which proves the address.
    return jsonb_build_object('ok', false, 'code', 'use_google');
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
  -- An existing account with no phone yet still proves its address by e-mail.
  return jsonb_build_object('ok', true, 'userId', v_user, 'needsEmail', true);
end;
$$;
revoke all on function _member_check_identity(text, text) from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- 2) Who is the caller, as a member who may link a phone
-- -------------------------------------------------------------------------
create or replace function _member_caller()
returns table (user_id uuid, email text, confirmed boolean)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select u.id, lower(u.email), u.email_confirmed_at is not null
    from auth.users u
   where u.id = auth.uid()
     and coalesce(u.is_anonymous, false) = false
     and current_employee_id() is null
$$;
revoke all on function _member_caller() from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- 3) Does this account still have to link a phone?
-- -------------------------------------------------------------------------
create or replace function member_needs_phone()
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid;
begin
  select c.user_id into v_uid from _member_caller() c;
  if v_uid is null then
    return false;
  end if;
  if coalesce((select l.is_admin from account_licenses l where l.user_id = v_uid), false) then
    return false;
  end if;
  if exists (select 1 from member_phones mp where mp.user_id = v_uid) then
    return false;
  end if;
  -- Only accounts still waiting for approval: nobody who already works with
  -- the app is locked out by this rule.
  return coalesce(
    (select l.status from account_licenses l where l.user_id = v_uid), 'pending'
  ) = 'pending';
end;
$$;
revoke all on function member_needs_phone() from public, anon;
grant execute on function member_needs_phone() to authenticated;

-- -------------------------------------------------------------------------
-- 4) Send the WhatsApp code to the phone the signed-in person typed
-- -------------------------------------------------------------------------
create or replace function member_request_phone_otp(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_uid   uuid;
  v_email text;
  v_ok    boolean;
  v_base  text := _secret('wa_base_url');
  v_sess  text := _secret('wa_session_id');
  v_key   text := _secret('wa_api_key');
  v_last  timestamptz;
  v_n     integer;
  v_code  text;
  v_oid   uuid := gen_random_uuid();
begin
  select c.user_id, c.email, c.confirmed into v_uid, v_email, v_ok from _member_caller() c;
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'not_authorized');
  end if;
  -- The address must have been confirmed (Google confirms it).
  if v_ok is not true or v_email is null then
    return jsonb_build_object('ok', false, 'code', 'email_not_confirmed');
  end if;
  if coalesce((select l.is_admin from account_licenses l where l.user_id = v_uid), false) then
    return jsonb_build_object('ok', false, 'code', 'not_authorized');
  end if;
  if v_phone !~ '^09[0-9]{8}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if v_base is null or v_sess is null or v_key is null then
    return jsonb_build_object('ok', false, 'code', 'sms_not_configured');
  end if;
  if exists (select 1 from member_phones mp where mp.user_id = v_uid) then
    return jsonb_build_object('ok', false, 'code', 'already_linked');
  end if;
  if exists (select 1 from member_phones mp where mp.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
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
                   'text',   'رمز التحقق لتطبيق إشاري: ' || v_code ||
                             E'\nصالح لمدة 5 دقائق. لا تشاركه مع أي شخص.')
    );
  exception when others then
    return jsonb_build_object('ok', false, 'code', 'send_failed');
  end;

  return jsonb_build_object('ok', true, 'phone', _mask_phone(v_phone));
end;
$$;
revoke all on function member_request_phone_otp(text) from public, anon;
grant execute on function member_request_phone_otp(text) to authenticated;

-- -------------------------------------------------------------------------
-- 5) Check the code and link the phone
-- -------------------------------------------------------------------------
create or replace function member_confirm_phone(p_phone text, p_otp text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_otp   text := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
  v_uid   uuid;
  v_email text;
  v_ok    boolean;
  v_o     member_otps;
begin
  select c.user_id, c.email, c.confirmed into v_uid, v_email, v_ok from _member_caller() c;
  if v_uid is null or v_ok is not true or v_email is null then
    return jsonb_build_object('ok', false, 'code', 'not_authorized');
  end if;
  if exists (select 1 from member_phones mp where mp.user_id = v_uid) then
    return jsonb_build_object('ok', false, 'code', 'already_linked');
  end if;

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

  begin
    insert into member_phones (user_id, phone) values (v_uid, v_phone);
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
  end;
  update member_otps o set consumed_at = now() where o.id = v_o.id;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function member_confirm_phone(text, text) from public, anon;
grant execute on function member_confirm_phone(text, text) to authenticated;

commit;
