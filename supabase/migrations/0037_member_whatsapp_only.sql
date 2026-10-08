-- 0037_member_whatsapp_only.sql
-- One message only: the WhatsApp code. The e-mail is no longer verified by a
-- code (it is an identifier the administrator sees); the PHONE is what is
-- proven. Replaces only the identity rule from 0035, so member_request_otp and
-- member_consume_otp keep working unchanged (needsEmail is now always false).
--
-- Rules:
--   * unknown e-mail                      -> new account (the phone must be free)
--   * known e-mail, phone already linked  -> must be that same phone
--   * known e-mail, NO phone linked:
--       - an unfinished registration (never confirmed, never signed in), e.g.
--         left over from the e-mail-code step of 0035  -> may be completed
--       - any other existing account (a real subscriber, the platform admin)
--         -> refused: a stranger who merely knows the e-mail must not be able
--         to attach their own phone to it.
--   * a phone linked to another account   -> refused.

begin;

create or replace function _member_check_identity(p_email text, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_user      uuid;
  v_confirmed timestamptz;
  v_signed_in timestamptz;
  v_known     text;
begin
  select u.id, u.email_confirmed_at, u.last_sign_in_at
    into v_user, v_confirmed, v_signed_in
    from auth.users u
   where lower(u.email) = p_email
   limit 1;

  if v_user is null then
    if exists (select 1 from member_phones mp where mp.phone = p_phone) then
      return jsonb_build_object('ok', false, 'code', 'phone_taken');
    end if;
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

  -- No phone linked: only an unfinished registration may be completed.
  if v_confirmed is not null or v_signed_in is not null then
    return jsonb_build_object('ok', false, 'code', 'identity_mismatch');
  end if;
  if exists (select 1 from member_phones mp where mp.phone = p_phone) then
    return jsonb_build_object('ok', false, 'code', 'phone_taken');
  end if;
  return jsonb_build_object('ok', true, 'userId', v_user, 'needsEmail', false);
end;
$$;
revoke all on function _member_check_identity(text, text) from public, anon, authenticated;

commit;
