import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const db = await freshDb();
const q = async (sql, p) => (await db.query(sql, p)).rows;

const ADMIN = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const A_WITH = '33333333-3333-3333-3333-333333333333';
const A_WITHOUT = '44444444-4444-4444-4444-444444444444';
const A_OTHER = '55555555-5555-5555-5555-555555555555';
await db.exec(`
  insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values
    ('${ADMIN}', 'a@x.ly', 'x', '{}'), ('${OTHER}', 'o@x.ly', 'x', '{}'),
    ('${A_WITH}', null, null, '{}'), ('${A_WITHOUT}', null, null, '{}'), ('${A_OTHER}', null, null, '{}');
  insert into account_licenses (user_id, status, license_type) values
    ('${ADMIN}', 'active', 'lifetime'), ('${OTHER}', 'active', 'lifetime')
    on conflict (user_id) do update set status = 'active';
`);
const emp = async (parent, name, phone, perms) => (await q(
  `insert into sub_users (parent_admin_id, employee_name, phone_number, login_code_hash, permissions)
   values ($1, $2, $3, 'x', $4::text[]) returning id`, [parent, name, phone, perms]))[0];
const withP = await emp(ADMIN, 'له الصلاحية', '0911111111', ['buys_create', 'clients_add']);
const without = await emp(ADMIN, 'بلا صلاحية', '0922222222', ['buys_create']);
const other = await emp(OTHER, 'موظف مدير آخر', '0933333333', ['buys_create', 'clients_add']);
await q(`insert into employee_sessions (sub_user_id, anonymous_user_id, device_id) values ($1,$2,'d1'),($3,$4,'d2'),($5,$6,'d3')`,
  [withP.id, A_WITH, without.id, A_WITHOUT, other.id, A_OTHER]);

const add = (uid, ...args) =>
  as(db, uid, (tx) => tx.query(`select * from employee_add_party($1,$2,$3,$4)`, args)).then((r) => r.rows[0]);

console.log('— the key is accepted by the database');
const keys = (await q(`select _employee_permission_keys() k`))[0].k;
ok(keys.includes('clients_add') && keys.includes('party_letters') && keys.length >= 10, 'all ten keys still there (later migrations may add more)', JSON.stringify(keys));
await as(db, ADMIN, (tx) => tx.query(`select admin_set_employee_permissions($1, array['buys_create','clients_add'])`, [without.id]));
ok((await q(`select permissions p from sub_users where id = $1`, [without.id]))[0].p.includes('clients_add'), 'the administrator can grant it');
await as(db, ADMIN, (tx) => tx.query(`select admin_set_employee_permissions($1, array['buys_create'])`, [without.id]));
ok(!(await q(`select permissions p from sub_users where id = $1`, [without.id]))[0].p.includes('clients_add'), 'and take it back');

console.log('— an employee with the permission adds a party for THEIR administrator');
const p1 = await add(A_WITH, 'عميل جديد', 'شركة الصحراء', '5521', ' TRC ');
ok(p1.owner_id === ADMIN, 'owned by the administrator, not the employee', p1.owner_id);
ok(p1.name === 'عميل جديد' && p1.company === 'شركة الصحراء' && p1.code === '5521' && p1.ref_prefix === 'TRC', 'fields saved, letters trimmed', JSON.stringify(p1));
const p2 = await add(A_WITH, 'بلا شركة', null, null, null);
ok(p2.company === null && p2.code === null && p2.ref_prefix === null, 'a party with only a name');
const p3 = await add(A_WITH, 'كود 77', '  ', '77', '');
ok(p3.company === null, 'blank company becomes none');
ok((await as(db, ADMIN, (tx) => tx.query(`select count(*)::int n from clients`))).rows[0].n === 3, 'the administrator sees all three');
ok((await as(db, OTHER, (tx) => tx.query(`select count(*)::int n from clients`))).rows[0].n === 0, 'another administrator sees none');

console.log('— the same code at the same company is refused, at another company it is fine');
await rejects(add(A_WITH, 'مكرر', 'شركة الصحراء', '5521', null), 'party_code_exists', 'duplicate code on one company');
const p4 = await add(A_WITH, 'نفس الكود', 'شركة النور', '5521', null);
ok(p4.code === '5521', 'same code, other company');

console.log('— everyone else is refused');
await rejects(add(A_WITHOUT, 'x', null, null, null), 'permission_denied', 'no permission');
await rejects(as(db, ADMIN, (tx) => tx.query(`select employee_add_party('x', null, null, null)`)), 'not_authorized', 'the administrator inserts directly');
await rejects(add(A_WITH, '   ', null, null, null), 'party_name_invalid', 'a name is required');
await rejects(add(A_WITH, 'x'.repeat(121), null, null, null), 'party_name_invalid', 'name too long');
await rejects(add(A_WITH, 'x', 'c'.repeat(121), null, null), 'party_text_too_long', 'company too long');
await rejects(add(A_WITH, 'x', null, null, 'L'.repeat(21)), 'letters_too_long', 'letters too long');
await rejects(as(db, '66666666-6666-6666-6666-666666666666', (tx) => tx.query(`select employee_add_party('x', null, null, null)`)), 'not_authorized', 'a user with no employee session');
const before = (await q(`select count(*)::int n from clients`))[0].n;
ok(before === 4, 'nothing extra was written', String(before));

console.log('— the employee has no other way to write a party');
const ins = await as(db, A_WITH, (tx) => tx.query(`insert into clients (owner_id, name) values ($1, 'مباشر') returning id`, [ADMIN])).catch(() => ({ rows: [] }));
ok(ins.rows.length === 0, 'no direct insert');
const upd = await as(db, A_WITH, (tx) => tx.query(`update clients set name = 'تغيير' where id = $1 returning id`, [p1.id])).catch(() => ({ rows: [] }));
ok(upd.rows.length === 0, 'no direct update');
const del = await as(db, A_WITH, (tx) => tx.query(`delete from clients where id = $1 returning id`, [p1.id])).catch(() => ({ rows: [] }));
ok(del.rows.length === 0, 'no direct delete');
ok((await q(`select name from clients where id = $1`, [p1.id]))[0].name === 'عميل جديد', 'unchanged');

console.log('— a blocked administrator licence stops it');
await db.exec(`update account_licenses set status = 'blocked' where user_id = '${ADMIN}'`);
await rejects(add(A_WITH, 'بعد الإيقاف', null, null, null), 'license_inactive', 'blocked account');
await db.exec(`update account_licenses set status = 'active' where user_id = '${ADMIN}'`);

console.log('— the earlier permission still works (0071)');
await q(`update sub_users set permissions = array['buys_create','party_letters'] where id = $1`, [withP.id]);
await as(db, A_WITH, (tx) => tx.query(`select employee_set_party_letters($1, 'ABC')`, [p1.id]));
ok((await q(`select ref_prefix r from clients where id = $1`, [p1.id]))[0].r === 'ABC', 'party_letters unchanged');

console.log('— running the file twice is harmless');
const fs = await import('node:fs');
await db.exec(fs.readFileSync(new URL('../migrations/0078_employee_add_party.sql', import.meta.url), 'utf8'));
ok(true, 'idempotent');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
