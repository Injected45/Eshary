-- 0053_deleted_accounts_list.sql
-- The administrator can read the log of deleted accounts (written by
-- admin_delete_user, 0052) from the app. Read-only: nothing can edit or delete
-- the log.

begin;

create or replace function admin_list_deleted_accounts()
returns table (
  id               uuid,
  email            text,
  phone            text,
  license_status   text,
  account_created  timestamptz,
  companies        integer,
  clients          integer,
  employees        integer,
  deleted_by_email text,
  deleted_at       timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not is_caller_admin() then
    raise exception 'admin only';
  end if;
  return query
  select d.id, d.email, d.phone, d.license_status, d.account_created,
         d.companies, d.clients, d.employees, d.deleted_by_email, d.deleted_at
    from deleted_accounts d
   order by d.deleted_at desc
   limit 500;
end;
$$;
revoke all on function admin_list_deleted_accounts() from public, anon;
grant execute on function admin_list_deleted_accounts() to authenticated;

commit;
