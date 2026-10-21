// One-time creation of the FIRST super admin of the ESHARI Admin platform.
//
// Easiest: double-click bootstrap-admin.bat at the repo root (it asks for each
// value). Or set BOOTSTRAP_EMAIL / BOOTSTRAP_NAME / BOOTSTRAP_PHONE /
// BOOTSTRAP_PASSWORD yourself. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY come
// from admin-web/.env.local.
//
// There is no default account and no default password: you choose both here,
// and the script refuses to run once a super admin exists (the database refuses
// too: platform_staff_add, "bootstrap_done").
//
// The WhatsApp number is proved the first time you sign in: the code goes to
// that number, and only someone holding it gets in.
import { createClient } from '@supabase/supabase-js';
import { existsSync, readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

// .env.local is read here too, so the script works without exporting anything
const envFile = new URL('../.env.local', import.meta.url);
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

function ask(question, { hidden = false } = {}) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) {
      const out = rl.output;
      rl._writeToOutput = (s) => {
        if (s.includes(question)) out.write(s);
        else if (/[\r\n]/.test(s)) out.write(s);
      };
    }
    rl.question(question, (a) => {
      rl.close();
      resolve(a.trim());
    });
  });
}

const get = async (key, question, opts) => {
  const v = (process.env[key] ?? '').trim();
  if (v) return v;
  const a = await ask(question, opts);
  if (!a) {
    console.error(`\n${key} is required.`);
    process.exit(1);
  }
  return a;
};

const url = (await get('SUPABASE_URL', 'Supabase URL: ')).replace(/\/+$/, '');
const key = await get('SUPABASE_SERVICE_ROLE_KEY', 'service_role key (Dashboard > Settings > API): ', { hidden: true });
const email = (await get('BOOTSTRAP_EMAIL', 'Admin e-mail: ')).toLowerCase();
const name = await get('BOOTSTRAP_NAME', 'Full name: ');
const phone = (await get('BOOTSTRAP_PHONE', 'WhatsApp number with country code (+218912345678): ')).replace(/[\s\-()]/g, '');
const password = await get('BOOTSTRAP_PASSWORD', 'Password (12+ characters, hidden): ', { hidden: true });

if (password.length < 12) {
  console.error('The password must be at least 12 characters.');
  process.exit(1);
}
if (!/^\+[1-9][0-9]{7,14}$/.test(phone)) {
  console.error('The phone must be international, e.g. +218912345678.');
  process.exit(1);
}

const svc = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

const { data: existing, error: e0 } = await svc
  .from('platform_staff')
  .select('user_id')
  .eq('role', 'super_admin')
  .limit(1);
if (e0) {
  console.error('Cannot read platform_staff - was migration 0077 applied?', e0.message);
  process.exit(1);
}
if (existing && existing.length > 0) {
  console.error('A super admin already exists. Add more staff from the platform (Staff accounts page).');
  process.exit(1);
}

const { data: created, error: e1 } = await svc.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
  user_metadata: { platform_staff: true },
});
if (e1 || !created.user) {
  console.error('Cannot create the login:', e1?.message ?? 'unknown');
  process.exit(1);
}

const { error: e2 } = await svc.rpc('platform_staff_add', {
  p_user: created.user.id,
  p_role: 'super_admin',
  p_name: name,
  p_phone: phone,
  p_by: null,
});
if (e2) {
  await svc.auth.admin.deleteUser(created.user.id).catch(() => {});
  console.error('Cannot register the super admin:', e2.message);
  process.exit(1);
}

console.log(`\nSuper admin created: ${email}`);
console.log('Open http://localhost:8000 and sign in; the first WhatsApp code proves the number.');
