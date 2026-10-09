-- 0051_admin_list_users_phone.sql
-- The administrator approves every new account, so the users list also shows
-- the phone each person confirmed (member_phones, WhatsApp code). Same rules as
-- before: only a platform admin can call it.

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
  phone          text
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
  select u.id          as user_id,
         u.email::text  as email,
         coalesce(l.status, 'pending') as status,
         l.license_type,
         l.trial_ends_at,
         coalesce(l.is_admin, false)   as is_admin,
         u.created_at,
         mp.phone
    from auth.users u
    left join account_licenses l on l.user_id = u.id
    left join member_phones mp on mp.user_id = u.id
   order by u.created_at desc;
end;
$$;

revoke all on function admin_list_users() from public, anon;
grant execute on function admin_list_users() to authenticated;

commit;
