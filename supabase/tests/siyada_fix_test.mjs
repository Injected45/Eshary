import fs from 'node:fs';
import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, text, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(text), name, `got: ${e.message}`); }
}

const sql = fs.readFileSync(new URL('../manual/2026-10-28_fix_siyada_company_name.sql', import.meta.url), 'utf8');
const ID = 'bc393e4f-6172-42d8-a83b-7fa4adfaeb78';

async function setup(company, code = '3108', amount = 16000) {
  const db = await freshDb();
  const A = '11111111-1111-1111-1111-111111111111';
  await db.exec(`insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values ('${A}','a@x.ly','x','{}');
    insert into account_licenses (user_id, status, license_type) values ('${A}','active','lifetime') on conflict (user_id) do update set status='active';`);
  const co = (await db.query(`insert into companies (owner_id, name, start_ref) values ($1,'الرحالة','Rh0100') returning id`, [A])).rows[0];
  const ex = (await db.query(`insert into exchanges (company_id, name, balance, our_code) values ($1,'بهاروز', 50000,'2067') returning id`, [co.id])).rows[0];
  await db.exec(`insert into exchange_companies (owner_id, name, kind) values ('${A}','بهاروز','mine'), ('${A}','الصحراء','client')`);
  const t = (await as(db, A, (tx) => tx.query(
    `select * from record_transfer($1,$2,'كود 3108',$3,$4,$5,'Rh0101')`, [co.id, ex.id, company, code, amount]))).rows[0];
  await db.query(`update transfers set id = $1 where id = $2`, [ID, t.id]);
  return { db, A, ex };
}

console.log('— the correction');
{
  const { db, A, ex } = await setup('شركةالسياده');
  const bal = (await db.query(`select balance b from exchanges where id = $1`, [ex.id])).rows[0].b;
  await db.exec(sql);
  const t = (await db.query(`select * from transfers where id = $1`, [ID])).rows[0];
  ok(t.beneficiary_account_company === 'السيادة', 'the company on the operation is "السيادة"', t.beneficiary_account_company);
  ok(Number(t.amount) === 16000 && t.reference === 'Rh0101' && t.beneficiary_code === '3108' && t.status === 'archived',
    'amount, reference, code and status untouched');
  ok((await db.query(`select balance b from exchanges where id = $1`, [ex.id])).rows[0].b === bal, 'the balance did not move');
  const ec = (await db.query(`select name, kind from exchange_companies where owner_id = $1 and name = 'السيادة'`, [A])).rows;
  ok(ec.length === 1 && ec[0].kind === 'client', 'saved once in the customers list, as a customer company');
  const cl = (await db.query(`select name, company, code from clients where owner_id = $1`, [A])).rows;
  ok(cl.length === 1 && cl[0].name === 'كود 3108' && cl[0].company === 'السيادة' && cl[0].code === '3108', 'the party is saved', JSON.stringify(cl));
  const au = (await db.query(`select old_value o, new_value n from audit_log where kind = 'transfer_data_corrected'`)).rows;
  ok(au.length === 1 && au[0].o.beneficiary_account_company === 'شركةالسياده' && au[0].n.beneficiary_account_company === 'السيادة', 'one audit line with before and after');
  ok((await db.query(`select count(*)::int n from transfers`)).rows[0].n === 1, 'no operation was added or removed');

  console.log('— running it twice changes nothing more');
  await db.exec(sql);
  ok((await db.query(`select count(*)::int n from exchange_companies where name = 'السيادة'`)).rows[0].n === 1, 'still one company');
  ok((await db.query(`select count(*)::int n from clients`)).rows[0].n === 1, 'still one party');
  ok((await db.query(`select count(*)::int n from audit_log where kind = 'transfer_data_corrected'`)).rows[0].n === 1, 'still one audit line');
}

console.log('— the company already exists in the list');
{
  const { db, A } = await setup('شركةالسياده');
  await db.exec(`insert into exchange_companies (owner_id, name, kind) values ('${A}','السيـادة','client')`); // with a tatweel
  await db.exec(sql);
  ok((await db.query(`select count(*)::int n from exchange_companies where kind = 'client' and name like '%سي%'`)).rows[0].n === 1, 'no duplicate company');
}

console.log('— it refuses anything else');
{
  const { db } = await setup('شركة أخرى');
  await rejects(db.exec(sql), 'اسم الشركة الحالي غير متوقع', 'another company name');
}
{
  const { db } = await setup('شركةالسياده', '9999');
  await rejects(db.exec(sql), 'ليست العملية المقصودة', 'another code');
}
{
  const { db } = await setup('شركةالسياده', '3108', 15000);
  await rejects(db.exec(sql), 'ليست العملية المقصودة', 'another amount');
}
{
  const db = await freshDb();
  await rejects(db.exec(sql), 'العملية غير موجودة', 'no such operation');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
