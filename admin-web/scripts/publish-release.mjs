// Publishes the APKs built by build-apk.bat as an update every installed app
// offers (a blocking "تحديث إلزامي" screen), so nobody is sent an APK again.
//
//   publish-update.bat                         (asks for the notes)
//   node scripts/publish-release.mjs --notes "ما الجديد"  [--optional] [--dry-run]
//   node scripts/publish-release.mjs --list
//   node scripts/publish-release.mjs --withdraw 12     (the app ignores build 12)
//   node scripts/publish-release.mjs --restore 12
//
// What it does, in this order (it stops at the first problem and publishes
// nothing half-way):
//   1. reads APK/build.json (written by build-apk.bat) and checks that
//      APK/Eshary-64.apk and APK/Eshary-32.apk are the files of that build;
//   2. uploads both to the public Storage bucket "app-releases" (build/...);
//   3. downloads them back and compares the SHA-256, so a broken upload is
//      never offered;
//   4. only then inserts the release row. The apps see it on their next check.
//
// Needs admin-web/.env.local (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY) and
// migration 0079. The service key stays on this computer.
import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { createInterface } from 'node:readline';

const root = new URL('../../', import.meta.url);
const envFile = new URL('../.env.local', import.meta.url);
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

const BUCKET = 'app-releases';
const FILES = [
  { abi: 'arm64-v8a', file: 'Eshary-64.apk' },
  { abi: 'armeabi-v7a', file: 'Eshary-32.apk' },
];

const fail = (msg) => {
  console.error(`\n✗ ${msg}`);
  process.exit(1);
};
const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const value = (n) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : undefined;
};

const url = (process.env.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
const key = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();
if (!url || !key) fail('admin-web\\.env.local needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
const svc = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

async function listReleases() {
  const { data, error } = await svc
    .from('app_releases')
    .select('build_number, version_name, mandatory, is_active, created_at')
    .order('build_number', { ascending: false })
    .limit(15);
  if (error) fail(`Cannot read app_releases (was migration 0079 applied?): ${error.message}`);
  if (!data.length) console.log('No release published yet.');
  for (const r of data) {
    console.log(
      `build ${String(r.build_number).padEnd(5)} ${r.version_name.padEnd(10)} ` +
        `${r.mandatory ? 'mandatory' : 'optional '} ${r.is_active ? 'ACTIVE   ' : 'withdrawn'} ${r.created_at.slice(0, 16)}`,
    );
  }
}

async function setActive(build, active) {
  const { data, error } = await svc
    .from('app_releases')
    .update({ is_active: active })
    .eq('platform', 'android')
    .eq('build_number', Number(build))
    .select('build_number');
  if (error) fail(error.message);
  if (!data?.length) fail(`No release with build ${build}.`);
  console.log(`✓ build ${build} is now ${active ? 'ACTIVE' : 'withdrawn'}.`);
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

if (flag('--list')) {
  await listReleases();
  process.exit(0);
}
if (value('--withdraw')) {
  await setActive(value('--withdraw'), false);
  process.exit(0);
}
if (value('--restore')) {
  await setActive(value('--restore'), true);
  process.exit(0);
}

// ---- 1. what was built -------------------------------------------------
const buildFile = new URL('APK/build.json', root);
if (!existsSync(buildFile)) fail('APK\\build.json is missing: run build-apk.bat first.');
const built = JSON.parse(readFileSync(buildFile, 'utf8'));
if (!Number.isInteger(built.build) || built.build < 1 || !built.versionName) {
  fail('APK\\build.json is not valid: run build-apk.bat again.');
}

const files = [];
for (const f of FILES) {
  const path = new URL(`APK/${f.file}`, root);
  if (!existsSync(path)) fail(`APK\\${f.file} is missing: run build-apk.bat first.`);
  const buf = readFileSync(path);
  if (buf.length < 5_000_000) fail(`APK\\${f.file} is too small (${buf.length} bytes): not a real build.`);
  // a file older than the build record was left from another build
  if (statSync(path).mtimeMs + 5 * 60_000 < new Date(built.builtAt).getTime()) {
    fail(`APK\\${f.file} is older than the build record: run build-apk.bat again.`);
  }
  files.push({ ...f, buf, sha: sha256(buf) });
}

const { data: existing, error: e0 } = await svc
  .from('app_releases')
  .select('build_number')
  .eq('platform', 'android')
  .gte('build_number', built.build);
if (e0) fail(`Cannot read app_releases (was migration 0079 applied?): ${e0.message}`);
if (existing?.length) {
  fail(
    `Build ${built.build} (or a newer one) is already published. ` +
      'Run build-apk.bat again (it raises the build number), then publish.',
  );
}

let notes = value('--notes');
if (notes === undefined && !flag('--dry-run')) {
  notes = await ask('What is new (shown to the users, one or two lines; Enter for the default): ');
}
notes = (notes || 'تحديث جديد: تحسينات وإصلاحات').slice(0, 1000);
const mandatory = !flag('--optional');

console.log(`\nBuild ${built.build}  (${built.versionName})  ${mandatory ? 'MANDATORY' : 'optional'}`);
for (const f of files) console.log(`  ${f.file}  ${(f.buf.length / 1048576).toFixed(1)} MB  sha256 ${f.sha.slice(0, 16)}…`);
console.log(`  notes: ${notes}`);
if (flag('--dry-run')) {
  console.log('\n(dry run: nothing was uploaded)');
  process.exit(0);
}

// ---- 2. upload ----------------------------------------------------------
const manifest = {};
for (const f of files) {
  const path = `${built.build}/${f.file}`;
  process.stdout.write(`Uploading ${path} … `);
  const { error } = await svc.storage.from(BUCKET).upload(path, f.buf, {
    contentType: 'application/vnd.android.package-archive',
    upsert: false,
  });
  if (error) fail(`upload failed: ${error.message} (was migration 0079 applied, so the bucket exists?)`);
  const publicUrl = `${url}/storage/v1/object/public/${BUCKET}/${path}`;

  // ---- 3. read it back exactly as a phone would ---------------------------
  const res = await fetch(publicUrl);
  if (!res.ok) fail(`the uploaded file cannot be downloaded (${res.status}): ${publicUrl}`);
  const back = Buffer.from(await res.arrayBuffer());
  if (sha256(back) !== f.sha) fail(`the downloaded copy of ${f.file} differs from the file: nothing was published.`);
  console.log('ok (downloaded back, checksum matches)');
  manifest[f.abi] = { url: publicUrl, sha256: f.sha, size: f.buf.length };
}

// ---- 4. publish ---------------------------------------------------------
const { error: e1 } = await svc.from('app_releases').insert({
  platform: 'android',
  build_number: built.build,
  version_name: built.versionName,
  mandatory,
  notes,
  files: manifest,
  is_active: true,
});
if (e1) fail(`could not publish: ${e1.message}`);

console.log(`\n✓ Published build ${built.build}. Every phone offers it on its next check`);
console.log('  (when the app opens or comes back to the screen).');
console.log('  Withdraw it with:  node scripts/publish-release.mjs --withdraw ' + built.build);
