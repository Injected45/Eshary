// Sets a new password for an ESHARI Admin staff account (when it is forgotten
// or refused). Run it through reset-admin-password.bat at the repo root: it
// asks for the e-mail and the new password. The password is typed here, never
// in a chat, and it is not stored anywhere but in Supabase.
//
// Only an account that is registered in platform_staff can be changed with
// this; a normal app user cannot. Its open sessions are ended.
import { createClient } from '@supabase/supabase-js';
import { existsSync, readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const envFile = new URL('../.env.local', import.meta.url);
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

function ask(question) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (a) => {
      rl.close();
      resolve(a.trim());
    });
  });
}

const fail = (msg) => {
  console.error(`\n${msg}`);
  process.exit(1);
};

const url = (process.env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
const key = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();
if (!url || !key) fail('admin-web\\.env.local needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');

const email = (process.env.RESET_EMAIL || (await ask('Staff e-mail: '))).toLowerCase();
const password = process.env.RESET_PASSWORD || (await ask('New password (12+ characters, it will be visible): '));
if (!email) fail('The e-mail is required.');
if (password.length < 12) fail('The password must be at least 12 characters.');

const svc = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

// find the user by e-mail (the list is small)
let user = null;
for (let page = 1; page <= 20 && !user; page++) {
  const { data, error } = await svc.auth.admin.listUsers({ page, perPage: 200 });
  if (error) fail(`Cannot read the users: ${error.message}`);
  user = data.users.find((u) => (u.email ?? '').toLowerCase() === email) ?? null;
  if (data.users.length < 200) break;
}
if (!user) fail('No account with this e-mail.');

const { data: staff, error: e1 } = await svc
  .from('platform_staff')
  .select('user_id, role, active')
  .eq('user_id', user.id)
  .maybeSingle();
if (e1) fail(`Cannot read platform_staff: ${e1.message}`);
if (!staff) fail('This account is not a platform staff account; nothing was changed.');

const { error: e2 } = await svc.auth.admin.updateUserById(user.id, { password });
if (e2) fail(`Cannot change the password: ${e2.message}`);

// end every open verified session of this account
await svc
  .from('platform_sessions')
  .update({ revoked_at: new Date().toISOString() })
  .eq('user_id', user.id)
  .is('revoked_at', null);

// prove it: sign in with the new password (no code is sent by this)
const anon = (process.env.SUPABASE_ANON_KEY ?? '').trim();
const r = await fetch(`${url}/auth/v1/token?grant_type=password`, {
  method: 'POST',
  headers: { apikey: anon, 'Content-Type': 'application/json' },
  body: JSON.stringify({ email, password }),
});
console.log(r.ok ? `\nDone. The password works for ${email} (${staff.role}).` : '\nChanged, but a test sign-in was refused - try the platform and tell me.');
console.log('Open http://localhost:8100 and sign in; the WhatsApp code will follow.');
