import fs from 'node:fs';
import { freshDb, as } from './harness.mjs';

let pass = 0, fail = 0;
const ok = (c, m, extra = '') => { if (c) pass++; else { fail++; console.log('FAIL', m, extra); } };
async function rejects(p, code, name) {
  try { await p; ok(false, name, '(no error)'); }
  catch (e) { ok(e.message.includes(code), name, `got: ${e.message}`); }
}

const A = '11111111-1111-1111-1111-111111111111';
const PLATFORM = '22222222-2222-2222-2222-222222222222';
const C = '55555555-5555-5555-5555-555555555555';
const n = (v) => (v === null || v === undefined ? null : Number(v));

const db = await freshDb({ upTo: 92 }); // a sale paid in cash from the account's dollars: 0093 sells from the cash book only
const q = async (sql, p) => (await db.query(sql, p)).rows;
await db.exec(`
  insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values
    ('${A}', 'a@x.ly', extensions.crypt('pass-a', extensions.gen_salt('bf')), '{}'),
    ('${PLATFORM}', 'p@x.ly', 'x', '{}');
  insert into account_licenses (user_id, status, license_type) values
    ('${A}', 'active', 'lifetime') on conflict (user_id) do update set status = 'active';
  insert into account_licenses (user_id, status, license_type, is_admin) values
    ('${PLATFORM}', 'active', 'lifetime', true) on conflict (user_id) do update set is_admin = true;`);

const cA = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'شركة', 'RH0100') returning id`, [A]))[0].id;
const ex = (await as(db, A, (tx) => tx.query(`select * from admin_open_account($1,'حساب',10000,null,null,7)`, [cA]))).rows[0];
const sell = (usd = 10) => as(db, A, (tx) => tx.query(`select * from record_transfer($1,$2,'م',null,null,$3,'',7.3,'cash')`, [cA, ex.id, usd])).then((r) => r.rows[0]);
const buy = (usd) => as(db, A, (tx) => tx.query(`select * from record_currency_buy($1,$2,null,null,$3,7.1,null,'','cash')`, [cA, ex.id, usd])).then((r) => r.rows[0]);
const restore = (b, o = A) => as(db, PLATFORM, (tx) => tx.query(`select admin_restore_owner($1,$2) r`, [b, o])).then((r) => r.rows[0].r);
const bal = async () => n((await q(`select balance from exchanges where id = $1`, [ex.id]))[0].balance);

console.log('— 1) wipe, then restore the wipe\'s own copy: the numbering does not jump');
await sell(); await sell(); await sell();          // RH0100..RH0102
const w = (await as(db, A, (tx) => tx.query(`select owner_wipe_operations('pass-a') r`))).rows[0].r;
ok(w.ok === true, 'wiped');
await buy(100);                                    // the wipe left the balance at 0
ok((await sell()).reference === 'RH0103', 'after the wipe the numbering goes on: RH0103');
await restore(w.backup_id);
ok((await q(`select count(*)::int k from transfers where owner_id = $1`, [A]))[0].k === 3, 'the three exits are back');
const t = await sell();
ok(t.reference === 'RH0104', 'after restoring the wipe\'s copy: RH0104 (RH0103 was already sent), not RH0106', t.reference);

console.log('— 3) restoring an OLDER copy never goes back');
const older = (await q(`select _save_backup('manual') id`))[0].id;   // 4 active: ..RH0104
await sell(); await sell();                                          // RH0105, RH0106
await restore(older);
ok((await q(`select count(*)::int k from transfers where owner_id = $1 and cancelled_at is null`, [A]))[0].k === 4, 'back to the 4 exits of the copy');
const t2 = await sell();
ok(t2.reference === 'RH0107', 'the next is RH0107: RH0105 and RH0106 were already sent', t2.reference);

console.log('— 2) a copy without the subscriber is refused, nothing deleted');
await db.exec(`insert into auth.users (id, email, encrypted_password) values ('${C}', 'c@x.ly', 'x');`);
await q(`insert into companies (owner_id, name, start_ref) values ($1, 'جديدة', 'C1')`, [C]);
await rejects(restore(older, C), 'owner_not_in_backup', 'refused');
ok((await q(`select count(*)::int k from companies where owner_id = $1`, [C]))[0].k === 1, 'C still has his company');

console.log('— 4) an account already below zero may come back up, never further down');
await db.transaction(async (tx) => {
  await tx.exec(`select set_config('eshary.restoring', 'on', true)`);
  await tx.query(`update exchanges set balance = -50 where id = $1`, [ex.id]);
});
ok((await bal()) === -50, 'an old account at −50');
await buy(20);
ok((await bal()) === -30, 'an entry of 20 is taken: −30');
await rejects(sell(1), 'insufficient_balance', 'an exit is refused');
await rejects(q(`update exchanges set balance = -40 where id = $1`, [ex.id]), 'insufficient_balance', 'and it never goes further down');
await buy(30);
ok((await bal()) === 0, 'back to zero');

console.log('— 6) past RH9999 the number grows, never cut');
const cB = (await q(`insert into companies (owner_id, name, start_ref) values ($1, 'ب', 'X99') returning id`, [A]))[0].id;
const nb = (await as(db, A, (tx) => tx.query(`select next_reference($1) r`, [cB]))).rows[0].r;
const active = (await q(`select count(*)::int k from transfers where owner_id = $1 and cancelled_at is null`, [A]))[0].k;
ok(nb === `X${99 + active}`, `X99 + ${active} active = X${99 + active}, three digits, not cut to two`, nb);

console.log('— the replaced files refuse to run again');
const run = (f) => db.exec('set search_path = public, extensions;\n' + fs.readFileSync(new URL(`../migrations/${f}`, import.meta.url), 'utf8')
  .replace(/create extension if not exists pgcrypto;/g, ''));
// each file opens its own transaction; the refusal leaves it aborted
for (const f of ['0086_adjustments_and_dinar_treasury.sql', '0087_operations_integrity.sql', '0088_restore_one_subscriber.sql']) {
  await rejects(run(f), 'لا تشغّله مرة أخرى', f);
  await db.exec('rollback').catch(() => {});
}
// since 0091 it refuses too (it would drop the customers' accounts from the wipe)
await rejects(run('0089_integrity_review_fixes.sql'), 'لا تشغّله مرة أخرى', '0089 after 0091');
await db.exec('rollback').catch(() => {});


console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
