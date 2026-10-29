-- 0090_sell_buy_wording.sql
-- The owner renamed the two operations on 2026-10-29: an exit ("خروج") is now
-- "بيع" and an entry ("دخول") is now "شراء", everywhere the app shows them.
-- Two messages the database itself sends to an employee name the operation:
-- «تم إلغاء عملية "بيع"...» and «تم رفض طلب إلغاء عملية "شراء"...». These two
-- functions are copied from 0048 (their latest definition) with only that
-- word changed. Nothing else changes; no row is touched. The WhatsApp
-- messages are built by the app and are not affected.
--
-- Needs 0089. Safe to run more than once.

begin;

do $$
begin
  if to_regprocedure('public._next_reference_for(uuid, uuid)') is null then
    raise exception 'شغّل الترحيل 0089 أولًا، ثم هذا الملف. لم يتغير شيء.';
  end if;
  -- run again after 0093 it would bring back a cancel that moves the account
  -- but not its book
  if to_regclass('public.account_books') is not null then
    raise exception 'هذا الملف (0090) طُبِّق سابقًا وتبعه 0093. لا تشغّله مرة أخرى. لم يتغير شيء.';
  end if;
end $$;

create or replace function admin_reject_cancellation(
  p_request_id uuid,
  p_note       text default null
) returns cancellation_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := auth.uid();
  v_row   cancellation_requests;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;

  update cancellation_requests
     set status = 'rejected',
         decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_request_id and owner_id = v_admin and status = 'pending'
  returning * into v_row;
  if not found then
    raise exception 'cancel_request_not_found' using errcode = 'P0001';
  end if;

  if v_row.sub_user_id is not null then
    insert into employee_messages (owner_id, sub_user_id, broadcast_id, title, body)
    values (
      v_admin, v_row.sub_user_id, gen_random_uuid(), 'طلب إلغاء مرفوض',
      format('تم رفض طلب إلغاء عملية "%s" بقيمة %s$%s',
             case v_row.kind when 'transfer' then 'بيع' else 'شراء' end,
             to_char(v_row.amount, 'FM999G999G990D00'),
             coalesce(E'\nالملاحظة: ' || v_row.decision_note, ''))
    );
  end if;

  return v_row;
end;
$$;
revoke all on function admin_reject_cancellation(uuid, text) from public, anon;
grant execute on function admin_reject_cancellation(uuid, text) to authenticated;

