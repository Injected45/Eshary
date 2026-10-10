-- 0059_trial_onboarding.sql
-- Trial requests, administrator decisions, WhatsApp verification and the
-- SubscriptionGuard (server time only).
--
-- What this replaces: new subscribers no longer register by e-mail, nor by an
-- invitation QR. They ask for a trial ("ابدأ تجربتك"); the administrator
-- decides (3 days / 1 week / more information / reject); a WhatsApp code
-- proves the phone and starts the trial the first time it is entered. The old
-- self-service doors (0034–0058) are closed here (execute revoked); the
-- administrator-side objects stay but are unused.
--
-- Three separate states, never mixed:
--   * the REQUEST      trial_requests.status   pending_review / needs_info /
--                                              approved / rejected / activated
--   * the SUBSCRIPTION account_licenses.status pending / trial / active /
--                                              expired / blocked (= suspended)
--   * the MESSAGE      wa_challenges.send_status queued / sent / failed
--   A failed WhatsApp message never cancels an approval or activates anything.
--
-- SubscriptionGuard (all of it in the database):
--   * the only clock is the database's (_server_now); nothing the app sends is
--     ever used as a time. Dates are timestamptz (UTC); the app shows them in
--     Africa/Tripoli.
--   * _server_now() never goes backwards: it is the greater of now() and the
--     highest time ever seen (time_guard), so a clock set back cannot reopen an
--     expired trial. A clock found behind that mark by more than 2 minutes is an
--     anomaly: activation and every subscription-gated operation pause, the
--     administrator is alerted, and nothing is extended automatically.
--   * valid  <=>  _server_now() < trial_ends_at   (equal = already over)
--   * after expiry the data stays and can be READ (and exported) but nothing
--     can be added or changed; the gate is on the server, so calling the API
--     directly changes nothing.
--
-- External requirement: Auth setting "Allow new users to sign up" should be OFF
-- (accounts are created only by the member-session Edge Function). See
-- docs/trial-onboarding.md.

begin;

-- =========================================================================
-- 1) The clock
-- =========================================================================
create table if not exists time_guard (
  id              integer primary key default 1 check (id = 1),
  max_seen_at     timestamptz not null default now(),
  anomaly_since   timestamptz,
  anomaly_alerted boolean not null default false
);
insert into time_guard (id) values (1) on conflict do nothing;
alter table time_guard enable row level security;
revoke all on time_guard from anon, authenticated;

-- Never earlier than the latest moment the database has seen.
create or replace function _server_now()
returns timestamptz
language sql
stable
security definer
set search_path = public, extensions
as $$
  select greatest(now(), (select g.max_seen_at from time_guard g where g.id = 1))
$$;
revoke all on function _server_now() from public, anon, authenticated;

-- True while the clock is not behind the highest time seen (2 minutes of slack).
create or replace function _time_trusted()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select now() >= (select g.max_seen_at from time_guard g where g.id = 1) - interval '2 minutes'
$$;
revoke all on function _time_trusted() from public, anon, authenticated;

-- =========================================================================
-- 2) Audit log (append-only) and alerts for the administrators
-- =========================================================================
create table if not exists audit_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  actor       uuid,
  actor_email text,
  kind        text not null,
  subject_type text,
  subject_id  text,
  old_value   jsonb,
  new_value   jsonb,
  note        text,
  ip_hash     text
);
create index if not exists audit_log_recent_idx on audit_log (at desc);
create index if not exists audit_log_subject_idx on audit_log (subject_type, subject_id, at desc);
alter table audit_log enable row level security;
revoke all on audit_log from anon, authenticated;

create or replace function _audit_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_immutable' using errcode = 'P0001';
end;
$$;
drop trigger if exists trg_audit_no_change on audit_log;
create trigger trg_audit_no_change
  before update or delete on audit_log
  for each row execute function _audit_immutable();
drop trigger if exists trg_audit_no_truncate on audit_log;
create trigger trg_audit_no_truncate
  before truncate on audit_log
  for each statement execute function _audit_immutable();

