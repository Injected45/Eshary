-- 0065_stronger_device_key.sql
-- An employee's account is bound to ONE phone. Until now the "phone key" was the
-- Android build id (the same on every phone of one model and system version),
-- so a second, identical phone could sign in with the same code. The app now
-- sends a key derived from the phone's own Android ID (hashed, never the raw
-- ID): "NEW~OLD". NEW is the key from now on; OLD is the key the previous app
-- version stored, offered ONLY so that an employee already bound under the old
-- key is moved to the new one at their next sign-in, without being locked out
-- and without the administrator resetting anything. After that single sign-in
-- the old key no longer opens the account.
--
-- A first sign-in binds NEW. A key that matches neither NEW nor (once) OLD is
-- refused with device_mismatch, as before. Safe to run more than once.

begin;

create or replace function _device_new(p_sent text)
returns text
language sql
immutable
as $$ select nullif(btrim(split_part(coalesce(p_sent, ''), '~', 1)), '') $$;

create or replace function _device_old(p_sent text)
returns text
language sql
immutable
as $$ select nullif(btrim(split_part(coalesce(p_sent, ''), '~', 2)), '') $$;

-- The code + phone sign-in.
create or replace function employee_login(
  p_phone     text,
  p_code      text,
  p_device_id text
) returns table (
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  session_id      uuid
) language plpgsql security definer set search_path = public, extensions as $$
declare
  v_sub_user   sub_users;
  v_session_id uuid;
  v_phone      text := trim(coalesce(p_phone, ''));
  v_fails      integer;
  v_new        text := _device_new(p_device_id);
  v_old        text := _device_old(p_device_id);
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_new is null then
    raise exception 'device_id_required' using errcode = 'P0001';
  end if;

  select count(*) into v_fails
    from employee_login_failures f
   where f.phone = v_phone and f.at > now() - interval '15 minutes';
  if v_fails >= 5 then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;

  for v_sub_user in
    select * from sub_users
    where phone_number = v_phone
      and status = 'active'
  loop
    if v_sub_user.login_code_hash = crypt(p_code, v_sub_user.login_code_hash) then
      if v_sub_user.device_id is null then
        update sub_users set
          device_id = v_new,
          login_code_used = true,
          login_code_used_at = now(),
          last_login_at = now(),
          updated_at = now()
        where id = v_sub_user.id;
      elsif v_sub_user.device_id = v_new
         or (v_old is not null and v_sub_user.device_id = v_old) then
        -- the same phone; one still on the old key is moved to the new one
        update sub_users set
          device_id = v_new,
          last_login_at = now(),
          updated_at = now()
        where id = v_sub_user.id;
      else
        raise exception 'device_mismatch' using errcode = 'P0001';
      end if;

      update employee_sessions es set
        is_active = false,
        ended_at = now()
      where es.sub_user_id = v_sub_user.id and es.is_active;

      insert into employee_sessions (
        sub_user_id, anonymous_user_id, device_id
      ) values (
        v_sub_user.id, auth.uid(), v_new
      ) returning id into v_session_id;

      insert into employee_activity_logs (
        parent_admin_id, sub_user_id, session_id, event_type, device_id
      ) values (
        v_sub_user.parent_admin_id, v_sub_user.id, v_session_id, 'login', v_new
      );

      delete from employee_login_failures f where f.phone = v_phone;

      return query select
        v_sub_user.id,
        v_sub_user.parent_admin_id,
        v_sub_user.employee_name,
        v_session_id;
      return;
    end if;
  end loop;

  -- Wrong phone or code: count it (a raise would roll the count back) and
  -- return no rows; the app reports "invalid credentials".
  insert into employee_login_failures (phone) values (v_phone);
  delete from employee_login_failures f where f.at < now() - interval '1 day';
  return;
end;
$$;

-- The QR + WhatsApp-code sign-in.
create or replace function employee_login_qr(p_token text, p_device_id text)
returns table (
  sub_user_id     uuid,
  parent_admin_id uuid,
  employee_name   text,
  session_id      uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_t          employee_qr_tokens;
  v_su         sub_users;
  v_session_id uuid;
  v_new        text := _device_new(p_device_id);
  v_old        text := _device_old(p_device_id);
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  if v_new is null then
    raise exception 'device_id_required' using errcode = 'P0001';
  end if;

  select * into v_t
    from employee_qr_tokens t
   where t.token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex')
     and t.used_at is null
     and t.expires_at > now()
   for update;
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  select * into v_su
    from sub_users s
   where s.id = v_t.sub_user_id
     and s.status = 'active'
     and s.login_code_hash = v_t.code_hash
   for update;
  if not found then
    raise exception 'invalid_qr' using errcode = 'P0001';
  end if;

  -- The identity check: a code delivered to the registered phone was verified.
  if not exists (
    select 1 from employee_otps o
     where o.token_id = v_t.id
       and o.verified_at is not null
       and o.verified_at > now() - interval '10 minutes'
  ) then
    raise exception 'otp_required' using errcode = 'P0001';
  end if;

  if v_su.device_id is null then
    update sub_users s
       set device_id          = v_new,
           login_code_used    = true,
           login_code_used_at = now(),
           last_login_at      = now(),
           updated_at         = now()
     where s.id = v_su.id;
  elsif v_su.device_id = v_new
     or (v_old is not null and v_su.device_id = v_old) then
    update sub_users s
       set device_id     = v_new,
           last_login_at = now(),
           updated_at    = now()
     where s.id = v_su.id;
  else
    -- Raising rolls the whole call back, so the token stays unused.
    raise exception 'device_mismatch' using errcode = 'P0001';
  end if;

  update employee_qr_tokens t
     set used_at = now()
   where t.id = v_t.id;

  update employee_sessions es
     set is_active = false,
         ended_at  = now()
   where es.sub_user_id = v_su.id
     and es.is_active;

  insert into employee_sessions (sub_user_id, anonymous_user_id, device_id)
  values (v_su.id, auth.uid(), v_new)
  returning id into v_session_id;

  insert into employee_activity_logs (
    parent_admin_id, sub_user_id, session_id, event_type, device_id
  ) values (
    v_su.parent_admin_id, v_su.id, v_session_id, 'login', v_new
  );

  return query select
    v_su.id,
    v_su.parent_admin_id,
    v_su.employee_name,
    v_session_id;
end;
$$;

commit;
