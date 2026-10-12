-- 0061_deleted_subscriber_cleanup.sql
-- Deleting a subscriber's account (from the app or from the Supabase
-- dashboard) now wipes their trial trail: the request, the "trial already
-- used" mark for the phone, pending codes and number-change requests. So the
-- administrator's list no longer shows them and the same person can ask for a
-- new trial. It is a deliberate administrator decision; the audit log (which
-- cannot be edited) keeps a record of who was deleted.
-- Safe to run more than once.

begin;

create or replace function _subscriber_deleted()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_phone text;
  v_name  text;
begin
  select a.phone, a.business_name into v_phone, v_name
    from subscriber_accounts a where a.user_id = old.id;
  if v_phone is null then
    select r.phone, r.business_name into v_phone, v_name
      from trial_requests r where r.user_id = old.id limit 1;
  end if;
  if v_phone is null then
    return old;           -- not a trial subscriber: nothing to clean
  end if;

  delete from wa_challenges where phone = v_phone or user_id = old.id;
  delete from trial_requests where user_id = old.id or phone = v_phone;
  delete from trial_history where user_id = old.id or phone = v_phone;
  -- phone_change_requests and subscriber_accounts go with the user (cascade)

  insert into audit_log (at, actor, actor_email, kind, subject_type, subject_id,
                         old_value, note)
  values (_server_now(), auth.uid(),
          (select u.email from auth.users u where u.id = auth.uid()),
          'subscriber_deleted', 'account', old.id::text,
          jsonb_build_object('phone', v_phone, 'business', v_name),
          'account deleted; its trial record was cleared');
  return old;
end;
$$;
revoke all on function _subscriber_deleted() from public, anon, authenticated;

drop trigger if exists trg_subscriber_deleted on auth.users;
create trigger trg_subscriber_deleted
  before delete on auth.users
  for each row execute function _subscriber_deleted();

-- Leftovers from accounts that were already deleted before this trigger existed.
delete from wa_challenges c
 where c.user_id is not null and not exists (select 1 from auth.users u where u.id = c.user_id);
delete from trial_history h
 where h.user_id is not null and not exists (select 1 from auth.users u where u.id = h.user_id);
delete from trial_requests r
 where r.status = 'activated' and r.user_id is null;

commit;
