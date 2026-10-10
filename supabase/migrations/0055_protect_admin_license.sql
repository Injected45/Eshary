-- 0055_protect_admin_license.sql
-- A platform administrator's licence is permanent and cannot be changed or
-- removed through the app: no activation change, no block, no "back to
-- pending", no trial, no deletion. (Taking the admin role away is a separate,
-- deliberate step: it flips is_admin first, which this rule allows.)
--
-- Direct SQL from the Dashboard (no signed-in user) is left free, so the owner
-- can always repair an account from there.

begin;

create or replace function _protect_admin_license()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Dashboard / service work: no signed-in user, no restriction.
  if auth.uid() is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'DELETE' then
    if old.is_admin then
      raise exception 'admin_license_locked' using errcode = 'P0001';
    end if;
    return old;
  end if;

  -- An update that keeps the account an admin must not touch its licence.
  if old.is_admin and new.is_admin
     and (new.status        is distinct from old.status
       or new.license_type  is distinct from old.license_type
       or new.trial_ends_at is distinct from old.trial_ends_at
       or new.activated_at  is distinct from old.activated_at
       or new.activated_by  is distinct from old.activated_by) then
    raise exception 'admin_license_locked' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_admin_license on account_licenses;
create trigger trg_protect_admin_license
  before update or delete on account_licenses
  for each row execute function _protect_admin_license();

commit;
