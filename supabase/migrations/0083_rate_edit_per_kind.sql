-- 0083_rate_edit_per_kind.sql
-- The permission to type the exchange rate, split by kind of operation:
--   rate_edit_sell  the employee types the SELL rate of an exit
--   rate_edit_buy   the employee types the BUY rate of an entry
-- Without the one for that kind, the operation is saved at the administrator's
-- last rate of that kind (as before). The single key "rate_edit" of 0081 is
-- replaced: an employee who had it gets both, so nobody loses anything.
-- Needs 0081. Safe to run more than once.

begin;

-- superseded-guard: a later migration redefined what this file defines; running
-- it again would undo that, so it refuses.
do $$
begin
  if to_regclass('public.operation_costs') is not null then
    raise exception 'هذا الملف (0083) طُبّق سابقًا وجاءت بعده ترحيلات أحدث، وإعادة تشغيله تلغي إصلاحاتها. لم يتغير شيء.';
  end if;
end $$;

do $$
begin
  if to_regprocedure('public._operation_rate(text, numeric)') is null then
    raise exception 'شغّل الترحيل 0081 أولًا (سعر الصرف)، ثم هذا الملف. لم يتغير شيء.';
  end if;
end $$;

-- every key of the earlier migrations (0078 added clients_add), with rate_edit
-- of 0081 split in two
create or replace function _employee_permission_keys()
returns text[]
language sql
immutable
as $$
  select array['transfers_create', 'buys_create', 'view_own', 'view_all',
               'closings_own', 'closings_all', 'accounts_own', 'accounts_all',
               'party_letters', 'clients_add', 'rate_edit_sell', 'rate_edit_buy']
$$;

-- an employee who had rate_edit keeps typing both rates
update sub_users
   set permissions = (
         select coalesce(array_agg(distinct k order by k), '{}')
           from unnest(array_remove(permissions, 'rate_edit')
                       || array['rate_edit_sell', 'rate_edit_buy']) as k
       ),
       updated_at = now()
 where 'rate_edit' = any (permissions);

-- the rate an operation is saved with: the permission of ITS kind decides
create or replace function _operation_rate(p_kind text, p_rate numeric)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_last  numeric;
begin
  if p_rate is not null and p_rate <= 0 then
    raise exception 'rate_invalid' using errcode = 'P0001';
  end if;

  if current_employee_id() is not null
     and not employee_has_perm(
       case p_kind when 'sell' then 'rate_edit_sell' else 'rate_edit_buy' end
     ) then
    select rate into v_last
      from last_exchange_rates
     where owner_id = v_admin and kind = p_kind;
    if v_last is null and p_rate is not null then
      raise exception 'rate_not_set' using errcode = 'P0001';
    end if;
    return v_last;
  end if;

  if p_rate is not null and current_employee_id() is null then
    insert into last_exchange_rates (owner_id, kind, rate, updated_at)
    values (v_admin, p_kind, p_rate, now())
    on conflict (owner_id, kind)
      do update set rate = excluded.rate, updated_at = excluded.updated_at;
  end if;
  return round(p_rate, 4);
end;
$$;
revoke all on function _operation_rate(text, numeric) from public, anon, authenticated;

-- can_edit_sell / can_edit_buy for the screens; can_edit (both) stays for the
-- 1.0.6 build, which has one flag for both screens and so never offers a box
-- the database would then overrule.
create or replace function current_exchange_rates()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_admin uuid := effective_admin_id();
  v_emp   boolean := current_employee_id() is not null;
  v_sell  boolean;
  v_buy   boolean;
begin
  if v_admin is null then
    raise exception 'not_authenticated' using errcode = 'P0001';
  end if;
  v_sell := not v_emp or employee_has_perm('rate_edit_sell');
  v_buy  := not v_emp or employee_has_perm('rate_edit_buy');
  return jsonb_build_object(
    'sell', (select rate from last_exchange_rates where owner_id = v_admin and kind = 'sell'),
    'buy',  (select rate from last_exchange_rates where owner_id = v_admin and kind = 'buy'),
    'can_edit_sell', v_sell,
    'can_edit_buy',  v_buy,
    'can_edit',      v_sell and v_buy
  );
end;
$$;
revoke all on function current_exchange_rates() from public, anon;
grant execute on function current_exchange_rates() to authenticated;

commit;
