-- 0058_member_invites.sql
-- Invitations by QR for new subscribers, and sign-in by phone number.
--
--   The platform administrator creates an invitation for a person: a name, a
--   phone number and what the account gets when they come in (a 3-day trial,
--   a permanent licence, or "wait for activation"). The invitation is a
--   one-time secret shown as a QR / short code that the administrator shows or
--   sends (image or text, e.g. by WhatsApp).
--
--   The invited person scans it (or pastes the code), TYPES THEIR PHONE NUMBER,
--   and a 4-digit code is sent by WhatsApp to the number the administrator
--   registered. Entering that code creates the account, links the phone, applies
--   the licence the administrator chose and signs them in. Whoever merely holds
--   the QR cannot get in: the code goes to the registered phone.
--
--   Later sign-ins use the same two steps without a QR: phone number +
--   WhatsApp code (member_phone_login_request).
--
-- Rules
--   * An invitation works once, expires (24 h by default, 1 h .. 7 days), can be
--     revoked, and 5 wrong phone numbers burn it.
--   * It never grants the administrator role: only a licence (trial / permanent
--     / pending). Making someone an administrator stays a separate, deliberate
--     step.
--   * Only the hash of the secret is stored.
--   * The account is created by the Edge Function (service role) with an
--     internal e-mail derived from the phone (p09XXXXXXXX@members.eshary.app);
--     nobody types or sees it.
--
-- Needs 0032 (_secret, _wa_chat_id, _mask_phone), 0034 (member_phones,
-- member_otps), 0040 (_new_otp4) and the Edge Function of this repo deployed.

begin;

-- -------------------------------------------------------------------------
-- 1) The invitations
-- -------------------------------------------------------------------------
create table if not exists member_invites (
  id              uuid primary key default gen_random_uuid(),
  token_hash      text not null unique,
  label           text not null check (length(btrim(label)) between 1 and 80),
  phone           text not null check (phone ~ '^09[0-9]{8}$'),
  license         text not null check (license in ('trial', 'lifetime', 'pending')),
  status          text not null default 'pending'
                  check (status in ('pending', 'used', 'revoked')),
  bad_phone_tries integer not null default 0,
  created_by      uuid not null,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  used_at         timestamptz,
  used_by         uuid references auth.users (id) on delete set null
);
create index if not exists member_invites_recent_idx
  on member_invites (created_at desc);
create index if not exists member_invites_phone_idx
  on member_invites (phone, status);
alter table member_invites enable row level security;
revoke all on member_invites from anon, authenticated;

-- The invitation behind a secret, only while it can still be used.
create or replace function _invite_by_token(p_token text)
returns member_invites
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v member_invites;
begin
  select * into v
    from member_invites i
   where i.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and i.status = 'pending'
     and i.expires_at > now();
  return v; -- all-null row when not found