create or replace function admin_cancel_operation(
  p_kind         text,
  p_operation_id uuid,
  p_reason       text,
  p_password     text,
  p_request_id   uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin      uuid := auth.uid();
  v_reason     text := btrim(coalesce(p_reason, ''));
  v_hash       text;
  v_admin_name text;
  v_fails      integer;
  v_t          transfers;
  v_b          currency_buys;
  v_company    uuid;
  v_exchange   uuid;
  v_amount     numeric;
  v_ref        text;
  v_party      text;
  v_at         timestamptz;
  v_emp        uuid;
  v_emp_name   text;
  v_before     numeric;
  v_after      numeric;
  v_req_id     uuid;
  v_req_name   text;
  v_req_emp    uuid;
  v_id         uuid;
  v_ex_name    text;
  v_ex_code    text;
  v_co_name    text;
begin
  if v_admin is null or current_employee_id() is not null then
    raise exception 'not_authorized' using errcode = 'P0001';
  end if;
  if not license_ok() then
    raise exception 'license_inactive' using errcode = 'P0001';
  end if;
  if p_kind not in ('transfer', 'buy') then
    raise exception 'cancel_not_found' using errcode = 'P0001';
  end if;
  if length(v_reason) < 3 or length(v_reason) > 500 then
    raise exception 'cancel_reason_required' using errcode = 'P0001';
  end if;

  -- Lock after 5 wrong passwords in 15 minutes.
  select count(*) into v_fails
    from cancel_auth_failures
   where user_id = v_admin and created_at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;

  select u.encrypted_password,
         coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
                  u.email, 'المدير')
    into v_hash, v_admin_name
    from auth.users u
   where u.id = v_admin;

  if v_hash is null or v_hash = '' then
    return jsonb_build_object('ok', false, 'error', 'password_not_set');
  end if;
  if p_password is null or crypt(p_password, v_hash) <> v_hash then
    insert into cancel_auth_failures (user_id) values (v_admin);
    return jsonb_build_object(
      'ok', false, 'error', 'wrong_password', 'remaining', greatest(0, 4 - v_fails)
    );
  end if;
  delete from cancel_auth_failures where user_id = v_admin;

  -- The operation, locked.
  if p_kind = 'transfer' then
    select * into v_t from transfers
     where id = p_operation_id and owner_id = v_admin
       for update;
    if not found then
      raise exception 'cancel_not_found' using errcode = 'P0001';
    end if;
    if v_t.status <> 'archived' then
      raise exception 'cancel_not_cancellable' using errcode = 'P0001';
    end if;
    if v_t.cancelled_at is not null then
      raise exception 'cancel_already' using errcode = 'P0001';
    end if;
    v_company := v_t.company_id;  v_exchange := v_t.exchange_id;
    v_amount  := v_t.amount;      v_ref      := v_t.reference;
    v_party   := v_t.beneficiary_name;
    v_at      := v_t.created_at;  v_emp      := v_t.created_by_employee_id;
  else
    select * into v_b from currency_buys
     where id = p_operation_id and owner_id = v_admin
       for update;
    if not found then
      raise exception 'cancel_not_found' using errcode = 'P0001';
    end if;
    if v_b.status <> 'archived' then
      raise exception 'cancel_not_cancellable' using errcode = 'P0001';
    end if;
    if v_b.cancelled_at is not null then
      raise exception 'cancel_already' using errcode = 'P0001';
    end if;
    v_company := v_b.my_company_id;  v_exchange := v_b.exchange_id;
    v_amount  := v_b.usd_amount;     v_ref      := v_b.reference;
    select coalesce(c.name, v_b.client_from_account) into v_party
      from (select 1) x left join clients c on c.id = v_b.client_id;
    v_at      := v_b.created_at;     v_emp      := v_b.created_by_employee_id;
  end if;

  if _ops_day(v_at) <> _ops_day(now()) then
    raise exception 'cancel_day_passed' using errcode = 'P0001';
  end if;

  -- The reversing entry, on the locked account.
  select balance, name, our_code into v_before, v_ex_name, v_ex_code
    from exchanges where id = v_exchange for update;
  if p_kind = 'transfer' then
    v_after := v_before + v_amount;
  else
    v_after := v_before - v_amount;
    if v_after < 0 then
      raise exception 'cancel_insufficient_balance' using errcode = 'P0001',
        detail = format('balance %s, entry %s', v_before, v_amount);
    end if;
  end if;
  update exchanges set balance = v_after where id = v_exchange;

  if p_kind = 'transfer' then
    update transfers set cancelled_at = now() where id = p_operation_id;
  else
    update currency_buys set cancelled_at = now() where id = p_operation_id;
  end if;

  -- The request(s) for it, approved.
  if p_request_id is not null and not exists (
    select 1 from cancellation_requests
     where id = p_request_id and owner_id = v_admin
       and operation_id = p_operation_id and status = 'pending'
  ) then
    raise exception 'cancel_request_not_found' using errcode = 'P0001';
  end if;
  update cancellation_requests
     set status = 'approved', decided_at = now()
   where operation_id = p_operation_id and status = 'pending'
  returning id, employee_name, sub_user_id into v_req_id, v_req_name, v_req_emp;

  select name into v_co_name from companies where id = v_company;
  if v_emp is not null then
    select employee_name into v_emp_name from sub_users where id = v_emp;
  end if;

  insert into operation_cancellations (
    owner_id, kind, operation_id, company_id, exchange_id, company_name,
    exchange_name, exchange_code, amount, reference, party_name,
    operation_created_at, operation_employee_id, operation_employee_name,
    request_id, requested_by_name, reason, balance_before, balance_after,
    cancelled_by, cancelled_by_name
  ) values (
    v_admin, p_kind, p_operation_id, v_company, v_exchange, v_co_name,
    v_ex_name, v_ex_code, v_amount, v_ref, v_party,
    v_at, v_emp, case when v_emp is null then 'المدير' else coalesce(v_emp_name, '—') end,
    v_req_id, v_req_name, v_reason, v_before, v_after,
    v_admin, v_admin_name
  )
  returning id into v_id;

  -- Tell the employee whose operation it was.
  if v_emp is not null then
    insert into employee_messages (owner_id, sub_user_id, broadcast_id, title, body)
    values (
      v_admin, v_emp, gen_random_uuid(), 'تم إلغاء عملية',
      format(E'تم إلغاء عملية "%s" بقيمة %s$\nالسبب: %s',
             case p_kind when 'transfer' then 'بيع' else 'شراء' end,
             to_char(v_amount, 'FM999G999G990D00'), v_reason)
    );
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'balance_after', v_after);
end;
$$;
revoke all on function admin_cancel_operation(text, uuid, text, text, uuid) from public, anon;
grant execute on function admin_cancel_operation(text, uuid, text, text, uuid) to authenticated;

commit;
