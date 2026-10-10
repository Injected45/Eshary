-- 0057_new_account_by_phone_email.sql
-- New accounts no longer use Google. The person picks an e-mail account that is
-- signed in on their phone (Android's account chooser lists only addresses that
-- are open and active on the device), types their phone number, and confirms
-- it with ONE WhatsApp code. Supersedes the "use_google" rule of 0050.
--
--   * unknown e-mail                      -> new account, WhatsApp code only
--   * known e-mail, phone already linked  -> same phone + WhatsApp code
--   * known e-mail, no phone linked yet   -> e-mail code STILL required
--                                            (an existing account that nothing
--                                            else protects: a request made by
--                                            hand with its address and another
--                                            phone must not take it over)
--   * a phone linked to another account   -> refused
--   * platform admin accounts never use this door
--
-- The Edge Function `member-session` (this repo's version) creates the user for
-- a new e-mail itself: it must be deployed.
--
-- member_needs_phone / member_request_phone_otp / member_confirm_phone (0050)
-- stay for accounts that arrive another way (e.g. the administrator's Google
-- sign-in); they are not part of the new-account flow.

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
    -- New account: the WhatsApp code is the only proof.
    return jsonb_build_object('ok', true, 'userId', null, 'needsEmail', false);
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