create or replace function _audit(
  p_kind text, p_subject_type text, p_subject_id text,
  p_old jsonb default null, p_new jsonb default null,
  p_note text default null, p_ip text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into audit_log (at, actor, actor_email, kind, subject_type, subject_id,
                         old_value, new_value, note, ip_hash)
  values (
    _server_now(), auth.uid(),
    (select u.email from auth.users u where u.id = auth.uid()),
    p_kind, p_subject_type, p_subject_id, p_old, p_new, p_note, p_ip
  );
end;
$$;
revoke all on function _audit(text, text, text, jsonb, jsonb, text, text) from public, anon, authenticated;

create table if not exists platform_alerts (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null,
  ref_id     text,
  body       text not null,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists platform_alerts_recent_idx on platform_alerts (created_at desc);
alter table platform_alerts enable row level security;
revoke all on platform_alerts from anon, authenticated;

create or replace function _alert(p_kind text, p_ref text, p_body text)
returns void
language sql
security definer
set search_path = public, extensions
as $$
  insert into platform_alerts (kind, ref_id, body) values (p_kind, p_ref, p_body)
$$;
revoke all on function _alert(text, text, text) from public, anon, authenticated;

-- =========================================================================
-- 3) The subscription record (account_licenses) and its validity rule
-- =========================================================================
alter table account_licenses
  add column if not exists trial_hours      integer,
  add column if not exists paid_approved_at timestamptz,
  add column if not exists paid_reference   text,
  add column if not exists paid_until       timestamptz,
  add column if not exists suspended_at     timestamptz,
  add column if not exists suspended_reason text;

alter table account_licenses drop constraint if exists account_licenses_license_type_check;
alter table account_licenses add constraint account_licenses_license_type_check
  check (license_type is null or license_type in ('trial', 'lifetime', 'paid'));

-- Valid = may operate. Platform administrators do not depend on the clock.
create or replace function _license_valid(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
      from account_licenses l
     where l.user_id = p_user
       and (
         (coalesce(l.is_admin, false) and l.status = 'active')
         or (
           _time_trusted()
           and (
             (l.status = 'active' and (l.paid_until is null or l.paid_until > _server_now()))
             or (l.status = 'trial' and l.trial_ends_at is not null
                 and l.trial_ends_at > _server_now())
           )
         )
       )
  )
$$;
revoke all on function _license_valid(uuid) from public, anon, authenticated;

-- Over (or paused by the clock) but not blocked / pending: the data can still be read.
create or replace function _license_readonly(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
      from account_licenses l
     where l.user_id = p_user
       and not coalesce(l.is_admin, false)
       and l.status in ('trial', 'active', 'expired')
  ) and not _license_valid(p_user)
$$;
revoke all on function _license_readonly(uuid) from public, anon, authenticated;

-- Same name and signature as 0036: every policy and function that uses it now
-- follows the server clock.
create or replace function effective_admin_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _raw_admin_id();
begin
  if v_admin is null then
    return null;
  end if;
  if _license_valid(v_admin) then
    return v_admin;
  end if;
  return null;
end;
$$;

create or replace function _readonly_admin_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := _raw_admin_id();
begin
  if v_admin is not null and _license_readonly(v_admin) then
    return v_admin;
  end if;
  return null;
end;
$$;
revoke all on function _readonly_admin_id() from public, anon;
grant execute on function _readonly_admin_id() to authenticated;

-- 0039's helper (used by triggers on employees / QR / codes).
create or replace function _admin_license_valid(p_admin uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$ select _license_valid(p_admin) $$;

create or replace function current_license_status()
returns table (
  status         text,
  license_type   text,
  trial_ends_at  timestamptz,
  is_valid       boolean,
  is_admin       boolean
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authorized: no auth.uid()';
  end if;
  return query
  select l.status,
         l.license_type,
         l.trial_ends_at,
         _license_valid(v_uid),
         coalesce(l.is_admin, false)
    from account_licenses l
   where l.user_id = v_uid;
end;
$$;
grant execute on function current_license_status() to authenticated;

-- A status of "expired" for what the clock already ended (information only:
-- validity never depends on this flag).
create or replace function expire_overdue_trials()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_count integer;
begin
  with updated as (
    update account_licenses
       set status = 'expired'
     where not coalesce(is_admin, false)
       and (
         (status = 'trial' and trial_ends_at is not null and trial_ends_at <= _server_now())
         or (status = 'active' and paid_until is not null and paid_until <= _server_now())
       )
    returning 1
  )
  select count(*) into v_count from updated;
  return v_count;
end;
$$;

-- Reading stays possible after expiry: the gate on SELECT accepts "valid" OR
-- "read-only"; inserts / updates / deletes still need a valid subscription.
do $$
declare
  t text;
begin
  foreach t in array array[
    'companies', 'exchanges', 'clients', 'transfers', 'currency_buys',
    'beneficiaries', 'exchange_companies', 'countries'
  ] loop
    execute format('drop policy if exists license_gate on public.%I', t);
    execute format('drop policy if exists license_gate_read on public.%I', t);
    execute format('drop policy if exists license_gate_ins on public.%I', t);
    execute format('drop policy if exists license_gate_upd on public.%I', t);
    execute format('drop policy if exists license_gate_del on public.%I', t);
    execute format(
      'create policy license_gate_read on public.%I as restrictive for select to authenticated using ((select license_ok()) or (select _readonly_admin_id()) is not null)', t);
    execute format(
      'create policy license_gate_ins on public.%I as restrictive for insert to authenticated with check ((select license_ok()))', t);
    execute format(
      'create policy license_gate_upd on public.%I as restrictive for update to authenticated using ((select license_ok())) with check ((select license_ok()))', t);
    execute format(
      'create policy license_gate_del on public.%I as restrictive for delete to authenticated using ((select license_ok()))', t);
  end loop;
end;
$$;

-- The permissive side of the read-only window.
drop policy if exists companies_select_readonly on companies;
create policy companies_select_readonly on companies
  for select to authenticated using (owner_id = (select _readonly_admin_id()));
drop policy if exists exchanges_select_readonly on exchanges;
create policy exchanges_select_readonly on exchanges
  for select to authenticated using (
    exists (select 1 from companies c
             where c.id = exchanges.company_id
               and c.owner_id = (select _readonly_admin_id()))
  );
drop policy if exists clients_select_readonly on clients;
create policy clients_select_readonly on clients
  for select to authenticated using (owner_id = (select _readonly_admin_id()));
drop policy if exists transfers_select_readonly on transfers;
create policy transfers_select_readonly on transfers
  for select to authenticated using (owner_id = (select _readonly_admin_id()));
drop policy if exists currency_buys_select_readonly on currency_buys;
create policy currency_buys_select_readonly on currency_buys
  for select to authenticated using (owner_id = (select _readonly_admin_id()));
drop policy if exists beneficiaries_select_readonly on beneficiaries;
create policy beneficiaries_select_readonly on beneficiaries
  for select to authenticated using (owner_id = (select _readonly_admin_id()));
drop policy if exists ec_select_readonly on exchange_companies;
create policy ec_select_readonly on exchange_companies
  for select to authenticated using (owner_id = (select _readonly_admin_id()));
drop policy if exists countries_select_readonly on countries;
create policy countries_select_readonly on countries
  for select to authenticated using (owner_id = (select _readonly_admin_id()));

-- =========================================================================
-- 4) Clock monitor (run every minute) and rate limits
-- =========================================================================
create or replace function time_guard_tick()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now timestamptz := clock_timestamp();
  g     time_guard;
begin
  select * into g from time_guard where id = 1 for update;
  if v_now >= g.max_seen_at then
    update time_guard
       set max_seen_at = v_now, anomaly_since = null, anomaly_alerted = false
     where id = 1;
  elsif v_now < g.max_seen_at - interval '2 minutes' then
    update time_guard
       set anomaly_since = coalesce(anomaly_since, v_now)
     where id = 1;
    if not g.anomaly_alerted then
      update time_guard set anomaly_alerted = true where id = 1;
      perform _audit(
        'time_anomaly', 'clock', '1',
        jsonb_build_object('max_seen_at', g.max_seen_at),
        jsonb_build_object('now', v_now),
        'the clock is behind the highest time seen'
      );
      perform _alert(
        'time_anomaly', '1',
        'تراجعت ساعة الخادم عن آخر وقت مسجَّل. أُوقف التفعيل والعمليات المرتبطة بالاشتراك مؤقتاً.'
      );
    end if;
  end if;
end;
$$;
revoke all on function time_guard_tick() from public, anon, authenticated;

create table if not exists rate_events (
  id   bigserial primary key,
  kind text not null,
  key  text not null,
  at   timestamptz not null default now()
);
create index if not exists rate_events_lookup_idx on rate_events (kind, key, at desc);
alter table rate_events enable row level security;
revoke all on rate_events from anon, authenticated;

create or replace function _rate_count(p_kind text, p_key text, p_window interval)
returns integer
language sql
stable
security definer
set search_path = public, extensions
as $$
  select count(*)::int from rate_events
   where kind = p_kind and key = p_key and at > now() - p_window
$$;
revoke all on function _rate_count(text, text, interval) from public, anon, authenticated;

create or replace function _rate_add(p_kind text, p_key text)
returns void
language sql
security definer
set search_path = public, extensions
as $$ insert into rate_events (kind, key) values (p_kind, p_key) $$;
revoke all on function _rate_add(text, text) from public, anon, authenticated;

-- Counts a hit and says whether it is within the limit.
create or replace function _rate_ok(p_kind text, p_key text, p_limit integer, p_window interval)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if _rate_count(p_kind, p_key, p_window) >= p_limit then
    return false;
  end if;
  perform _rate_add(p_kind, p_key);
  return true;
end;
$$;
revoke all on function _rate_ok(text, text, integer, interval) from public, anon, authenticated;

-- =========================================================================
-- 5) Secrets, phone and network helpers
-- =========================================================================
-- The server-side secret that makes stored codes unusable without it.
insert into app_secrets (key, value)
select 'otp_pepper', encode(gen_random_bytes(32), 'hex')
 where not exists (select 1 from app_secrets where key = 'otp_pepper');

create or replace function _pepper()
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$ select value from app_secrets where key = 'otp_pepper' $$;
revoke all on function _pepper() from public, anon, authenticated;

-- E.164 with a leading +. Libya (+218) must be a mobile number: +2189XXXXXXXX.
create or replace function _e164_ok(p text)
returns boolean
language sql
immutable
as $$
  select p ~ '^\+[1-9][0-9]{7,14}$'
     and (p not like '+218%' or p ~ '^\+2189[0-9]{8}$')
$$;

create or replace function _e164_clean(p text)
returns text
language sql
immutable
as $$ select regexp_replace(btrim(coalesce(p, '')), '[\s\-()]', '', 'g') $$;

create or replace function _wa_chat_e164(p text)
returns text
language sql
immutable
as $$ select regexp_replace(p, '\D', '', 'g') || '@c.us' $$;

create or replace function _mask_e164(p text)
returns text
language sql
immutable
as $$ select left(p, 4) || '*****' || right(p, 3) $$;

-- The internal sign-in address of a subscriber (never shown or typed).
create or replace function _subscriber_email(p text)
returns text
language sql
immutable
as $$ select 't' || regexp_replace(p, '\D', '', 'g') || '@subscribers.eshary.invalid' $$;

-- A hash of the caller's network address (never the address itself). PostgREST
-- exposes the headers; the Edge Function passes the address it saw.
create or replace function _ip_hash(p_ip text default null)
returns text
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_headers json;
  v_ip      text := nullif(btrim(coalesce(p_ip, '')), '');
begin
  if v_ip is null then
    begin
      v_headers := nullif(current_setting('request.headers', true), '')::json;
      v_ip := nullif(btrim(split_part(
        coalesce(v_headers ->> 'cf-connecting-ip', v_headers ->> 'x-forwarded-for', ''), ',', 1)), '');
    exception when others then
      v_ip := null;
    end;
  end if;
  return encode(hmac(coalesce(v_ip, 'unknown'), _pepper(), 'sha256'), 'hex');
end;
$$;
revoke all on function _ip_hash(text) from public, anon, authenticated;

-- =========================================================================
-- 6) Tables of the flow
-- =========================================================================
create table if not exists trial_requests (
  id                uuid primary key default gen_random_uuid(),
  follow_hash       text not null unique,
  manager_name      text not null check (length(btrim(manager_name)) between 2 and 80),
  business_name     text not null check (length(btrim(business_name)) between 2 and 120),
  phone             text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  status            text not null default 'pending_review'
                    check (status in ('pending_review', 'needs_info', 'approved', 'rejected', 'activated')),
  review_note       text,
  requested_at      timestamptz not null default now(),
  consent_at        timestamptz not null,
  ip_hash           text,
  approved_at       timestamptz,
  approved_by       uuid,
  approval_expires_at timestamptz,
  trial_hours       integer check (trial_hours in (72, 168)),
  phone_verified_at timestamptz,
  activated_at      timestamptz,
  trial_ends_at     timestamptz,
  user_id           uuid references auth.users (id) on delete set null,
  updated_at        timestamptz not null default now()
);
-- One open request per phone (stops duplicates and spam).
create unique index if not exists trial_requests_open_phone_idx
  on trial_requests (phone) where status in ('pending_review', 'needs_info', 'approved');
