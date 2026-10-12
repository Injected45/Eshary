-- reviewer_seed.sql — NOT a migration: run it by hand, once, for the Google Play
-- reviewer's account (see docs/reviewer-account.md).
--
-- 1) Authentication > Users > Add user: an e-mail and a password, "Auto Confirm
--    User" ticked. Write them in Play Console > App content > App access.
-- 2) Put that e-mail on the first line below, then run this whole script in the
--    SQL Editor.
--
-- It gives that account a permanent licence (so the trial clock never locks the
-- reviewer out) and a little demo data: one company with two accounts, the
-- exchange offices, and two senders / a beneficiary, so every screen has
-- something to show and an exit / entry can be saved straight away.
-- Safe to run more than once: it adds the demo data only if the account has none.

do $$
declare
  v_email text := 'reviewer@example.com';   -- <<< CHANGE THIS to the reviewer's e-mail
  v_uid   uuid;
  v_co    uuid;
begin
  select id into v_uid from auth.users where lower(email) = lower(v_email);
  if v_uid is null then
    raise exception 'No user with e-mail %. Create it first in Authentication > Users.', v_email;
  end if;

  -- a permanent licence: the reviewer is never stopped by the clock
  insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at)
  values (v_uid, 'active', 'lifetime', null, now())
  on conflict (user_id) do update
    set status = 'active', license_type = 'lifetime', trial_ends_at = null,
        paid_until = null, activated_at = now();

  if exists (select 1 from companies where owner_id = v_uid) then
    raise notice 'The account already has data: nothing added.';
    return;
  end if;

  insert into exchange_companies (owner_id, name) values
    (v_uid, 'شركة الصرافة الأولى'),
    (v_uid, 'شركة الصرافة الثانية');

  insert into companies (owner_id, name, start_ref)
  values (v_uid, 'شركتي التجريبية', 'REF-1000')
  returning id into v_co;

  insert into exchanges (company_id, name, balance, our_code) values
    (v_co, 'شركة الصرافة الأولى', 25000, 'ACC-100'),
    (v_co, 'شركة الصرافة الثانية', 10000, 'ACC-200');

  insert into clients (owner_id, name, company, code) values
    (v_uid, 'أحمد علي', 'شركة المرسل التجريبية', 'S-001'),
    (v_uid, 'سالم محمد', 'شركة المرسل التجريبية', 'S-002');

  insert into beneficiaries (owner_id, name, account, code) values
    (v_uid, 'مستفيد تجريبي', 'شركة المستفيد التجريبية', 'B-001');

  raise notice 'Done: licence + demo data for %', v_email;
end;
$$;
