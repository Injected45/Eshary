-- 0064_delete_my_account.sql
-- Google Play requires an account-deletion path inside the app. A subscriber
-- deletes their own account with a WhatsApp code sent to their registered
-- phone (so a borrowed, unlocked phone cannot delete it). Deleting removes:
--   * the account and everything it owns (companies, accounts, clients,
--     beneficiaries, operations, employees, branches ... by cascade);
--   * the employees' anonymous sign-ins;
--   * the trial trail of the phone (the same person may ask again);
--   * the personal data inside the audit log (the events stay, their contents
--     are erased) and inside the stored backups (their rows are removed);
--   * alerts and rate counters that carry the business name or the phone.
-- Safe to run more than once.

begin;

-- 1) a new kind of code
alter table wa_challenges drop constraint if exists wa_challenges_purpose_check;
alter table wa_challenges add constraint wa_challenges_purpose_check
  check (purpose in ('activation', 'login', 'phone_change', 'account_delete'));

-- 2) the audit log stays append-only, with ONE exception: erasing the contents
--    of the rows about an account that is being deleted (the row, its kind and
--    its time stay; names, phones and values go).
create or replace function _audit_immutable()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and coalesce(current_setting('eshary.audit_scrub', true), '') = 'on'
     and new.id = old.id
     and new.at = old.at
     and new.kind = old.kind
     and new.subject_type is not distinct from old.subject_type
     and new.subject_id is not distinct from old.subject_id
     and new.old_value is null
     and new.new_value is null
     and new.note is null
     and new.actor_email is null
     and new.ip_hash is null then
    return new;
  end if;
  raise exception 'audit_immutable' using errcode = 'P0001';
end;
$$;

-- 3) stored backups: remove the rows of one account
create or replace function _redact_owner_from_backups(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.backups b
     set data = jsonb_set(
       b.data,
       '{tables}',
       (
         select coalesce(jsonb_object_agg(e.k, case
           when e.k = 'profiles' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'id' is distinct from p_uid::text)
           when e.k = 'account_licenses' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'user_id' is distinct from p_uid::text)
           when e.k in ('branches', 'sub_users', 'employee_activity_logs') then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'parent_admin_id' is distinct from p_uid::text)
           when e.k = 'exchanges' then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where (r ->> 'company_id') not in (
                 select c ->> 'id'
                   from jsonb_array_elements(coalesce(b.data -> 'tables' -> 'companies', '[]'::jsonb)) c
                  where c ->> 'owner_id' = p_uid::text))
           when e.k in ('companies', 'clients', 'beneficiaries', 'countries',
                        'exchange_companies', 'transfers', 'currency_buys',
                        'cancellation_requests', 'operation_cancellations') then
             (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(e.v) r
               where r ->> 'owner_id' is distinct from p_uid::text)
           else e.v
         end), '{}'::jsonb)
         from jsonb_each(b.data -> 'tables') as e(k, v)
       )
     )
   where jsonb_typeof(b.data -> 'tables') = 'object';
  update public.backups set size_bytes = octet_length(data::text) where true;
end;
$$;
revoke all on function _redact_owner_from_backups(uuid) from public, anon, authenticated;

-- 4) whatever way an account is deleted (the app, an administrator, the
--    dashboard), its personal traces go with it.
create or replace function _subscriber_deleted()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text;
  v_reqs  text[];