end;
$$;
revoke all on function _invite_by_token(text) from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- 2) Administrator: create / list / revoke
-- -------------------------------------------------------------------------
create or replace function admin_create_member_invite(
  p_name    text,
  p_phone   text,
  p_license text,
  p_hours   integer default 24
) returns table (id uuid, token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name  text := btrim(coalesce(p_name, ''));
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_token text;
  v_id    uuid;
  v_exp   timestamptz;
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid_name' using errcode = 'P0001';
  end if;
  if v_phone !~ '^09[0-9]{8}$' then
    raise exception 'invalid_phone' using errcode = 'P0001';
  end if;
  if p_license is null or p_license not in ('trial', 'lifetime', 'pending') then
    raise exception 'invalid_license' using errcode = 'P0001';
  end if;
  if p_hours is null or p_hours < 1 or p_hours > 168 then
    raise exception 'invalid_hours' using errcode = 'P0001';
  end if;
  if exists (select 1 from member_phones mp where mp.phone = v_phone) then
    raise exception 'phone_taken' using errcode = 'P0001';
  end if;

  -- One open invitation per phone: a new one replaces the old.
  update member_invites i set status = 'revoked'
   where i.phone = v_phone and i.status = 'pending';

  v_token := encode(gen_random_bytes(32), 'hex');
  v_exp   := now() + make_interval(hours => p_hours);
  insert into member_invites (token_hash, label, phone, license, created_by, expires_at)
  values (encode(digest(v_token, 'sha256'), 'hex'), v_name, v_phone, p_license, auth.uid(), v_exp)
  returning member_invites.id into v_id;

  return query select v_id, v_token, v_exp;
end;
$$;
revoke all on function admin_create_member_invite(text, text, text, integer) from public, anon;
grant execute on function admin_create_member_invite(text, text, text, integer) to authenticated;

create or replace function admin_list_member_invites()
returns table (
  id          uuid,
  label       text,
  phone       text,
  license     text,
  status      text,
  created_at  timestamptz,
  expires_at  timestamptz,
  used_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  return query
  select i.id, i.label, i.phone, i.license,
         case when i.status = 'pending' and i.expires_at <= now()
              then 'expired' else i.status end,
         i.created_at, i.expires_at, i.used_at
    from member_invites i
   order by i.created_at desc
   limit 200;
end;
$$;
revoke all on function admin_list_member_invites() from public, anon;
grant execute on function admin_list_member_invites() to authenticated;

create or replace function admin_revoke_member_invite(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  update member_invites i set status = 'revoked'
   where i.id = p_id and i.status = 'pending';
  if not found then
    raise exception 'invite_not_found' using errcode = 'P0001';
  end if;
end;
$$;
revoke all on function admin_revoke_member_invite(uuid) from public, anon;
grant execute on function admin_revoke_member_invite(uuid) to authenticated;

-- -------------------------------------------------------------------------
-- 3) The invited person: preview, ask for the WhatsApp code
-- -------------------------------------------------------------------------
create or replace function member_invite_preview(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v member_invites := _invite_by_token(p_token);
begin
  if v.id is null then
    return jsonb_build_object('ok', false, 'code', 'invite_invalid');
  end if;
  return jsonb_build_object('ok', true, 'name', v.label, 'phone', _mask_phone(v.phone));
end;
$$;
revoke all on function member_invite_preview(text) from public;
grant execute on function member_invite_preview(text) to anon, authenticated;

create or replace function member_invite_request_otp(p_token text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v       member_invites := _invite_by_token(p_token);
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_key   text;
  v_base  text := _secret('wa_base_url');
  v_sess  text := _secret('wa_session_id');
  v_wa    text := _secret('wa_api_key');
  v_last  timestamptz;
  v_n     integer;
  v_tries integer;
  v_code  text;
  v_oid   uuid := gen_random_uuid();
begin
  if v.id is null then
    return jsonb_build_object('ok', false, 'code', 'invite_invalid');
  end if;
  if v_phone !~ '^09[0-9]{8}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if v_base is null or v_sess is null or v_wa is null then
    return jsonb_build_object('ok', false, 'code', 'sms_not_configured');
  end if;
  v_key := 'invite:' || v.id::text;

  -- The typed number must be the one the administrator registered.
  if v.phone <> v_phone then
    update member_invites i
       set bad_phone_tries = i.bad_phone_tries + 1,
           status = case when i.bad_phone_tries + 1 >= 5 then 'revoked' else i.status end
     where i.id = v.id
    returning i.bad_phone_tries into v_tries;
    if v_tries >= 5 then
      return jsonb_build_object('ok', false, 'code', 'invite_invalid');
    end if;
    return jsonb_build_object('ok', false, 'code', 'phone_mismatch', 'left', 5 - v_tries);
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
   where o.created_at > now() - interval '1 hour';
  if v_n >= 60 then
    return jsonb_build_object('ok', false, 'code', 'busy');
  end if;

  v_code := _new_otp4();
  begin
    insert into member_otps (id, email, phone, code_hash, expires_at)
    values (
      v_oid, v_key, v_phone,
      encode(digest(v_code || ':' || v_oid::text, 'sha256'), 'hex'),
      now() + interval '5 minutes'
    );
    perform net.http_post(
      url     := v_base || '/api/sessions/' || v_sess || '/messages/send-text',
      headers := jsonb_build_object('X-API-Key', v_wa, 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
                   'chatId', _wa_chat_id(v_phone),
                   'text',   'رمز الدخول لتطبيق إشاري: ' || v_code ||
                             E'\nصالح لمدة 5 دقائق. لا تشاركه مع أي شخص.')
    );
  exception when others then
    return jsonb_build_object('ok', false, 'code', 'send_failed');
  end;

  return jsonb_build_object('ok', true, 'phone', _mask_phone(v_phone));
end;
$$;
revoke all on function member_invite_request_otp(text, text) from public;
grant execute on function member_invite_request_otp(text, text) to anon, authenticated;

-- -------------------------------------------------------------------------
-- 4) The Edge Function side (service role only)
-- -------------------------------------------------------------------------
-- Checks the invitation + the WhatsApp code. p_commit = false only checks (a
-- wrong code still counts an attempt); true also burns the code.
create or replace function member_invite_consume(
  p_token  text,
  p_phone  text,
  p_otp    text,
  p_commit boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v       member_invites := _invite_by_token(p_token);
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_otp   text := regexp_replace(coalesce(p_otp, ''), '\D', '', 'g');
  v_o     member_otps;
begin
  if v.id is null then
    return jsonb_build_object('ok', false, 'code', 'invite_invalid');
  end if;
  if v.phone <> v_phone then
    return jsonb_build_object('ok', false, 'code', 'phone_mismatch');
  end if;

  select * into v_o
    from member_otps o
   where o.email = 'invite:' || v.id::text
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

  if exists (select 1 from member_phones mp where mp.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
  end if;
  if p_commit then
    update member_otps o set consumed_at = now() where o.id = v_o.id;
  end if;
  return jsonb_build_object(
    'ok', true, 'inviteId', v.id, 'name', v.label, 'license', v.license, 'phone', v.phone);
end;
$$;
revoke all on function member_invite_consume(text, text, text, boolean) from public, anon, authenticated;
grant execute on function member_invite_consume(text, text, text, boolean) to service_role;

-- After the account exists: link the phone, apply the licence the
-- administrator chose, mark the invitation used.
create or replace function member_invite_finish(p_invite uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v member_invites;
begin
  select * into v from member_invites i
   where i.id = p_invite and i.status = 'pending'
   for update;
  if not found then
    raise exception 'invite_invalid' using errcode = 'P0001';
  end if;
  if exists (select 1 from member_phones mp
              where mp.phone = v.phone and mp.user_id <> p_user) then
    raise exception 'phone_taken' using errcode = 'P0001';
  end if;

  insert into member_phones (user_id, phone) values (p_user, v.phone)
  on conflict (user_id) do nothing;

  if v.license = 'trial' then
    insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
    values (p_user, 'trial', 'trial', now() + interval '3 days', now(), v.created_by)
    on conflict (user_id) do update
      set status = 'trial', license_type = 'trial',
          trial_ends_at = now() + interval '3 days',
          activated_at = now(), activated_by = v.created_by;
  elsif v.license = 'lifetime' then
    insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
    values (p_user, 'active', 'lifetime', null, now(), v.created_by)
    on conflict (user_id) do update
      set status = 'active', license_type = 'lifetime', trial_ends_at = null,
          activated_at = now(), activated_by = v.created_by;
  else
    insert into account_licenses (user_id, status)
    values (p_user, 'pending')
    on conflict (user_id) do nothing;
  end if;

  update member_invites i
     set status = 'used', used_at = now(), used_by = p_user
   where i.id = v.id;
end;
$$;
revoke all on function member_invite_finish(uuid, uuid) from public, anon, authenticated;
grant execute on function member_invite_finish(uuid, uuid) to service_role;

create or replace function member_user_id_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = public, extensions
as $$
  select u.id from auth.users u where lower(u.email) = lower(p_email) limit 1
$$;
revoke all on function member_user_id_by_email(text) from public, anon, authenticated;
grant execute on function member_user_id_by_email(text) to service_role;

-- -------------------------------------------------------------------------
-- 5) Sign-in by phone number (a member whose phone is linked)
-- -------------------------------------------------------------------------
-- The e-mail behind a linked phone (never an administrator).
create or replace function member_email_for_phone(p_phone text)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$
  select lower(u.email)
    from member_phones mp
    join auth.users u on u.id = mp.user_id
   where mp.phone = regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g')
     and coalesce((select l.is_admin from account_licenses l where l.user_id = u.id), false) = false
   limit 1
$$;
revoke all on function member_email_for_phone(text) from public, anon, authenticated;
grant execute on function member_email_for_phone(text) to service_role;

create or replace function member_phone_login_request(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := regexp_replace(btrim(coalesce(p_phone, '')), '\s', '', 'g');
  v_email text;
  v_base  text := _secret('wa_base_url');
  v_sess  text := _secret('wa_session_id');
  v_wa    text := _secret('wa_api_key');
  v_last  timestamptz;
  v_n     integer;
  v_code  text;
  v_oid   uuid := gen_random_uuid();
begin
  if v_phone !~ '^09[0-9]{8}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if v_base is null or v_sess is null or v_wa is null then
    return jsonb_build_object('ok', false, 'code', 'sms_not_configured');
  end if;
  v_email := member_email_for_phone(v_phone);
  if v_email is null then
    return jsonb_build_object('ok', false, 'code', 'phone_not_found');
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
      headers := jsonb_build_object('X-API-Key', v_wa, 'Content-Type', 'application/json'),
      body    := jsonb_build_object(
                   'chatId', _wa_chat_id(v_phone),
                   'text',   'رمز الدخول لتطبيق إشاري: ' || v_code ||
                             E'\nصالح لمدة 5 دقائق. لا تشاركه مع أي شخص.')
    );
  exception when others then
    return jsonb_build_object('ok', false, 'code', 'send_failed');
  end;

  return jsonb_build_object('ok', true, 'phone', _mask_phone(v_phone));
end;
$$;
revoke all on function member_phone_login_request(text) from public;
grant execute on function member_phone_login_request(text) to anon, authenticated;

commit;
