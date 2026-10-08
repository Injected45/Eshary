-- 0045_employee_notifications.sql
-- Two notification flows between the admin and the employees.
--
--   admin_alerts       one row per operation an EMPLOYEE saves (exit / entry),
--                      written by a trigger. The admin reads them (and marks
--                      them read); nobody else can see or write them.
--   employee_messages  messages the admin sends to chosen employees, or to all.
--                      One row per recipient (sharing a broadcast_id), so read
--                      state is tracked per employee.
--
-- Nothing here changes the existing tables' columns or the balance logic; the
-- trigger only appends a row after an employee's insert. The employee name is
-- stored on the alert, so the history survives deleting the employee.
--
-- Separate from the older `notifications` table (0018), which holds the global
-- text shown in the PDF reports.

begin;

-- -------------------------------------------------------------------------
-- 1) Alerts for the admin
-- -------------------------------------------------------------------------
create table if not exists admin_alerts (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id) on delete cascade,
  sub_user_id   uuid references sub_users (id) on delete set null,
  employee_name text not null,
  kind          text not null check (kind in ('transfer', 'buy', 'pending_buy')),
  operation_id  uuid not null,
  amount        numeric(14, 2) not null,
  party_name    text,
  created_at    timestamptz not null default now(),
  read_at       timestamptz
);

create index if not exists admin_alerts_owner_recent_idx
  on admin_alerts (owner_id, created_at desc);
create index if not exists admin_alerts_employee_recent_idx
  on admin_alerts (owner_id, sub_user_id, created_at desc);

alter table admin_alerts enable row level security;

drop policy if exists admin_alerts_select_own on admin_alerts;
create policy admin_alerts_select_own on admin_alerts
  for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists admin_alerts_update_own on admin_alerts;
create policy admin_alerts_update_own on admin_alerts
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists admin_alerts_delete_own on admin_alerts;
create policy admin_alerts_delete_own on admin_alerts
  for delete to authenticated using (owner_id = (select auth.uid()));

drop policy if exists license_gate on admin_alerts;
create policy license_gate on admin_alerts
  as restrictive for all to authenticated using ((select license_ok()));

-- No insert policy: only the trigger (security definer) writes. The only
-- column the admin may change is read_at.
revoke insert, update on admin_alerts from anon, authenticated;
grant update (read_at) on admin_alerts to authenticated;
revoke all on admin_alerts from anon;

create or replace function _alert_on_employee_transfer()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name text;
begin
  select employee_name into v_name from sub_users where id = new.created_by_employee_id;
  insert into admin_alerts (
    owner_id, sub_user_id, employee_name, kind, operation_id, amount, party_name
  ) values (
    new.owner_id, new.created_by_employee_id, coalesce(v_name, '—'),
    'transfer', new.id, new.amount, new.beneficiary_name
  );
  return new;
end;
$$;
revoke all on function _alert_on_employee_transfer() from public, anon, authenticated;

drop trigger if exists trg_alert_employee_transfer on transfers;
create trigger trg_alert_employee_transfer
  after insert on transfers
  for each row
  when (new.created_by_employee_id is not null)
  execute function _alert_on_employee_transfer();

create or replace function _alert_on_employee_buy()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_name   text;
  v_client text;
begin
  select employee_name into v_name from sub_users where id = new.created_by_employee_id;
  select name into v_client from clients where id = new.client_id;
  insert into admin_alerts (
    owner_id, sub_user_id, employee_name, kind, operation_id, amount, party_name
  ) values (
    new.owner_id, new.created_by_employee_id, coalesce(v_name, '—'),
    case when new.status = 'pending' then 'pending_buy' else 'buy' end,
    new.id, new.usd_amount, v_client
  );
  return new;
end;
$$;
revoke all on function _alert_on_employee_buy() from public, anon, authenticated;

drop trigger if exists trg_alert_employee_buy on currency_buys;
create trigger trg_alert_employee_buy
  after insert on currency_buys
  for each row
  when (new.created_by_employee_id is not null)
  execute function _alert_on_employee_buy();

