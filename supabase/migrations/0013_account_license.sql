-- 0013_account_license.sql
-- Manual-activation license gate. Every newly registered user lands in
-- status='pending' and cannot use the app until an admin (service_role
-- via Supabase Studio) flips them to 'trial' or 'active'/'lifetime'.
--
-- Note: filename is 0013 because 0012 is already in use by
-- 0012_currency_buys_reference.sql. Order of execution still matches the
-- intent in the planning doc — the trigger on auth.users is additive and
-- composes cleanly with handle_new_user() from 0005.

begin;

-- =========================================================================
-- account_licenses
-- =========================================================================

create table if not exists account_licenses (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  status         text not null default 'pending'
                 check (status in ('pending','trial','active','expired','blocked')),
  license_type   text check (license_type in ('trial','lifetime')),
  trial_ends_at  timestamptz,
  activated_at   timestamptz,
  activated_by   uuid references auth.users (id),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists account_licenses_status_idx
  on account_licenses (status);
create index if not exists account_licenses_trial_ends_at_idx
  on account_licenses (trial_ends_at)
  where status = 'trial';

-- updated_at maintenance
create or replace function set_account_licenses_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_account_licenses_updated_at on account_licenses;
create trigger trg_account_licenses_updated_at
  before update on account_licenses
  for each row execute function set_account_licenses_updated_at();

-- =========================================================================
-- RLS — users can SELECT their own row only. No insert/update/delete for
-- end users; admin uses service_role from Supabase Studio.
-- =========================================================================

alter table account_licenses enable row level security;

drop policy if exists account_licenses_select_own on account_licenses;
create policy account_licenses_select_own on account_licenses
  for select using (user_id = auth.uid());

-- =========================================================================
-- Auto-provision a pending license row on auth.users INSERT. Composes with
-- handle_new_user() from 0005_auth_triggers.sql via a separate trigger so
-- either can be reverted independently.
-- =========================================================================

create or replace function handle_new_user_license()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into account_licenses (user_id, status)
  values (new.id, 'pending')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_license on auth.users;
create trigger on_auth_user_created_license
  after insert on auth.users
  for each row execute function handle_new_user_license();

-- Backfill: any pre-existing user without a license row gets one in pending
-- so the gate covers users created before this migration.
insert into account_licenses (user_id, status)
select u.id, 'pending'
  from auth.users u
  left join account_licenses l on l.user_id = u.id
 where l.user_id is null;

-- =========================================================================
-- Admin RPCs (service_role only). These are sugar for the admin so they can
-- right-click → run from Studio instead of hand-editing columns. Hand-editing
-- the row directly is also fine.
-- =========================================================================

create or replace function activate_trial(p_user uuid)
returns account_licenses
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_row account_licenses;
begin
  insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
  values (p_user, 'trial', 'trial', now() + interval '3 days', now(), auth.uid())
  on conflict (user_id) do update
    set status        = 'trial',
        license_type  = 'trial',
        trial_ends_at = now() + interval '3 days',
        activated_at  = now(),
        activated_by  = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function activate_lifetime(p_user uuid)
returns account_licenses
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_row account_licenses;
begin
  insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
  values (p_user, 'active', 'lifetime', null, now(), auth.uid())
  on conflict (user_id) do update
    set status        = 'active',
        license_type  = 'lifetime',
        trial_ends_at = null,
        activated_at  = now(),
        activated_by  = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function activate_trial(uuid)    from public, anon, authenticated;
revoke all on function activate_lifetime(uuid) from public, anon, authenticated;
grant  execute on function activate_trial(uuid)    to service_role;
grant  execute on function activate_lifetime(uuid) to service_role;

-- =========================================================================
-- current_license_status() — what the app calls on every gate evaluation.
-- security definer so the row is visible even if the user somehow lacks a
-- direct SELECT (shouldn't happen given the RLS policy, but cheap safety).
-- =========================================================================

create or replace function current_license_status()
returns table (
  status         text,
  license_type   text,
  trial_ends_at  timestamptz,
  is_valid       boolean
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
         (l.status = 'active'
            or (l.status = 'trial' and l.trial_ends_at is not null and l.trial_ends_at > now()))
           as is_valid
    from account_licenses l
   where l.user_id = v_uid;
end;
$$;

grant execute on function current_license_status() to authenticated;

-- =========================================================================
-- expire_overdue_trials() — flip rows whose trial window has elapsed. Call
-- manually from Studio, or schedule via pg_cron if the extension is enabled.
-- The Dart side does NOT enforce expiry; the server is the source of truth.
-- =========================================================================

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
     where status = 'trial'
       and trial_ends_at is not null
       and trial_ends_at <= now()
    returning 1
  )
  select count(*) into v_count from updated;
  return v_count;
end;
$$;

revoke all on function expire_overdue_trials() from public, anon, authenticated;
grant  execute on function expire_overdue_trials() to service_role;

commit;
