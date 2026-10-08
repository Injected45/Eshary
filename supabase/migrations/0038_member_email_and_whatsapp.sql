-- 0038_member_email_and_whatsapp.sql
-- Back to TWO proofs the first time (reverses 0037): the e-mail (a code Supabase
-- mails to it) AND the phone (the WhatsApp code). Anyone registering with an
-- e-mail they do not own can no longer succeed, because the e-mail code goes to
-- the real owner. Later sign-ins use e-mail + the linked phone + the WhatsApp
-- code only.
--
-- Same identity rule as 0035 (this file simply re-applies it):
--   * unknown e-mail                        -> new account, e-mail proof needed
--   * known e-mail, phone already linked    -> must be the same phone, no e-mail proof
--   * known e-mail, no phone linked yet     -> e-mail proof needed (not for admins)
--   * a phone linked to another account     -> refused
--   * platform admin accounts never use this door
--
-- member_request_otp / member_consume_otp (0035) are unchanged. The Edge Function
-- `member-session` must be the version that also checks the e-mail code.

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

commit;