create index if not exists trial_requests_recent_idx on trial_requests (requested_at desc);
alter table trial_requests enable row level security;
revoke all on trial_requests from anon, authenticated;

-- A phone that has had a trial never gets another automatically, even after the
-- account is deleted.
create table if not exists trial_history (
  phone              text primary key,
  first_activated_at timestamptz not null,
  request_id         uuid,
  user_id            uuid
);
alter table trial_history enable row level security;
revoke all on trial_history from anon, authenticated;

create table if not exists subscriber_accounts (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  request_id    uuid,
  phone         text not null unique check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  auth_email    text not null,
  manager_name  text not null,
  business_name text not null,
  created_at    timestamptz not null default now()
);
alter table subscriber_accounts enable row level security;
revoke all on subscriber_accounts from anon, authenticated;

create table if not exists wa_challenges (
  id            uuid primary key default gen_random_uuid(),
  purpose       text not null check (purpose in ('activation', 'login', 'phone_change')),
  request_id    uuid references trial_requests (id) on delete cascade,
  user_id       uuid,
  phone         text not null,
  approval_at   timestamptz,
  code_mac      text not null,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null,
  attempts      integer not null default 0,
  consumed_at   timestamptz,
  revoked_at    timestamptz,
  send_status   text not null default 'queued'
                check (send_status in ('queued', 'sent', 'failed')),
  send_error    text,
  net_request_id bigint
);
create index if not exists wa_challenges_phone_idx on wa_challenges (purpose, phone, created_at desc);
alter table wa_challenges enable row level security;
revoke all on wa_challenges from anon, authenticated;

-- A previous run may have created these tables in an older shape: bring them
-- up to date (all of this is a no-op on a fresh database).
alter table subscriber_accounts add column if not exists auth_email text;
update subscriber_accounts
   set auth_email = 't' || regexp_replace(phone, '\D', '', 'g') || '@subscribers.eshary.invalid'
 where auth_email is null;
alter table subscriber_accounts alter column auth_email set not null;
alter table wa_challenges drop constraint if exists wa_challenges_purpose_check;
alter table wa_challenges add constraint wa_challenges_purpose_check
  check (purpose in ('activation', 'login', 'phone_change'));

-- =========================================================================
-- 7) WhatsApp: send, status, challenges
-- =========================================================================
-- Sends through the gateway (pg_net, asynchronous). Returns the request id or
-- null when it could not even be queued. Never throws.
create or replace function _wa_send(p_phone text, p_text text)
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_base text := _secret('wa_base_url');
  v_sess text := _secret('wa_session_id');
  v_key  text := _secret('wa_api_key');
  v_id   bigint;
begin
  if v_base is null or v_sess is null or v_key is null then
    return null;
  end if;
  begin
    select net.http_post(
      url     := v_base || '/api/sessions/' || v_sess || '/messages/send-text',
      headers := jsonb_build_object('X-API-Key', v_key, 'Content-Type', 'application/json'),
      body    := jsonb_build_object('chatId', _wa_chat_e164(p_phone), 'text', p_text)
    ) into v_id;
  exception when others then
    return null;
  end;
  return v_id;
end;
$$;
revoke all on function _wa_send(text, text) from public, anon, authenticated;

-- Reads the gateway's answers back: 2xx = sent, anything else = failed. A
-- delivered message is NOT a verified phone: only entering the code verifies.
create or replace function wa_sync_status()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_n integer := 0;
  r   record;
begin
  for r in
    select c.id, c.net_request_id, c.created_at
      from wa_challenges c
     where c.send_status = 'queued'
  loop
    if r.net_request_id is null then
      update wa_challenges set send_status = 'failed', send_error = 'not_queued' where id = r.id;
      v_n := v_n + 1;
      continue;
    end if;
    declare
      v_code integer;
      v_err  text;
      v_seen boolean;
    begin
      select true, x.status_code, x.error_msg into v_seen, v_code, v_err
        from net._http_response x where x.id = r.net_request_id;
      if v_seen is not null then
        if v_code between 200 and 299 then
          update wa_challenges set send_status = 'sent' where id = r.id;
        else
          update wa_challenges
             set send_status = 'failed',
                 send_error  = coalesce('http_' || v_code::text, left(v_err, 60), 'error')
           where id = r.id;
        end if;
        v_n := v_n + 1;
      elsif r.created_at < now() - interval '2 minutes' then
        update wa_challenges set send_status = 'failed', send_error = 'no_answer' where id = r.id;
        v_n := v_n + 1;
      end if;
    exception when others then
      null;
    end;
  end loop;
  return v_n;
end;
$$;
revoke all on function wa_sync_status() from public, anon, authenticated;

create or replace function _new_code6()
returns text
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
  ) % 1000000)::text, 6, '0');
end;
$$;
revoke all on function _new_code6() from public, anon, authenticated;

create or replace function _code_mac(p_code text, p_id uuid)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$ select encode(hmac(p_code || ':' || p_id::text, _pepper(), 'sha256'), 'hex') $$;
revoke all on function _code_mac(text, uuid) from public, anon, authenticated;

-- Issues a code: waits 60 s between sends, at most 5 sends per phone per hour
-- and 10 per network address per hour, revokes the previous code, stores only
-- the keyed hash, sends it. p_intro is put before the code in the message.
-- Returns {ok, wait} or {ok:false, code, wait?}. The send's outcome is read
-- later (wa_sync_status); a failure here is reported but changes no state.
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
  if not _rate_ok('wa_ip', p_ip, 10, interval '1 hour') then
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

-- Checks a typed code against the live challenge. At most 5 wrong tries per
-- code; 15 wrong tries per key per hour whatever the number of codes (a resend
-- never resets that). Wrong answers are counted and returned, not raised, so
-- the count is kept. The caller consumes the code when everything else passes.
create or replace function _check_challenge(
  p_purpose   text,
  p_phone     text,
  p_code      text,
  p_lock_key  text,
  p_approval  timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c      wa_challenges;
  v_code text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
begin
  if _rate_count('verify_fail', p_lock_key, interval '1 hour') >= 15 then
    return jsonb_build_object('ok', false, 'code', 'locked');
  end if;

  select * into c
    from wa_challenges w
   where w.purpose = p_purpose and w.phone = p_phone
     and w.consumed_at is null and w.revoked_at is null
     and w.expires_at > now()
   order by w.created_at desc
   limit 1
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'code_expired');
  end if;
  -- tied to the approval it was issued for
  if p_approval is not null and c.approval_at is distinct from p_approval then
    update wa_challenges set revoked_at = now() where id = c.id;
    return jsonb_build_object('ok', false, 'code', 'code_expired');
  end if;
  if c.attempts >= 5 then
    update wa_challenges set revoked_at = now() where id = c.id;
    return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
  end if;

  if _code_mac(v_code, c.id) <> c.code_mac then
    update wa_challenges
       set attempts = c.attempts + 1,
           revoked_at = case when c.attempts + 1 >= 5 then now() else null end
     where id = c.id;
    perform _rate_add('verify_fail', p_lock_key);
    if c.attempts + 1 >= 5 then
      return jsonb_build_object('ok', false, 'code', 'too_many_attempts');
    end if;
    return jsonb_build_object(
      'ok', false, 'code', 'invalid_code', 'left', 5 - (c.attempts + 1));
  end if;

  return jsonb_build_object('ok', true, 'challengeId', c.id);
