-- 0034_member_phone_otp_login.sql
-- Password-less account creation / sign-in for new subscribers ("members"):
-- e-mail + phone number + a 6-digit code sent by WhatsApp to that phone.
--
--   member_phones                       one verified phone per account
--   member_request_otp(email, phone)    anon-callable: validates, rate-limits and
--                                       sends the code through the WhatsApp gateway
--   member_consume_otp(email, phone, otp)   SERVICE ROLE ONLY: checks the code
--   member_link_phone(user_id, phone)       SERVICE ROLE ONLY: binds the phone
--
-- The session itself is issued by the Edge Function `member-session`
-- (supabase/functions/member-session/index.ts): it calls member_consume_otp with
-- the service role, creates the auth user when needed (new accounts then follow
-- the existing licence flow: status 'pending' until the platform admin approves),
-- binds the phone, and returns a one-time token the app exchanges for a session.
-- The code can therefore only be checked server-side; the app cannot verify it.
--
-- Rules:
--   * existing e-mail  -> the phone must be the one linked to that account;
--     accounts with no linked phone (e.g. the platform admin) never use this door.
--   * new e-mail       -> the phone must not already belong to another account.
--   * a code lives 5 minutes, 3 wrong tries burn it, 45 s between sends,
--     3 sends per phone and 5 per e-mail per hour, 60 sends per hour overall
--     (the overall cap stops the endpoint being used to spam WhatsApp).
--
-- Needs 0032 first (app_secrets, _secret, _wa_chat_id, _mask_phone) and pg_net.

begin;

create table if not exists member_phones (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  phone      text not null unique check (phone ~ '^09[0-9]{8}$'),
  created_at timestamptz not null default now()
);
alter table member_phones enable row level security;
revoke all on member_phones from anon, authenticated;

create table if not exists member_otps (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  phone       text not null,
  code_hash   text not null,
  attempts    integer not null default 0,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  consumed_at timestamptz
);
create index if not exists member_otps_email_idx on member_otps (email, created_at desc);
create index if not exists member_otps_phone_idx on member_otps (phone, created_at desc);
alter table member_otps enable row level security;
revoke all on member_otps from anon, authenticated;

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
  v_user  uuid;
  v_known text;
  v_last  timestamptz;
  v_n     integer;
  v_bytes bytea;
  v_code  text;
  v_id    uuid := gen_random_uuid();
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

  select u.id into v_user from auth.users u where lower(u.email) = v_email limit 1;
  if v_user is not null then
    select mp.phone into v_known from member_phones mp where mp.user_id = v_user;
    if v_known is null or v_known <> v_phone then
      return jsonb_build_object('ok', false, 'code', 'identity_mismatch');
    end if;
  elsif exists (select 1 from member_phones mp where mp.phone = v_phone) then
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
      v_id, v_email, v_phone,
      encode(digest(v_code || ':' || v_id::text, 'sha256'), 'hex'),
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
    'ok', true, 'phone', _mask_phone(v_phone), 'isNew', v_user is null);
end;
$$;

-- -------------------------------------------------------------------------
-- Service role only. Never raises on a wrong code, so the attempt counter is
-- not rolled back with the call.
-- -------------------------------------------------------------------------
create or replace function member_consume_otp(p_email text, p_phone text, p_otp text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_otp   text := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
  v_o     member_otps;
  v_user  uuid;
  v_known text;
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
  select u.id into v_user from auth.users u where lower(u.email) = v_email limit 1;
  if v_user is not null then
    select mp.phone into v_known from member_phones mp where mp.user_id = v_user;
    if v_known is null or v_known <> v_phone then
      return jsonb_build_object('ok', false, 'code', 'identity_mismatch');
    end if;
  elsif exists (select 1 from member_phones mp where mp.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
  end if;

  update member_otps o set consumed_at = now() where o.id = v_o.id;
  return jsonb_build_object('ok', true, 'userId', v_user);
end;
$$;

create or replace function member_link_phone(p_user_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into member_phones (user_id, phone)
  values (p_user_id, p_phone)
  on conflict (user_id) do nothing;
end;
$$;

revoke all on function member_request_otp(text, text)           from public;
revoke all on function member_consume_otp(text, text, text)     from public, anon, authenticated;
revoke all on function member_link_phone(uuid, text)            from public, anon, authenticated;

grant execute on function member_request_otp(text, text)        to anon, authenticated;
grant execute on function member_consume_otp(text, text, text)  to service_role;
grant execute on function member_link_phone(uuid, text)         to service_role;

commit;
