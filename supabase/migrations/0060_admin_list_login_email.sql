-- 0060_admin_list_login_email.sql
-- The account cards of new subscribers show "business — manager", not an
-- e-mail (their sign-in address is internal). The old per-account actions
-- (permanent activation, block, ...) find the account by e-mail, so the list
-- now also returns the real sign-in address in `login_email` for the app to
-- use. Permanent activation is also written to the audit log now.
-- Safe to run more than once.

begin;

drop function if exists admin_list_users();
create or replace function admin_list_users()
returns table (
  user_id        uuid,
  email          text,
  status         text,
  license_type   text,
  trial_ends_at  timestamptz,
  is_admin       boolean,
  created_at     timestamptz,
  phone          text,
  login_email    text
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  return query
  select u.id,
         case when sa.user_id is not null then sa.business_name || ' — ' || sa.manager_name
              else u.email::text end,
         coalesce(l.status, 'pending'),
         l.license_type,
         l.trial_ends_at,
         coalesce(l.is_admin, false),
         u.created_at,
         coalesce(sa.phone, mp.phone),
         u.email::text
    from auth.users u
    left join account_licenses l on l.user_id = u.id
    left join subscriber_accounts sa on sa.user_id = u.id
    left join member_phones mp on mp.user_id = u.id
   order by u.created_at desc;
end;
$$;
revoke all on function admin_list_users() from public, anon;
grant execute on function admin_list_users() to authenticated;

create or replace function admin_activate_lifetime(p_user_email text)
returns account_licenses
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_target uuid;
  v_row    account_licenses;
  v_old    jsonb;
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;

  select id into v_target from auth.users
   where lower(email) = lower(trim(p_user_email))
   limit 1;
  if v_target is null then
    raise exception 'user not found';
  end if;

  select jsonb_build_object('status', l.status, 'license_type', l.license_type,
                            'trial_ends_at', l.trial_ends_at, 'paid_until', l.paid_until)
    into v_old
    from account_licenses l where l.user_id = v_target;

  insert into account_licenses (user_id, status, license_type, trial_ends_at, activated_at, activated_by)
  values (v_target, 'active', 'lifetime', null, now(), auth.uid())
  on conflict (user_id) do update
    set status        = 'active',
        license_type  = 'lifetime',
        trial_ends_at = null,
        paid_until    = null,
        suspended_at  = null,
        suspended_reason = null,
        activated_at  = now(),
        activated_by  = auth.uid()
  returning * into v_row;

  perform _audit('lifetime_activated', 'account', v_target::text, v_old,
                 jsonb_build_object('status', 'active', 'license_type', 'lifetime'),
                 'permanent activation by an administrator');
  return v_row;
end;
$$;

commit;
