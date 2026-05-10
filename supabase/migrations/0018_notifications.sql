-- 0018_notifications.sql
-- Global app-wide notifications shown in the header of every PDF report.
-- All authenticated users can read the active notifications; only admins
-- (gated by is_caller_admin() from 0014) may insert / update / delete.

begin;

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  title       text,
  body        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users (id) on delete set null
);

create index notifications_active_recent_idx
  on notifications (is_active, created_at desc)
  where is_active = true;

alter table notifications enable row level security;

create policy notifications_select_active on notifications
  for select to authenticated
  using (is_active = true);

create policy notifications_insert_admin on notifications
  for insert to authenticated
  with check (is_caller_admin());

create policy notifications_update_admin on notifications
  for update to authenticated
  using (is_caller_admin())
  with check (is_caller_admin());

create policy notifications_delete_admin on notifications
  for delete to authenticated
  using (is_caller_admin());

commit;