-- -------------------------------------------------------------------------
-- 2) Messages from the admin to employees
-- -------------------------------------------------------------------------
create table if not exists employee_messages (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references auth.users (id) on delete cascade,
  sub_user_id  uuid not null references sub_users (id) on delete cascade,
  broadcast_id uuid not null,
  title        text,
  body         text not null check (length(btrim(body)) > 0 and length(body) <= 1000),
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);

create index if not exists employee_messages_employee_recent_idx
  on employee_messages (sub_user_id, created_at desc);
create index if not exists employee_messages_owner_recent_idx
  on employee_messages (owner_id, created_at desc);

alter table employee_messages enable row level security;

-- The admin sees what they sent; an employee sees only their own messages.
drop policy if exists employee_messages_select_admin on employee_messages;
create policy employee_messages_select_admin on employee_messages
  for select to authenticated using (owner_id = (select auth.uid()));

drop policy if exists employee_messages_select_employee on employee_messages;
create policy employee_messages_select_employee on employee_messages
  for select to authenticated
  using (
    sub_user_id = (select current_employee_id())
    and owner_id = (select effective_admin_id())
  );

drop policy if exists employee_messages_delete_admin on employee_messages;
create policy employee_messages_delete_admin on employee_messages
  for delete to authenticated using (owner_id = (select auth.uid()));

drop policy if exists license_gate on employee_messages;
create policy license_gate on employee_messages
  as restrictive for all to authenticated using ((select license_ok()));

-- Writes only through the functions below.
revoke insert, update on employee_messages from anon, authenticated;
revoke all on employee_messages from anon;

-- p_sub_user_ids NULL or empty = every active employee of the caller.
create or replace function admin_send_employee_message(
  p_sub_user_ids uuid[],
  p_title        text,
  p_body         text
) returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin    uuid := auth.uid();
  v_ids      uuid[];
  v_bid      uuid := gen_random_uuid();
  v_count    integer;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized';
  end if;
  if not license_ok() then
    raise exception 'license_inactive';
  end if;
  if p_body is null or length(btrim(p_body)) = 0 then
    raise exception 'empty_message';
  end if;

  if p_sub_user_ids is null or cardinality(p_sub_user_ids) = 0 then
    select array_agg(id) into v_ids
      from sub_users
     where parent_admin_id = v_admin and status = 'active';
  else
    select array_agg(id) into v_ids
      from sub_users
     where parent_admin_id = v_admin and status = 'active'
       and id = any (p_sub_user_ids);
    -- every chosen employee must be the caller's and active
    if coalesce(cardinality(v_ids), 0)
         <> cardinality(array(select distinct x from unnest(p_sub_user_ids) x)) then
      raise exception 'invalid_recipients';
    end if;
  end if;

  if v_ids is null or cardinality(v_ids) = 0 then
    raise exception 'no_recipients';
  end if;

  insert into employee_messages (owner_id, sub_user_id, broadcast_id, title, body)
  select v_admin, u, v_bid, nullif(btrim(coalesce(p_title, '')), ''), btrim(p_body)
    from unnest(v_ids) u;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function admin_send_employee_message(uuid[], text, text) from public, anon;
grant execute on function admin_send_employee_message(uuid[], text, text) to authenticated;

-- An employee marks their own message read.
create or replace function employee_mark_messages_read(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_emp   uuid := current_employee_id();
  v_count integer;
begin
  if v_emp is null or effective_admin_id() is null then
    raise exception 'not_authorized';
  end if;
  update employee_messages
     set read_at = now()
   where sub_user_id = v_emp and read_at is null
     and (p_ids is null or id = any (p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function employee_mark_messages_read(uuid[]) from public, anon;
grant execute on function employee_mark_messages_read(uuid[]) to authenticated;

-- -------------------------------------------------------------------------
-- 3) Live updates
-- -------------------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table admin_alerts;
exception when duplicate_object then null;
         when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table employee_messages;
exception when duplicate_object then null;
         when undefined_object then null;
end $$;

commit;
