-- 0049_new_account_whatsapp_only.sql
-- A NEW account no longer needs an e-mail code: the e-mail is chosen from the
-- accounts signed in on the phone (the app's account chooser) and the person
-- proves the phone with the WhatsApp code. One step, one code.
--
-- What changes (identity rule of 0038):
--   * unknown e-mail                        -> new account, WhatsApp code only   (was: + e-mail code)
--   * known e-mail, phone already linked    -> same phone + WhatsApp code        (unchanged)
--   * known e-mail, no phone linked yet     -> e-mail code STILL required        (unchanged)
--   * a phone linked to another account     -> refused                           (unchanged)
--   * platform admin accounts never use this door                                (unchanged)
--
-- Why the third line stays: an existing account that has no phone linked yet
-- (an e-mail/password or Google account) is protected only by its e-mail. The
-- server cannot tell whether an address was picked from the phone's list or
-- sent by a hand-made request, so letting a WhatsApp code alone link a phone to
-- such an account would let anyone take it over by entering its address with
-- their own phone. A brand-new address has nothing to take over.
--
-- The Edge Function `member-session` must be redeployed: it now creates the
-- user for a new e-mail itself (service role, e-mail pre-confirmed) instead of
-- relying on the e-mail code to create it.

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
  -- Existing account with no phone yet: it still has to prove it owns the
  -- address (e-mail code).
  return jsonb_build_object('ok', true, 'userId', v_user, 'needsEmail', true);
end;
$$;
revoke all on function _member_check_identity(text, text) from public, anon, authenticated;

commit;