end;
$$;
revoke all on function _check_challenge(text, text, text, text, timestamptz) from public, anon, authenticated;

-- =========================================================================
-- 8) The applicant (no account yet; a random follow token is the only key)
-- =========================================================================
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
  if not _rate_ok('submit_ip', v_ip, 5, interval '1 hour')
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

-- What the applicant sees about their own request. Only the secret token opens
-- it: typing a phone number reveals nothing.
create or replace function trial_follow(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r      trial_requests;
  v_now  timestamptz := _server_now();
  v_ip   text := _ip_hash(null);
  v_msg  wa_challenges;
  v_wait integer := 0;
  v_status text;
begin
  if not _rate_ok('follow_ip', v_ip, 900, interval '1 hour') then
    return jsonb_build_object('ok', false, 'code', 'too_many_requests');
  end if;
  select * into r from trial_requests
   where follow_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;

  perform wa_sync_status();
  select * into v_msg from wa_challenges c
   where c.request_id = r.id and c.purpose = 'activation'
   order by c.created_at desc limit 1;
  if v_msg.id is not null and v_msg.created_at > now() - interval '60 seconds' then
    v_wait := ceil(extract(epoch from (v_msg.created_at + interval '60 seconds' - now())))::int;
  end if;

  v_status := r.status;
  if r.status = 'approved' and r.approval_expires_at <= v_now then
    v_status := 'approval_expired';
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', v_status,
    'managerName', r.manager_name,
    'businessName', r.business_name,
    'phone', _mask_e164(r.phone),
    'requestedAt', r.requested_at,
    'approvedAt', r.approved_at,
    'approvalExpiresAt', r.approval_expires_at,
    'trialHours', r.trial_hours,
    'phoneVerified', r.phone_verified_at is not null,
    'reviewNote', case when r.status in ('needs_info', 'rejected') then r.review_note end,
    'messageStatus', v_msg.send_status,
    'codeExpiresAt', case when v_msg.id is not null and v_msg.consumed_at is null
                           and v_msg.revoked_at is null then v_msg.expires_at end,
    'resendWait', v_wait,
    'canRequestCode', v_status = 'approved',
    'serverNow', v_now
  );
end;
$$;
revoke all on function trial_follow(text) from public;
grant execute on function trial_follow(text) to anon, authenticated;

-- Correct a wrong number before the decision; the change is recorded.
create or replace function trial_update_phone(p_token text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r       trial_requests;
  v_phone text := _e164_clean(p_phone);
  v_ip    text := _ip_hash(null);
begin
  select * into r from trial_requests
   where follow_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  if r.status not in ('pending_review', 'needs_info') then
    return jsonb_build_object('ok', false, 'code', 'not_editable');
  end if;
  if not _e164_ok(v_phone) then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if not _rate_ok('phone_edit', r.id::text, 3, interval '1 day') then
    return jsonb_build_object('ok', false, 'code', 'too_many_requests');
  end if;
  if v_phone = r.phone then
    return jsonb_build_object('ok', true);
  end if;
  if exists (select 1 from trial_history h where h.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'trial_used');
  end if;
  if exists (select 1 from subscriber_accounts a where a.phone = v_phone) then
    return jsonb_build_object('ok', false, 'code', 'account_exists');
  end if;
  begin
    update trial_requests set phone = v_phone, phone_verified_at = null, updated_at = _server_now()
     where id = r.id;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'request_exists');
  end;
  update wa_challenges set revoked_at = now()
   where request_id = r.id and consumed_at is null and revoked_at is null;
  perform _audit('trial_phone_changed', 'trial_request', r.id::text,
                 jsonb_build_object('phone', r.phone), jsonb_build_object('phone', v_phone),
                 'by the applicant, before the decision', v_ip);
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function trial_update_phone(text, text) from public;
grant execute on function trial_update_phone(text, text) to anon, authenticated;

