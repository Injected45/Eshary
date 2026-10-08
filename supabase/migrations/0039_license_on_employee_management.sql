-- 0039_license_on_employee_management.sql
-- Found by the sign-in test run (a real PostgreSQL, 67 checks): the licence gate
-- of 0036 protects the business tables, but the functions that manage and
-- sign in employees are SECURITY DEFINER and bypassed it. A blocked or expired
-- company could still issue QR codes, add employees, and its employees could
-- still sign in and have WhatsApp codes sent for them (each costing a message).
--
-- Three triggers close that, whichever function does the work:
--   * sub_users           before insert/update  (add, edit, device reset, sign-in
--                                                bookkeeping, status changes)
--   * employee_qr_tokens  before insert         (issuing a QR)
--   * employee_otps       before insert         (sending a WhatsApp code)
--
-- Each raises 'license_inactive' when the company that owns the employee does
-- not hold a valid licence (active, or trial not yet ended). They only act for
-- authenticated callers (auth.uid() not null), so the platform owner working
-- from the SQL editor / service role is never blocked.

begin;

create or replace function _admin_license_valid(p_admin uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from account_licenses l
     where l.user_id = p_admin
       and (
         l.status = 'active'
         or (l.status = 'trial'
             and l.trial_ends_at is not null
             and l.trial_ends_at > now())
       )
  )
$$;
revoke all on function _admin_license_valid(uuid) from public, anon, authenticated;

create or replace function _trg_license_sub_users()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null and not _admin_license_valid(new.parent_admin_id) then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function _trg_license_by_sub_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin uuid;
begin
  if auth.uid() is null then
    return new;
  end if;
  select su.parent_admin_id into v_admin from sub_users su where su.id = new.sub_user_id;
  if v_admin is null or not _admin_license_valid(v_admin) then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function _trg_license_sub_users(), _trg_license_by_sub_user()
  from public, anon, authenticated;

drop trigger if exists trg_license_sub_users on sub_users;
create trigger trg_license_sub_users
  before insert or update on sub_users
  for each row execute function _trg_license_sub_users();

drop trigger if exists trg_license_qr_tokens on employee_qr_tokens;
create trigger trg_license_qr_tokens
  before insert on employee_qr_tokens
  for each row execute function _trg_license_by_sub_user();

drop trigger if exists trg_license_otps on employee_otps;
create trigger trg_license_otps
  before insert on employee_otps
  for each row execute function _trg_license_by_sub_user();

commit;
