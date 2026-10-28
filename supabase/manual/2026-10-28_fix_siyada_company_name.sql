-- One-off correction (2026-10-28), run once in the Supabase SQL Editor.
--
-- The exit Rh0101 (16,000$, executed by the employee "بالعيد") has the
-- beneficiary's company typed as "شركةالسياده" (no space). This makes it
-- "السيادة" (without the word "شركة"), and saves the company in the customers'
-- list and the party "كود 3108" in the saved clients, so the next operation can
-- pick them instead of typing them.
--
-- It changes ONLY the beneficiary's company text of that one operation. The
-- amount, the account, the balance, the reference and the time are untouched,
-- and an audit line records what was changed. Safe to run twice (the second run
-- changes nothing and says so).

do $$
declare
  v_id    uuid := 'bc393e4f-6172-42d8-a83b-7fa4adfaeb78';
  v_new   text := 'السيادة';
  v_owner uuid;
  v_old   text;
  v_code  text;
  v_amt   numeric;
  v_n     integer := 0;
  v_co    integer := 0;
  v_party integer := 0;
begin
  select t.owner_id, t.beneficiary_account_company, t.beneficiary_code, t.amount
    into v_owner, v_old, v_code, v_amt
    from transfers t
   where t.id = v_id;

  if v_owner is null then
    raise exception 'العملية غير موجودة — لم يتغيّر شيء';
  end if;
  -- safety: only this operation (16,000$ to code 3108) and only this company
  if v_amt is distinct from 16000 or coalesce(v_code, '') <> '3108' then
    raise exception 'هذه ليست العملية المقصودة (المبلغ %، الكود %) — لم يتغيّر شيء', v_amt, v_code;
  end if;
  if v_old is null or v_old not like '%سياد%' then
    raise exception 'اسم الشركة الحالي غير متوقع: % — لم يتغيّر شيء', v_old;
  end if;

  -- 1) the name on the operation
  if v_old <> v_new then
    update transfers
       set beneficiary_account_company = v_new
     where id = v_id;
    get diagnostics v_n = row_count;
    insert into audit_log (kind, subject_type, subject_id, old_value, new_value, note)
    values ('transfer_data_corrected', 'transfer', v_id::text,
            jsonb_build_object('beneficiary_account_company', v_old),
            jsonb_build_object('beneficiary_account_company', v_new),
            'تصحيح اسم الشركة المستفيدة فقط (بلا مسافة)');
  end if;

  -- 2) the company in the customers' list (not mine), once
  insert into exchange_companies (owner_id, name, kind)
  select v_owner, v_new, 'client'
   where not exists (
     select 1 from exchange_companies e
      where e.owner_id = v_owner and replace(_party_key(e.name), 'ـ', '') = replace(_party_key(v_new), 'ـ', ''));
  get diagnostics v_co = row_count;

  -- 3) the saved client: "كود 3108" at "السيادة", once
  insert into clients (owner_id, name, company, code)
  select v_owner, 'كود 3108', v_new, '3108'
   where not exists (
     select 1 from clients c
      where c.owner_id = v_owner
        and replace(_party_key(c.company), 'ـ', '') = replace(_party_key(v_new), 'ـ', '')
        and _party_key(c.code) = '3108');
  get diagnostics v_party = row_count;

  raise notice 'تم: العملية المعدّلة=% ، شركة جديدة في قائمة العملاء=% ، عميل جديد محفوظ=%',
    v_n, v_co, v_party;
end;
$$;
