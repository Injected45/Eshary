-- 0031_admin_binding_audit.sql
-- Audit trail for the admin actions that change who may use an employee
-- account: unbinding a device, and issuing a sign-in QR. Both now write a row
-- in employee_activity_logs (who = the admin, which employee, when, and the
-- device that was unbound).
--
-- Replaces reset_sub_user_device (0024) and admin_create_employee_qr (0030)
-- with the same behaviour plus the audit insert, and widens the event_type
-- whitelist with 'device_reset' and 'qr_issued'.

begin;

alter table employee_activity_logs
  drop constraint if exists employee_activity_logs_event_type_check;

alter table employee_activity_logs
  add constraint employee_activity_logs_event_type_check check (
    event_type in (
      'login',
      'logout',
      'transfer_created',
      'currency_buy_created',
      'pending_buy_created',
      'device_reset',
      'qr_issued'
    )
  );

-- -------------------------------------------------------------------------
create or replace function reset_sub_user_device(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_old_device text;
  v_found      boolean;
begin
  select s.device_id, true
    into v_old_device, v_found
    from sub_users s
   where s.id = p_id
     and s.parent_admin_id = auth.uid();
  if v_found is not true then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;

  update sub_users s
     set device_id          = null,
         login_code_used    = false,
         login_code_used_at = null,
         updated_at         = now()
   where s.id = p_id
     and s.parent_admin_id = auth.uid();

  -- Bounce the employee out of any active session so their current device
  -- loses access immediately.
  update employee_sessions es
     set is_active = false,
         ended_at  = now()
   where es.sub_user_id = p_id
     and es.is_active;

  insert into employee_activity_logs (
    parent_admin_id, sub_user_id, event_type, device_id
  ) values (
    auth.uid(), p_id, 'device_reset', v_old_device
  );
end;
$$;

-- -------------------------------------------------------------------------
create or replace function admin_create_employee_qr(
  p_sub_user_id  uuid,
  p_reset_device boolean default false
) returns table (token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_su         sub_users;
  v_token      text;
  v_exp        timestamptz := now() + interval '10 minutes';
  v_old_device text;
begin
  select * into v_su
    from sub_users s
   where s.id = p_sub_user_id
     and s.parent_admin_id = auth.uid();
  if not found then
    raise exception 'sub_user_not_found' using errcode = 'P0002';
  end if;
  if v_su.status <> 'active' then
    raise exception 'sub_user_disabled' using errcode = 'P0001';
  end if;
  if v_su.registered_email is null then
    raise exception 'email_required' using errcode = 'P0001';
  end if;

  if p_reset_device then
    v_old_device := v_su.device_id;
    update sub_users s
       set device_id          = null,
           login_code_used    = false,
           login_code_used_at = null,
           updated_at         = now()
     where s.id = v_su.id;
    update employee_sessions es
       set is_active = false,
           ended_at  = now()
     where es.sub_user_id = v_su.id
       and es.is_active;
    insert into employee_activity_logs (
      parent_admin_id, sub_user_id, event_type, device_id
    ) values (
      auth.uid(), v_su.id, 'device_reset', v_old_device
    );
  end if;

  delete from employee_qr_tokens t
   where t.sub_user_id = v_su.id
     and (t.used_at is null or t.expires_at < now());

  v_token := encode(gen_random_bytes(32), 'hex');

  insert into employee_qr_tokens (sub_user_id, token_hash, code_hash, expires_at)
  values (
    v_su.id,
    encode(digest(v_token, 'sha256'), 'hex'),
    v_su.login_code_hash,
    v_exp
  );

  insert into employee_activity_logs (
    parent_admin_id, sub_user_id, event_type
  ) values (
    auth.uid(), v_su.id, 'qr_issued'
  );

  return query select v_token, v_exp;
end;
$$;

commit;
