import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };

const ADMIN = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';

async function setup(db) {
  await db.exec(`
    insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values
      ('${ADMIN}', 'a@x.ly', extensions.crypt('pass-1234', extensions.gen_salt('bf')), '{}'),
      ('${OTHER}', 'o@x.ly', 'x', '{}');
    insert into account_licenses (user_id, status, license_type) values
      ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
      on conflict (user_id) do update set status = 'active';
  `);
  const company = async (owner, name, start) => (await db.query(
    `insert into companies (owner_id, name, start_ref) values ($1, $2, $3) returning id`, [owner, name, start])).rows[0].id;
  const exchange = async (companyId) => (await db.query(
    `insert into exchanges (company_id, name, balance) values ($1, 'صرافة', 1000000) returning id`, [companyId])).rows[0].id;
  const c1 = await company(ADMIN, 'بهاروز', 'RH0100');
  const x1 = await exchange(c1);
  return { c1, x1, company, exchange };
}

const next = (db, companyId, uid = ADMIN) =>
  as(db, uid, (tx) => tx.query(`select next_reference($1) r`, [companyId])).then((r) => r.rows[0].r);
// a transfer saved the way the app saves it: number from next_reference, then record_transfer
const send = async (db, companyId, exchangeId, amount = 100) => {
  const ref = await next(db, companyId);
  const row = await as(db, ADMIN, (tx) => tx.query(
    `select * from record_transfer($1, $2, 'مستفيد', null, null, $3, $4)`, [companyId, exchangeId, amount, ref]));
  return row.rows[0];
};
const cancel = (db, id) => as(db, ADMIN, (tx) => tx.query(
  `select admin_cancel_operation('transfer', $1, 'خطأ في البيانات', 'pass-1234')`, [id]));

{
  console.log('— the last transfer cancelled: the next one takes its number');
  const db = await freshDb();
  const { c1, x1 } = await setup(db);
  ok(await next(db, c1) === 'RH0100', 'the first number is the start number');
  const t0 = await send(db, c1, x1);
  const t1 = await send(db, c1, x1);
  const t2 = await send(db, c1, x1);
  ok([t0, t1, t2].map((t) => t.reference).join() === 'RH0100,RH0101,RH0102', 'in sequence', [t0, t1, t2].map((t) => t.reference).join());
  await cancel(db, t2.id);
  ok((await db.query(`select cancelled_at from transfers where id = $1`, [t2.id])).rows[0].cancelled_at, 'RH0102 is cancelled (the row stays)');
  ok(await next(db, c1) === 'RH0102', 'the next transfer is RH0102 again');
  const t3 = await send(db, c1, x1);
  ok(t3.reference === 'RH0102', 'saved as RH0102');
  ok(await next(db, c1) === 'RH0103', 'then RH0103');
  const both = (await db.query(`select reference, cancelled_at is not null c from transfers where reference = 'RH0102' order by created_at`)).rows;
  ok(both.length === 2 && both[0].c && !both[1].c, 'one cancelled RH0102 and one active RH0102', JSON.stringify(both));

  console.log('— two cancelled in a row: both numbers come back');
  const t4 = await send(db, c1, x1);
  const t5 = await send(db, c1, x1);
  ok(t4.reference === 'RH0103' && t5.reference === 'RH0104', 'RH0103, RH0104');
  await cancel(db, t5.id);
  await cancel(db, t4.id);
  ok(await next(db, c1) === 'RH0103', 'next is RH0103');

  console.log('— an earlier one cancelled: never back, never a repeat');
  const t6 = await send(db, c1, x1); // RH0103
  const t7 = await send(db, c1, x1); // RH0104
  const t8 = await send(db, c1, x1); // RH0105
  ok([t6, t7, t8].map((t) => t.reference).join() === 'RH0103,RH0104,RH0105', 'RH0103..RH0105', [t6, t7, t8].map((t) => t.reference).join());
  await cancel(db, t6.id);
  ok(await next(db, c1) === 'RH0106', 'after cancelling RH0103 (not the last) the next is RH0106');
  const active = (await db.query(`select reference from transfers where cancelled_at is null`)).rows.map((r) => r.reference);
  ok(!active.includes(await next(db, c1)), 'not a number an active transfer has');
  await cancel(db, t1.id); // RH0101, long before
  ok(await next(db, c1) === 'RH0106', 'still RH0106');
  console.log(`   ${pass} passed so far`);
}

{
  console.log('— with no cancellation the result is the old formula exactly');
  const db = await freshDb();
  const { c1, x1, company, exchange } = await setup(db);
  const c2 = await company(ADMIN, 'شركة ثانية', 'KD500');
  const x2 = await exchange(c2);
  await send(db, c1, x1); // RH0100
  await send(db, c2, x2); // KD501 (counts across companies, as project_web.html:711)
  ok(await next(db, c1) === 'RH0102', 'the count still spans all companies', await next(db, c1));
  ok(await next(db, c2) === 'KD502', 'the other company too', await next(db, c2));
  const c3 = await company(ADMIN, 'بلا أرقام', 'ABC');
  ok(await next(db, c3) === 'ABC003', 'a start with no digits: <start>003 after two transfers', await next(db, c3));
  const c4 = await company(ADMIN, 'أصفار', '000');
  ok(await next(db, c4) === '002', 'a start of only digits', await next(db, c4));

  console.log('— a lower start number never brings back a used number');
  await db.query(`update companies set start_ref = 'RH0050' where id = $1`, [c1]);
  ok(await next(db, c1) === 'RH0101', 'goes on after RH0100, not RH0052', await next(db, c1));

  console.log('— only the administrator of the company');
  let err = '';
  try { await next(db, c1, OTHER); } catch (e) { err = e.message; }
  ok(err.includes('not_authorized'), 'another administrator is refused', err);
}

{
  console.log('— running the file twice is harmless');
  const db = await freshDb();
  const fs = await import('node:fs');
  const sql = fs.readFileSync(new URL('../migrations/0080_reference_skips_cancelled.sql', import.meta.url), 'utf8');
  await db.exec('set search_path = public, extensions;\n' + sql);
  const { c1, x1 } = await setup(db);
  const t = await send(db, c1, x1);
  ok(t.reference === 'RH0100', 'works after a second run');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
