-- 0066_auth_hardening.sql
-- Findings of the security review of the activation and sign-in flows:
--  1. The phone sign-in told anyone whether a number belongs to a subscriber
--     ("phone_not_found" vs a code being sent). A number we do not know now gets
--     the same answer, the same wait and the same limits as a subscriber's, and
--     nothing is sent. (login_request, login_verify)
--  2. The per-address limits (5 trial requests / 10 codes an hour) were low for
--     places where many people share one address (offices, mobile carriers), so
--     honest users could be refused. They are raised to 20 and 40; the strict
--     limits stay per phone (a code every 60 s, five an hour, five tries per code,
--     fifteen wrong tries an hour).
-- Safe to run more than once.

begin;

create or replace function _issue_challenge(
  p_purpose  text,
  p_request  uuid,
  p_user     uuid,
  p_phone    text,
  p_approval timestamptz,
  p_intro    text,
  p_ip       text
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_last  timestamptz;
  v_n     integer;
  v_id    uuid := gen_random_uuid();
  v_code  text;
  v_net   bigint;
begin
  select max(c.created_at) into v_last
    from wa_challenges c where c.purpose = p_purpose and c.phone = p_phone;
  if v_last is not null and v_last > now() - interval '60 seconds' then
    return jsonb_build_object(
      'ok', false, 'code', 'too_soon',
      'wait', ceil(extract(epoch from (v_last + interval '60 seconds' - now())))::int);
  end if;
  select count(*) into v_n from wa_challenges c
   where c.phone = p_phone and c.created_at > now() - interval '1 hour';
  if v_n >= 5 then
    return jsonb_build_object('ok', false, 'code', 'too_many_sends');
  end if;
  if not _rate_ok('wa_ip', p_ip, 40, interval '1 hour') then
    return jsonb_build_object('ok', false, 'code', 'too_many_sends');
  end if;
  if not _rate_ok('wa_global', 'all', 300, interval '1 hour') then
    return jsonb_build_object('ok', false, 'code', 'busy');
  end if;

  -- the new code replaces the old one
  update wa_challenges
     set revoked_at = now()
   where purpose = p_purpose and phone = p_phone
     and consumed_at is null and revoked_at is null;

  v_code := _new_code6();
  insert into wa_challenges (id, purpose, request_id, user_id, phone, approval_at,
                             code_mac, expires_at)
  values (v_id, p_purpose, p_request, p_user, p_phone, p_approval,
          _code_mac(v_code, v_id), now() + interval '5 minutes');

  v_net := _wa_send(
    p_phone,
    p_intro || 'رمز التحقق لتطبيق إشاري: ' || v_code ||
    E'\nصالح لمدة 5 دقائق ويُستخدم مرة واحدة. لا تشاركه مع أي شخص.'
  );
  update wa_challenges
     set net_request_id = v_net,
         send_status = case when v_net is null then 'failed' else 'queued' end,
         send_error  = case when v_net is null then 'not_queued' else null end
   where id = v_id;

  return jsonb_build_object('ok', true, 'wait', 60, 'queued', v_net is not null);
end;
$$;

revoke all on function _issue_challenge(text, uuid, uuid, text, timestamptz, text, text) from public, anon, authenticated;

create or replace function trial_submit(
  p_manager text,
  p_business text,
  p_phone   text,
  p_consent boolean
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_manager  text := regexp_replace(btrim(coalesce(p_manager, '')), '\s+', ' ', 'g');
  v_business text := regexp_replace(btrim(coalesce(p_business, '')), '\s+', ' ', 'g');
  v_phone    text := _e164_clean(p_phone);
  v_ip       text := _ip_hash(null);
  v_token    text;
  v_id       uuid;
begin
  if length(v_manager) < 2 or length(v_manager) > 80
     or length(v_business) < 2 or length(v_business) > 120 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name');
  end if;
  if not _e164_ok(v_phone) then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if p_consent is not true then
    return jsonb_build_object('ok', false, 'code', 'consent_required');
  end if;
  if not _rate_ok('submit_ip', v_ip, 20, interval '1 hour')
     or not _rate_ok('submit_phone', v_phone, 3, interval '1 day') then
    return jsonb_build_object('ok', false, 'code', 'too_many_requests');
  end if;
  if exists (select 1 from trial_history h where h.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'trial_used');
  end if;
  if exists (select 1 from subscriber_accounts a where a.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'account_exists');
  end if;
  if exists (select 1 from trial_requests r
              where r.phone = v_phone
                and r.status in ('pending_review', 'needs_info', 'approved')) then
    return jsonb_build_object('ok', false, 'code', 'request_exists');
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  begin
    insert into trial_requests (follow_hash, manager_name, business_name, phone,
                                requested_at, consent_at, ip_hash)
    values (encode(digest(v_token, 'sha256'), 'hex'), v_manager, v_business, v_phone,
            _server_now(), _server_now(), v_ip)
    returning id into v_id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'request_exists');
  end;

  perform _audit('trial_requested', 'trial_request', v_id::text, null,
                 jsonb_build_object('manager', v_manager, 'business', v_business,
                                    'phone', v_phone, 'phone_verified', false),
                 null, v_ip);
  perform _alert('trial_request', v_id::text,
                 'طلب تجربة جديد: ' || v_business || ' (' || v_manager || ')');
  return jsonb_build_object('ok', true, 'followToken', v_token, 'status', 'pending_review');
end;
$$;

revoke all on function trial_submit(text, text, text, boolean) from public;
grant execute on function trial_submit(text, text, text, boolean) to anon, authenticated;

create or replace function login_request(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := _e164_clean(p_phone);
  a       subscriber_accounts;
  v_ip    text := _ip_hash(null);
begin
  if not _e164_ok(v_phone) then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  select * into a from subscriber_accounts s where s.phone = v_phone;
  if not found then
    -- The answer for a number we do not know looks exactly like the answer for
    -- a subscriber (same wait, same limits), so the screen cannot be used to
    -- find out who is registered. Nothing is sent.
    if not _rate_ok('login_unknown_ip', v_ip, 40, interval '1 hour') then
      return jsonb_build_object('ok', false, 'code', 'too_many_sends');
    end if;
    if not _rate_ok('login_unknown_60', v_phone, 1, interval '60 seconds') then
      return jsonb_build_object('ok', false, 'code', 'too_soon', 'wait', 60);
    end if;
    if not _rate_ok('login_unknown_1h', v_phone, 5, interval '1 hour') then
      return jsonb_build_object('ok', false, 'code', 'too_many_sends');
    end if;
    return jsonb_build_object('ok', true, 'wait', 60, 'queued', true);
  end if;
  return _issue_challenge('login', null, a.user_id, v_phone, null, '', v_ip);
end;
$$;

revoke all on function login_request(text) from public;
grant execute on function login_request(text) to anon, authenticated;

create or replace function login_verify(p_phone text, p_code text, p_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text := _e164_clean(p_phone);
  a       subscriber_accounts;
  chk     jsonb;
  v_ip    text := _ip_hash(p_ip);
begin
  select * into a from subscriber_accounts s where s.phone = v_phone for update;
  if not found then
    -- Same behaviour as a wrong code for a subscriber: five tries, then the
    -- code is "dead". No code was ever sent, so nothing can match.
    declare
      v_n integer := _rate_count('verify_unknown', v_phone, interval '1 hour');
    begin
      if v_n >= 5 then
        return jsonb_build_object('ok', false, 'code', 'code_expired');
      end if;
      perform _rate_add('verify_unknown', v_phone);
      if v_n + 1 >= 5 then
        return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
      end if;
      return jsonb_build_object('ok', false, 'code', 'invalid_code', 'left', 5 - (v_n + 1));
    end;
  end if;
  if not _rate_ok('login_ip', v_ip, 30, interval '1 hour') then
    return jsonb_build_object('ok', false, 'code', 'too_many_requests');
  end if;
  chk := _check_challenge('login', v_phone, p_code, 'login:' || v_phone, null);
  if (chk ->> 'ok')::boolean is not true then
    return chk;
  end if;
  update wa_challenges set consumed_at = now() where id = (chk ->> 'challengeId')::uuid;
  perform _audit('login', 'account', a.user_id::text, null, null, null, v_ip);
  return jsonb_build_object('ok', true, 'userId', a.user_id,
                            'email', a.auth_email);
end;
$$;

revoke all on function login_verify(text, text, text) from public, anon, authenticated;
grant execute on function login_verify(text, text, text) to service_role;

commit;