begin
  select a.phone into v_phone from subscriber_accounts a where a.user_id = old.id;
  if v_phone is null then
    select r.phone into v_phone from trial_requests r where r.user_id = old.id limit 1;
  end if;
  select coalesce(array_agg(r.id::text), '{}') into v_reqs
    from trial_requests r
   where r.user_id = old.id or (v_phone is not null and r.phone = v_phone);

  -- the audit rows about this account: the events stay, the contents go
  perform set_config('eshary.audit_scrub', 'on', true);
  update audit_log
     set old_value = null, new_value = null, note = null,
         actor_email = null, ip_hash = null
   where subject_id = old.id::text
      or subject_id = any (v_reqs)
      or actor = old.id;
  perform set_config('eshary.audit_scrub', 'off', true);

  delete from platform_alerts
   where ref_id = old.id::text or ref_id = any (v_reqs);
  delete from rate_events
   where key = old.id::text or (v_phone is not null and key = v_phone);

  perform _redact_owner_from_backups(old.id);

  if v_phone is not null then
    delete from wa_challenges where phone = v_phone or user_id = old.id;
    delete from trial_requests where user_id = old.id or phone = v_phone;
    delete from trial_history where user_id = old.id or phone = v_phone;
    -- phone_change_requests and subscriber_accounts go with the user (cascade)
    insert into audit_log (at, actor, kind, subject_type, subject_id)
    values (_server_now(), null, 'subscriber_deleted', 'account', old.id::text);
  end if;
  return old;
end;
$$;
revoke all on function _subscriber_deleted() from public, anon, authenticated;

-- 5) the subscriber's own request: a code to the phone on the account
create or replace function account_delete_request()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_phone text;
begin
  if v_uid is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if coalesce((select l.is_admin from account_licenses l where l.user_id = v_uid), false) then
    raise exception 'cannot_delete_admin' using errcode = 'P0001';
  end if;
  select a.phone into v_phone from subscriber_accounts a where a.user_id = v_uid;
  if v_phone is null then
    select m.phone into v_phone from member_phones m where m.user_id = v_uid;
    -- legacy 09XXXXXXXX numbers go out in international form
    if v_phone is not null and v_phone ~ '^09[0-9]{8}$' then
      v_phone := '+218' || substr(v_phone, 2);
    end if;
  end if;
  if v_phone is null then
    return jsonb_build_object('ok', false, 'code', 'no_phone');
  end if;
  return _issue_challenge(
    'account_delete', null, v_uid, v_phone, null,
    'طلب حذف حسابك في إشاري نهائياً.' || E'\n' ||
    'إن لم تكن أنت من طلب ذلك فتجاهل الرسالة ولا تشارك الرمز.' || E'\n',
    _ip_hash(null)
  );
end;
$$;
revoke all on function account_delete_request() from public, anon;
grant execute on function account_delete_request() to authenticated;

-- 6) the confirmation: the right code deletes the account for good
create or replace function account_delete_confirm(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_phone text;
  chk     jsonb;
  v_anon  uuid[];
begin
  if v_uid is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if coalesce((select l.is_admin from account_licenses l where l.user_id = v_uid), false) then
    raise exception 'cannot_delete_admin' using errcode = 'P0001';
  end if;
  select a.phone into v_phone from subscriber_accounts a where a.user_id = v_uid;
  if v_phone is null then
    select m.phone into v_phone from member_phones m where m.user_id = v_uid;
    if v_phone is not null and v_phone ~ '^09[0-9]{8}$' then
      v_phone := '+218' || substr(v_phone, 2);
    end if;
  end if;
  if v_phone is null then
    return jsonb_build_object('ok', false, 'code', 'no_phone');
  end if;

  chk := _check_challenge('account_delete', v_phone, p_code, 'del:' || v_uid::text, null);
  if (chk ->> 'ok')::boolean is not true then
    return chk;
  end if;
  update wa_challenges set consumed_at = now() where id = (chk ->> 'challengeId')::uuid;

  -- the employees' anonymous sign-ins belong to this account too
  select coalesce(array_agg(s.anonymous_user_id), '{}') into v_anon
    from employee_sessions s
    join sub_users su on su.id = s.sub_user_id
   where su.parent_admin_id = v_uid;

  -- everything the account owns goes by cascade; the trigger cleans the trail
  delete from auth.users where id = v_uid;
  if cardinality(v_anon) > 0 then
    delete from auth.users where id = any (v_anon);
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function account_delete_confirm(text) from public, anon;
grant execute on function account_delete_confirm(text) to authenticated;

commit;