-- A new code for an approved request, without a new approval, while the
-- approval stands (7 days).
create or replace function trial_request_code(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r     trial_requests;
  v_ip  text := _ip_hash(null);
begin
  select * into r from trial_requests
   where follow_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  if r.status <> 'approved' then
    return jsonb_build_object('ok', false, 'code',
      case when r.status = 'activated' then 'already_activated' else 'not_approved' end);
  end if;
  if r.approval_expires_at <= _server_now() then
    return jsonb_build_object('ok', false, 'code', 'approval_expired');
  end if;
  if not _time_trusted() then
    return jsonb_build_object('ok', false, 'code', 'time_untrusted');
  end if;
  return _issue_challenge('activation', r.id, null, r.phone, r.approved_at, '', v_ip);
end;
$$;
revoke all on function trial_request_code(text) from public;
grant execute on function trial_request_code(text) to anon, authenticated;

-- Sign-in of an existing subscriber on a new device: phone + WhatsApp code.
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
    return jsonb_build_object('ok', false, 'code', 'phone_not_found');
  end if;
  return _issue_challenge('login', null, a.user_id, v_phone, null, '', v_ip);
end;
$$;
revoke all on function login_request(text) from public;
grant execute on function login_request(text) to anon, authenticated;

-- =========================================================================
-- 9) The Edge Function (service role): activation and sign-in
-- =========================================================================
-- Who the follow token belongs to, if the request can be activated.
create or replace function trial_prepare(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r trial_requests;
begin
  select * into r from trial_requests
   where follow_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex');
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  if r.status = 'activated' then
    return jsonb_build_object('ok', false, 'code', 'already_activated');
  end if;
  if r.status <> 'approved' then
    return jsonb_build_object('ok', false, 'code', 'not_approved');
  end if;
  if r.approval_expires_at <= _server_now() then
    return jsonb_build_object('ok', false, 'code', 'approval_expired');
  end if;
  return jsonb_build_object(
    'ok', true, 'requestId', r.id, 'phone', r.phone,
    'email', _subscriber_email(r.phone),
    'manager', r.manager_name, 'business', r.business_name);
end;
$$;
revoke all on function trial_prepare(text) from public, anon, authenticated;
grant execute on function trial_prepare(text) to service_role;

-- The activation, in ONE transaction: the code, the approval still standing,
-- the start (fixed only now, the first time), the end (start + 72 / 168 h),
-- the code consumed, the request and the subscription updated. The row is
-- locked, so two simultaneous calls cannot both activate or restart the clock.
create or replace function trial_activate(
  p_token text,
  p_code  text,
  p_user  uuid,
  p_ip    text default null,
  p_commit boolean default true
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r      trial_requests;
  chk    jsonb;
  v_now  timestamptz;
  v_end  timestamptz;
  v_ip   text := _ip_hash(p_ip);
begin
  select * into r from trial_requests
   where follow_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  if r.status = 'activated' then
    return jsonb_build_object('ok', false, 'code', 'already_activated');
  end if;
  if r.status <> 'approved' then
    return jsonb_build_object('ok', false, 'code', 'not_approved');
  end if;
  if r.approval_expires_at <= _server_now() then
    return jsonb_build_object('ok', false, 'code', 'approval_expired');
  end if;
  if not _time_trusted() then
    return jsonb_build_object('ok', false, 'code', 'time_untrusted');
  end if;
  if not _rate_ok('activate_ip', v_ip, 30, interval '1 hour') then
    return jsonb_build_object('ok', false, 'code', 'too_many_requests');
  end if;

  chk := _check_challenge('activation', r.phone, p_code, 'req:' || r.id::text, r.approved_at);
  if (chk ->> 'ok')::boolean is not true then
    perform _audit('activation_failed', 'trial_request', r.id::text, null,
                   jsonb_build_object('code', chk ->> 'code'), null, v_ip);
    return chk;
  end if;

  if exists (select 1 from trial_history h where h.phone = r.phone) then
    return jsonb_build_object('ok', false, 'code', 'trial_used');
  end if;

  -- first pass (p_commit = false): the code is right, nothing is consumed yet,
  -- so the Edge Function can create the account without leaving orphans behind
  if not p_commit then
    return jsonb_build_object('ok', true, 'checked', true);
  end if;

  v_now := _server_now();
  v_end := v_now + make_interval(hours => r.trial_hours);

  update wa_challenges set consumed_at = now() where id = (chk ->> 'challengeId')::uuid;
  insert into trial_history (phone, first_activated_at, request_id, user_id)
  values (r.phone, v_now, r.id, p_user);
  update trial_requests
     set status = 'activated', phone_verified_at = v_now, activated_at = v_now,
         trial_ends_at = v_end, user_id = p_user, updated_at = v_now
   where id = r.id;
  insert into subscriber_accounts (user_id, request_id, phone, auth_email, manager_name, business_name)
  values (p_user, r.id, r.phone, _subscriber_email(r.phone), r.manager_name, r.business_name);
  insert into account_licenses (user_id, status, license_type, trial_ends_at,
                                activated_at, activated_by, trial_hours)
  values (p_user, 'trial', 'trial', v_end, v_now, r.approved_by, r.trial_hours)
  on conflict (user_id) do update
    set status = 'trial', license_type = 'trial', trial_ends_at = v_end,
        activated_at = v_now, activated_by = r.approved_by, trial_hours = r.trial_hours;

  perform _audit('trial_activated', 'trial_request', r.id::text,
                 jsonb_build_object('status', 'approved'),
                 jsonb_build_object('status', 'activated', 'activated_at', v_now,
                                    'trial_ends_at', v_end, 'trial_hours', r.trial_hours),
                 null, v_ip);
  return jsonb_build_object('ok', true, 'trialEndsAt', v_end, 'userId', p_user);
end;
$$;
revoke all on function trial_activate(text, text, uuid, text, boolean) from public, anon, authenticated;
grant execute on function trial_activate(text, text, uuid, text, boolean) to service_role;

-- Sign-in check: the code only; it changes nothing about the subscription.
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
    return jsonb_build_object('ok', false, 'code', 'phone_not_found');
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

-- =========================================================================
-- 10) Administrator: requests and decisions
-- =========================================================================
create or replace function _admin_only()
returns void
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
end;
$$;
revoke all on function _admin_only() from public, anon, authenticated;

create or replace function admin_list_trial_requests()
returns table (
  id               uuid,
  manager_name     text,
  business_name    text,
  phone            text,
  status           text,
  bucket           text,
  review_note      text,
  requested_at     timestamptz,
  approved_at      timestamptz,
  approval_expires_at timestamptz,
  trial_hours      integer,
  phone_verified   boolean,
  activated_at     timestamptz,
  trial_ends_at    timestamptz,
  remaining_seconds bigint,
  user_id          uuid,
  subscription_status text,
  paid_until       timestamptz,
  message_status   text,
  message_error    text,
  repeat_hint      integer,
  server_now       timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform _admin_only();
  perform wa_sync_status();
  return query
  select r.id, r.manager_name, r.business_name, r.phone, r.status,
         case
           when r.status = 'pending_review' then 'pending_review'
           when r.status = 'needs_info' then 'needs_info'
           when r.status = 'rejected' then 'rejected_or_suspended'
           when r.status = 'approved' and m.send_status = 'failed' then 'message_failed'
           when r.status = 'approved' and r.approval_expires_at <= _server_now() then 'approval_expired'
           when r.status = 'approved' then 'approved_waiting'
           when l.status = 'blocked' then 'rejected_or_suspended'
           when l.status = 'active' and (l.paid_until is null or l.paid_until > _server_now()) then 'paid'
           when l.status = 'trial' and l.trial_ends_at > _server_now()
                and l.trial_ends_at <= _server_now() + interval '24 hours' then 'ending_soon'
           when l.status = 'trial' and l.trial_ends_at > _server_now() then 'active_trial'
           else 'expired_trial'
         end,
         r.review_note, r.requested_at, r.approved_at, r.approval_expires_at,
         r.trial_hours, r.phone_verified_at is not null, r.activated_at,
         coalesce(l.trial_ends_at, r.trial_ends_at),
         case when l.trial_ends_at is not null
              then greatest(0, floor(extract(epoch from (l.trial_ends_at - _server_now()))))::bigint end,
         r.user_id, l.status, l.paid_until,
         m.send_status, m.send_error,
         (select count(*)::int from trial_requests o
           where o.id <> r.id
             and (lower(o.business_name) = lower(r.business_name)
                  or (o.ip_hash is not null and o.ip_hash = r.ip_hash
                      and o.requested_at > _server_now() - interval '30 days'))),
         _server_now()
    from trial_requests r
    left join account_licenses l on l.user_id = r.user_id
    left join lateral (
      select c.send_status, c.send_error
        from wa_challenges c
       where c.request_id = r.id and c.purpose = 'activation'
       order by c.created_at desc limit 1
    ) m on true
   order by r.requested_at desc
   limit 500;
end;
$$;
revoke all on function admin_list_trial_requests() from public, anon;
grant execute on function admin_list_trial_requests() to authenticated;

-- Decisions: approve_72 | approve_168 | request_info | reject | withdraw |
-- renew_approval (an approval that ran out: same hours, fresh 7 days).
create or replace function admin_trial_decide(
  p_id       uuid,
  p_decision text,
  p_note     text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r      trial_requests;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_now  timestamptz := _server_now();
  v_hours integer;
  v_old  jsonb;
  v_send jsonb;
  v_intro text;
begin
  perform _admin_only();
  select * into r from trial_requests where id = p_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if r.status in ('activated', 'rejected') and p_decision <> 'withdraw' then
    raise exception 'request_closed' using errcode = 'P0001';
  end if;
  v_old := jsonb_build_object('status', r.status, 'trial_hours', r.trial_hours,
                              'approved_at', r.approved_at);

  if p_decision in ('approve_72', 'approve_168', 'renew_approval') then
    if r.status = 'approved' and p_decision <> 'renew_approval' then
      raise exception 'already_approved' using errcode = 'P0001';
    end if;
    if r.status not in ('pending_review', 'needs_info', 'approved') then
      raise exception 'request_closed' using errcode = 'P0001';
    end if;
    v_hours := case p_decision when 'approve_72' then 72 when 'approve_168' then 168
                               else coalesce(r.trial_hours, 72) end;
    if exists (select 1 from trial_history h where h.phone = r.phone) then
      raise exception 'trial_used' using errcode = 'P0001';
    end if;
    update trial_requests
       set status = 'approved', approved_at = v_now, approved_by = auth.uid(),
           approval_expires_at = v_now + interval '7 days', trial_hours = v_hours,
           review_note = v_note, updated_at = v_now
     where id = r.id;
    perform _audit('trial_' || p_decision, 'trial_request', r.id::text, v_old,
                   jsonb_build_object('status', 'approved', 'trial_hours', v_hours,
                                      'approved_at', v_now,
                                      'approval_expires_at', v_now + interval '7 days'),
                   v_note);
    -- The code goes out with the approval. If the message fails the approval
    -- stays; the applicant (or an administrator) asks for another.
    v_intro := 'تمت الموافقة على طلب تجربتك لتطبيق إشاري لمدة ' ||
               case v_hours when 72 then '3 أيام' else 'أسبوع' end ||
               E'. تبدأ التجربة عند إدخال الرمز لأول مرة.\n';
    v_send := _issue_challenge('activation', r.id, null, r.phone, v_now, v_intro, _ip_hash(null));
    return jsonb_build_object('ok', true, 'status', 'approved', 'trialHours', v_hours,
                              'message', v_send);

  elsif p_decision = 'request_info' then
    if v_note is null then
      raise exception 'note_required' using errcode = 'P0001';
    end if;
    update trial_requests set status = 'needs_info', review_note = v_note, updated_at = v_now
     where id = r.id;
  elsif p_decision = 'reject' then
    if v_note is null then
      raise exception 'note_required' using errcode = 'P0001';
    end if;
    update trial_requests set status = 'rejected', review_note = v_note, updated_at = v_now
     where id = r.id;
  elsif p_decision = 'withdraw' then
    if r.status <> 'approved' then
      raise exception 'not_approved' using errcode = 'P0001';
    end if;
    update trial_requests
       set status = 'pending_review', approved_at = null, approval_expires_at = null,
           review_note = v_note, updated_at = v_now
     where id = r.id;
  else
    raise exception 'invalid_decision' using errcode = 'P0001';
  end if;

  -- any code issued under the old state is dead
  update wa_challenges set revoked_at = now()
   where request_id = r.id and consumed_at is null and revoked_at is null;
  perform _audit('trial_' || p_decision, 'trial_request', r.id::text, v_old,
                 jsonb_build_object('status', (select status from trial_requests where id = r.id)),
                 v_note);
  return jsonb_build_object('ok', true,
                            'status', (select status from trial_requests where id = r.id));
end;
$$;
revoke all on function admin_trial_decide(uuid, text, text) from public, anon;
grant execute on function admin_trial_decide(uuid, text, text) to authenticated;

create or replace function admin_trial_fix_phone(p_id uuid, p_phone text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r       trial_requests;
  v_phone text := _e164_clean(p_phone);
begin
  perform _admin_only();
  select * into r from trial_requests where id = p_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if r.status in ('activated', 'rejected') then
    raise exception 'request_closed' using errcode = 'P0001';
  end if;
  if not _e164_ok(v_phone) then
    raise exception 'invalid_phone' using errcode = 'P0001';
  end if;
  if exists (select 1 from trial_history h where h.phone = v_phone) then
    raise exception 'trial_used' using errcode = 'P0001';
  end if;
  begin
    update trial_requests set phone = v_phone, phone_verified_at = null,
           updated_at = _server_now()
     where id = r.id;
  exception when unique_violation then
    raise exception 'request_exists' using errcode = 'P0001';
  end;
  update wa_challenges set revoked_at = now()
   where request_id = r.id and consumed_at is null and revoked_at is null;
  perform _audit('trial_phone_changed', 'trial_request', r.id::text,
                 jsonb_build_object('phone', r.phone), jsonb_build_object('phone', v_phone),
                 'by an administrator');
end;
$$;
revoke all on function admin_trial_fix_phone(uuid, text) from public, anon;
grant execute on function admin_trial_fix_phone(uuid, text) to authenticated;

create or replace function admin_resend_trial_code(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r trial_requests;
begin
  perform _admin_only();
  select * into r from trial_requests where id = p_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if r.status <> 'approved' then
    raise exception 'not_approved' using errcode = 'P0001';
  end if;
  if r.approval_expires_at <= _server_now() then
    raise exception 'approval_expired' using errcode = 'P0001';
  end if;
  if not _time_trusted() then
    raise exception 'time_untrusted' using errcode = 'P0001';
  end if;
  perform _audit('trial_code_resent', 'trial_request', r.id::text, null, null, 'by an administrator');
  return _issue_challenge('activation', r.id, null, r.phone, r.approved_at, '', _ip_hash(null));
end;
$$;
revoke all on function admin_resend_trial_code(uuid) from public, anon;
grant execute on function admin_resend_trial_code(uuid) to authenticated;

-- Subscription decisions on an existing account:
--   extend_trial   new_end = max(server_now, current_end) + hours   (reason required)
--   confirm_payment paid_until = max(server_now, current paid_until) + days
--                  (a payment reference is required; a receipt picture is not proof)
--   suspend (reason) / reactivate
create or replace function admin_subscription_action(
  p_user      uuid,
  p_action    text,
  p_hours     integer default null,
  p_days      integer default null,
  p_reference text default null,
  p_reason    text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  l        account_licenses;
  v_now    timestamptz := _server_now();
  v_ref    text := nullif(btrim(coalesce(p_reference, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_new    timestamptz;
  v_old    jsonb;
begin
  perform _admin_only();
  select * into l from account_licenses where user_id = p_user for update;
  if not found then
    raise exception 'user_not_found' using errcode = 'P0001';
  end if;
  if coalesce(l.is_admin, false) then
    raise exception 'admin_license_locked' using errcode = 'P0001';
  end if;
  v_old := jsonb_build_object('status', l.status, 'trial_ends_at', l.trial_ends_at,
                              'paid_until', l.paid_until);

  if p_action = 'extend_trial' then
    if p_hours is null or p_hours < 1 or p_hours > 24 * 90 then
      raise exception 'invalid_hours' using errcode = 'P0001';
    end if;
    if v_reason is null then
      raise exception 'reason_required' using errcode = 'P0001';
    end if;
    if l.status = 'blocked' then
      raise exception 'account_suspended' using errcode = 'P0001';
    end if;
    v_new := greatest(v_now, coalesce(l.trial_ends_at, v_now)) + make_interval(hours => p_hours);
    update account_licenses
       set status = 'trial', license_type = 'trial', trial_ends_at = v_new,
           activated_at = coalesce(activated_at, v_now)
     where user_id = p_user;
    perform _audit('trial_extended', 'account', p_user::text, v_old,
                   jsonb_build_object('trial_ends_at', v_new, 'extension_hours', p_hours), v_reason);
    return jsonb_build_object('ok', true, 'trialEndsAt', v_new);

  elsif p_action = 'confirm_payment' then
    if v_ref is null then
      raise exception 'reference_required' using errcode = 'P0001';
    end if;
    if p_days is null or p_days < 1 or p_days > 3650 then
      raise exception 'invalid_days' using errcode = 'P0001';
    end if;
    v_new := greatest(v_now, coalesce(l.paid_until, v_now)) + make_interval(days => p_days);
    update account_licenses
       set status = 'active', license_type = 'paid', paid_until = v_new,
           paid_approved_at = v_now, paid_reference = v_ref,
           activated_at = coalesce(activated_at, v_now),
           suspended_at = null, suspended_reason = null
     where user_id = p_user;
    perform _audit('payment_confirmed', 'account', p_user::text, v_old,
                   jsonb_build_object('paid_until', v_new, 'days', p_days, 'reference', v_ref),
                   v_reason);
    return jsonb_build_object('ok', true, 'paidUntil', v_new);

  elsif p_action = 'suspend' then
    if v_reason is null then
      raise exception 'reason_required' using errcode = 'P0001';
    end if;
    update account_licenses
       set status = 'blocked', suspended_at = v_now, suspended_reason = v_reason
     where user_id = p_user;
    perform _audit('account_suspended', 'account', p_user::text, v_old,
                   jsonb_build_object('status', 'blocked'), v_reason);
    return jsonb_build_object('ok', true);

  elsif p_action = 'reactivate' then
    if l.status <> 'blocked' then
      raise exception 'not_suspended' using errcode = 'P0001';
    end if;
    update account_licenses
       set status = case when paid_approved_at is not null then 'active' else 'trial' end,
           suspended_at = null, suspended_reason = null
     where user_id = p_user;
    perform _audit('account_reactivated', 'account', p_user::text, v_old,
                   jsonb_build_object('status',
                     (select status from account_licenses where user_id = p_user)), v_reason);
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'invalid_action' using errcode = 'P0001';
end;
$$;
revoke all on function admin_subscription_action(uuid, text, integer, integer, text, text) from public, anon;
grant execute on function admin_subscription_action(uuid, text, integer, integer, text, text) to authenticated;

-- A deliberate decision after a clock problem (e.g. a restored database).
create or replace function admin_time_guard_reset(p_reason text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  g time_guard;
begin
  perform _admin_only();
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'reason_required' using errcode = 'P0001';
  end if;
  select * into g from time_guard where id = 1 for update;
  update time_guard set max_seen_at = clock_timestamp(), anomaly_since = null,
         anomaly_alerted = false where id = 1;
  perform _audit('time_guard_reset', 'clock', '1',
                 jsonb_build_object('max_seen_at', g.max_seen_at),
                 jsonb_build_object('max_seen_at', clock_timestamp()), btrim(p_reason));
end;
$$;
revoke all on function admin_time_guard_reset(text) from public, anon;
grant execute on function admin_time_guard_reset(text) to authenticated;

create or replace function admin_list_audit(p_limit integer default 200, p_subject text default null)
returns table (
  id bigint, at timestamptz, actor_email text, kind text, subject_type text,
  subject_id text, old_value jsonb, new_value jsonb, note text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _admin_only();
  return query
  select a.id, a.at, a.actor_email, a.kind, a.subject_type, a.subject_id,
         a.old_value, a.new_value, a.note
    from audit_log a
   where p_subject is null or a.subject_id = p_subject
   order by a.at desc, a.id desc
   limit least(coalesce(p_limit, 200), 1000);
end;
$$;
revoke all on function admin_list_audit(integer, text) from public, anon;
grant execute on function admin_list_audit(integer, text) to authenticated;

create or replace function admin_platform_alerts()
returns table (id uuid, kind text, ref_id text, body text, created_at timestamptz, read_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _admin_only();
  return query
  select a.id, a.kind, a.ref_id, a.body, a.created_at, a.read_at
    from platform_alerts a order by a.created_at desc limit 100;
end;
$$;
revoke all on function admin_platform_alerts() from public, anon;
grant execute on function admin_platform_alerts() to authenticated;

create or replace function admin_alerts_mark_read()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform _admin_only();
  update platform_alerts set read_at = now() where read_at is null;
end;
$$;
revoke all on function admin_alerts_mark_read() from public, anon;
grant execute on function admin_alerts_mark_read() to authenticated;

-- Short marketing indicators.
create or replace function admin_trial_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_total int; v_act int; v_paid int; v_wait numeric;
begin
  perform _admin_only();
  select count(*) into v_total from trial_requests;
  select count(*) into v_act from trial_requests where activated_at is not null;
  select count(*) into v_paid from trial_requests r
    join account_licenses l on l.user_id = r.user_id
   where l.paid_approved_at is not null;
  select avg(extract(epoch from (approved_at - requested_at))) into v_wait
    from trial_requests where approved_at is not null;
  return jsonb_build_object(
    'requests', v_total,
    'activated', v_act,
    'paid', v_paid,
    'avgApprovalWaitSeconds', coalesce(round(v_wait), 0),
    'activationRate', case when v_total = 0 then 0 else round(v_act::numeric / v_total, 4) end,
    'conversionRate', case when v_act = 0 then 0 else round(v_paid::numeric / v_act, 4) end
  );
end;
$$;
revoke all on function admin_trial_stats() from public, anon;
grant execute on function admin_trial_stats() to authenticated;

-- =========================================================================
-- 11) The subscriber's own view (what the app shows and counts down)
-- =========================================================================
-- server_now / trial_ends_at / remaining_seconds / subscription_status /
-- allowed_actions. The countdown on screen is only a display between syncs;
-- it never grants anything.
create or replace function subscription_state()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tenant uuid := _raw_admin_id();
  l        account_licenses;
  v_now    timestamptz := _server_now();
  v_valid  boolean;
  v_ro     boolean;
  v_status text;
begin
  if v_tenant is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  select * into l from account_licenses where user_id = v_tenant;
  if not found then
    return jsonb_build_object('serverNow', v_now, 'status', 'pending',
                              'allowedActions', '[]'::jsonb);
  end if;
  v_valid := _license_valid(v_tenant);
  v_ro := _license_readonly(v_tenant);
  v_status := case
    when coalesce(l.is_admin, false) then 'paid'
    when l.status = 'blocked' then 'suspended'
    when l.status = 'pending' then 'pending'
    when v_valid and l.status = 'trial' then 'trial'
    when v_valid and l.status = 'active' then 'paid'
    when not _time_trusted() and l.status in ('trial', 'active') then 'time_untrusted'
    else 'expired'
  end;
  return jsonb_build_object(
    'serverNow', v_now,
    'status', v_status,
    'licenseType', l.license_type,
    'trialHours', l.trial_hours,
    'activatedAt', l.activated_at,
    'trialEndsAt', l.trial_ends_at,
    'remainingSeconds', case when v_status = 'trial'
        then greatest(0, floor(extract(epoch from (l.trial_ends_at - v_now))))::bigint end,
    'paidUntil', l.paid_until,
    'allowedActions', case when v_valid then '["read","write","export"]'::jsonb
                           when v_ro then '["read","export"]'::jsonb
                           else '[]'::jsonb end,
    'timeTrusted', _time_trusted()
  );
end;
$$;
revoke all on function subscription_state() from public, anon;
grant execute on function subscription_state() to authenticated;

-- "طلب اشتراك" / "طلب تمديد": a message to the administrators, nothing more.
create or replace function subscription_request(p_kind text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tenant uuid := _raw_admin_id();
  a        subscriber_accounts;
  v_note   text := left(nullif(btrim(coalesce(p_note, '')), ''), 300);
begin
  if v_tenant is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if p_kind not in ('subscribe', 'extend') then
    raise exception 'invalid_kind' using errcode = 'P0001';
  end if;
  if not _rate_ok('sub_request', v_tenant::text, 3, interval '1 day') then
    raise exception 'too_many_requests' using errcode = 'P0001';
  end if;
  select * into a from subscriber_accounts where user_id = v_tenant;
  perform _alert(
    'sub_request_' || p_kind, v_tenant::text,
    case p_kind when 'subscribe' then 'طلب اشتراك' else 'طلب تمديد تجربة' end ||
    ': ' || coalesce(a.business_name, v_tenant::text) ||
    coalesce(' — ' || v_note, '')
  );
  perform _audit('sub_request_' || p_kind, 'account', v_tenant::text, null,
                 jsonb_build_object('note', v_note));
end;
$$;
revoke all on function subscription_request(text, text) from public, anon;
grant execute on function subscription_request(text, text) to authenticated;

-- =========================================================================
-- 12) Administrators' account list: the phone of the new accounts too
-- =========================================================================
drop function if exists admin_list_users();
create or replace function admin_list_users()
returns table (
  user_id        uuid,
  email          text,
  status         text,
  license_type   text,
  trial_ends_at  timestamptz,
  is_admin       boolean,
  created_at     timestamptz,
  phone          text
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  return query
  select u.id,
         case when sa.user_id is not null then sa.business_name || ' — ' || sa.manager_name
              else u.email::text end,
         coalesce(l.status, 'pending'),
         l.license_type,
         l.trial_ends_at,
         coalesce(l.is_admin, false),
         u.created_at,
         coalesce(sa.phone, mp.phone)
    from auth.users u
    left join account_licenses l on l.user_id = u.id
    left join subscriber_accounts sa on sa.user_id = u.id
    left join member_phones mp on mp.user_id = u.id
   order by u.created_at desc;
end;
$$;
revoke all on function admin_list_users() from public, anon;
grant execute on function admin_list_users() to authenticated;

-- =========================================================================
-- 12b) Changing the WhatsApp number of an account that already exists
-- =========================================================================
-- The subscriber asks; a code sent to the NEW number proves it is theirs; an
-- administrator approves. One change per 30 days. The old number gets a notice
-- and keeps its place in trial_history, and so does the new one, so changing
-- numbers never earns another trial. The internal sign-in address never
-- changes (subscriber_accounts.auth_email).
create table if not exists phone_change_requests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  old_phone   text not null,
  new_phone   text not null check (new_phone ~ '^\+[1-9][0-9]{7,14}$'),
  status      text not null default 'pending_verify'
              check (status in ('pending_verify', 'pending_admin', 'approved', 'rejected', 'cancelled')),
  created_at  timestamptz not null default now(),
  verified_at timestamptz,
  decided_at  timestamptz,
  decided_by  uuid,
  note        text
);
create unique index if not exists phone_change_open_idx
  on phone_change_requests (user_id) where status in ('pending_verify', 'pending_admin');
alter table phone_change_requests enable row level security;
revoke all on phone_change_requests from anon, authenticated;

create or replace function _subscriber_uid()
returns uuid
language sql
stable
security definer
set search_path = public, extensions
as $$
  select a.user_id from subscriber_accounts a where a.user_id = auth.uid()
$$;
revoke all on function _subscriber_uid() from public, anon, authenticated;

create or replace function phone_change_start(p_new text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := _subscriber_uid();
  a       subscriber_accounts;
  v_phone text := _e164_clean(p_new);
  v_id    uuid;
  v_res   jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if not _license_valid(v_uid) then
    return jsonb_build_object('ok', false, 'code', 'license_inactive');
  end if;
  select * into a from subscriber_accounts where user_id = v_uid;
  if not _e164_ok(v_phone) then
    return jsonb_build_object('ok', false, 'code', 'invalid_phone');
  end if;
  if v_phone = a.phone then
    return jsonb_build_object('ok', false, 'code', 'same_phone');
  end if;
  if exists (select 1 from subscriber_accounts s where s.phone = v_phone)
     or exists (select 1 from trial_history h where h.phone = v_phone)
     or exists (select 1 from trial_requests r where r.phone = v_phone
                 and r.status in ('pending_review', 'needs_info', 'approved')) then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
  end if;
  if exists (select 1 from phone_change_requests c
              where c.user_id = v_uid and c.status = 'approved'
                and c.decided_at > _server_now() - interval '30 days') then
    return jsonb_build_object('ok', false, 'code', 'change_too_soon');
  end if;
  if not _rate_ok('phone_change', v_uid::text, 5, interval '1 day') then
    return jsonb_build_object('ok', false, 'code', 'too_many_requests');
  end if;
  update phone_change_requests set status = 'cancelled'
   where user_id = v_uid and status in ('pending_verify', 'pending_admin');
  insert into phone_change_requests (user_id, old_phone, new_phone, created_at)
  values (v_uid, a.phone, v_phone, _server_now())
  returning id into v_id;
  v_res := _issue_challenge('phone_change', null, v_uid, v_phone, null,
                            'طلب تغيير رقم حسابك في إشاري.' || E'\n', _ip_hash(null));
  perform _audit('phone_change_requested', 'account', v_uid::text,
                 jsonb_build_object('phone', a.phone), jsonb_build_object('phone', v_phone));
  return v_res || jsonb_build_object('requestId', v_id);
end;
$$;
revoke all on function phone_change_start(text) from public, anon;
grant execute on function phone_change_start(text) to authenticated;

create or replace function phone_change_resend()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := _subscriber_uid();
  c     phone_change_requests;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  select * into c from phone_change_requests
   where user_id = v_uid and status = 'pending_verify';
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  return _issue_challenge('phone_change', null, v_uid, c.new_phone, null,
                          'طلب تغيير رقم حسابك في إشاري.' || E'\n', _ip_hash(null));
end;
$$;
revoke all on function phone_change_resend() from public, anon;
grant execute on function phone_change_resend() to authenticated;

create or replace function phone_change_verify(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := _subscriber_uid();
  c     phone_change_requests;
  chk   jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  select * into c from phone_change_requests
   where user_id = v_uid and status = 'pending_verify' for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found');
  end if;
  chk := _check_challenge('phone_change', c.new_phone, p_code, 'chg:' || v_uid::text, null);
  if (chk ->> 'ok')::boolean is not true then
    return chk;
  end if;
  update wa_challenges set consumed_at = now() where id = (chk ->> 'challengeId')::uuid;
  update phone_change_requests set status = 'pending_admin', verified_at = _server_now()
   where id = c.id;
  perform _alert('phone_change', c.id::text,
                 'طلب تغيير رقم بعد تحقق الرقم الجديد: ' ||
                 (select business_name from subscriber_accounts where user_id = v_uid));
  perform _audit('phone_change_verified', 'account', v_uid::text, null,
                 jsonb_build_object('phone', c.new_phone));
  return jsonb_build_object('ok', true, 'status', 'pending_admin');
end;
$$;
revoke all on function phone_change_verify(text) from public, anon;
grant execute on function phone_change_verify(text) to authenticated;

create or replace function phone_change_status()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := _subscriber_uid();
  c     phone_change_requests;
  a     subscriber_accounts;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  select * into a from subscriber_accounts where user_id = v_uid;
  select * into c from phone_change_requests
   where user_id = v_uid order by created_at desc limit 1;
  return jsonb_build_object(
    'phone', _mask_e164(a.phone),
    'status', c.status,
    'newPhone', case when c.id is not null then _mask_e164(c.new_phone) end,
    'note', c.note,
    'nextChangeAfter', (select max(x.decided_at) + interval '30 days'
                          from phone_change_requests x
                         where x.user_id = v_uid and x.status = 'approved')
  );
end;
$$;
revoke all on function phone_change_status() from public, anon;
grant execute on function phone_change_status() to authenticated;

create or replace function phone_change_cancel()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update phone_change_requests set status = 'cancelled'
   where user_id = _subscriber_uid() and status in ('pending_verify', 'pending_admin');
end;
$$;
revoke all on function phone_change_cancel() from public, anon;
grant execute on function phone_change_cancel() to authenticated;

create or replace function admin_list_phone_changes()
returns table (
  id uuid, business_name text, manager_name text, old_phone text, new_phone text,
  status text, created_at timestamptz, verified_at timestamptz, note text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
begin
  perform _admin_only();
  return query
  select c.id, a.business_name, a.manager_name, c.old_phone, c.new_phone,
         c.status, c.created_at, c.verified_at, c.note
    from phone_change_requests c
    join subscriber_accounts a on a.user_id = c.user_id
   order by c.created_at desc limit 200;
end;
$$;
revoke all on function admin_list_phone_changes() from public, anon;
grant execute on function admin_list_phone_changes() to authenticated;

create or replace function admin_phone_change_decide(p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  c      phone_change_requests;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_now  timestamptz := _server_now();
begin
  perform _admin_only();
  select * into c from phone_change_requests where id = p_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0001';
  end if;
  if c.status <> 'pending_admin' then
    raise exception 'request_closed' using errcode = 'P0001';
  end if;
  if p_approve then
    if exists (select 1 from subscriber_accounts s where s.phone = c.new_phone) then
      raise exception 'phone_taken' using errcode = 'P0001';
    end if;
    update subscriber_accounts set phone = c.new_phone where user_id = c.user_id;
    insert into trial_history (phone, first_activated_at, user_id)
    values (c.new_phone, v_now, c.user_id)
    on conflict (phone) do nothing;
    update phone_change_requests
       set status = 'approved', decided_at = v_now, decided_by = auth.uid(), note = v_note
     where id = c.id;
    perform _wa_send(c.old_phone,
      'تنبيه من إشاري: تم تغيير رقم واتساب المرتبط بحسابك إلى رقم جديد. إن لم تكن أنت من طلب ذلك فتواصل مع الدعم فوراً.');
    perform _wa_send(c.new_phone,
      'تم اعتماد هذا الرقم لحسابك في إشاري. ادخل به من «دخول حسابي».');
    perform _audit('phone_change_approved', 'account', c.user_id::text,
                   jsonb_build_object('phone', c.old_phone),
                   jsonb_build_object('phone', c.new_phone), v_note);
  else
    if v_note is null then
      raise exception 'note_required' using errcode = 'P0001';
    end if;
    update phone_change_requests
       set status = 'rejected', decided_at = v_now, decided_by = auth.uid(), note = v_note
     where id = c.id;
    perform _audit('phone_change_rejected', 'account', c.user_id::text, null, null, v_note);
  end if;
end;
$$;
revoke all on function admin_phone_change_decide(uuid, boolean, text) from public, anon;
grant execute on function admin_phone_change_decide(uuid, boolean, text) to authenticated;

-- =========================================================================
-- 13) Close the old self-service doors
-- =========================================================================
do $$
declare
  f text;
begin
  foreach f in array array[
    'member_request_otp(text, text)',
    'member_invite_preview(text)',
    'member_invite_request_otp(text, text)',
    'member_phone_login_request(text)',
    'member_request_phone_otp(text)',
    'member_confirm_phone(text, text)',
    'member_needs_phone()',
    'admin_create_member_invite(text, text, text, integer)',
    'admin_list_member_invites()',
    'admin_revoke_member_invite(uuid)'
  ] loop
    begin
      execute format('revoke execute on function %s from public, anon, authenticated', f);
    exception when undefined_function then
      null;
    end;
  end loop;
end;
$$;

-- =========================================================================
-- 14) One job for the minute-by-minute work (needs pg_cron)
-- =========================================================================
create or replace function eshary_tick()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform time_guard_tick();
  perform wa_sync_status();
  perform expire_overdue_trials();
  delete from rate_events where at < now() - interval '2 days';
end;
$$;
revoke all on function eshary_tick() from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  begin
    perform cron.unschedule('eshary-tick');
  exception when others then
    null;
  end;
  perform cron.schedule('eshary-tick', '* * * * *', 'select public.eshary_tick()');
exception when others then
  raise notice 'pg_cron not scheduled: %', sqlerrm;
end;
$$;

commit;
