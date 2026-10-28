import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';

beforeAll(() => {
  process.env.SESSION_SECRET = 'x'.repeat(48);
  process.env.SUPABASE_URL = 'https://example.supabase.co';
  process.env.SUPABASE_ANON_KEY = 'anon';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service';
});

function files(dir: string, out: string[] = []): string[] {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) files(p, out);
    else out.push(p);
  }
  return out;
}
const src = files('src').filter((f) => /\.(ts|tsx)$/.test(f));
const read = (f: string) => readFileSync(f, 'utf8');

describe('sealed cookies', () => {
  const sample = (typ: 'pending' | 'session') => ({
    typ,
    uid: 'u1',
    at: 'access',
    rt: 'refresh',
    sid: 's1',
    atExp: 123,
  });

  it('round-trips and is not readable', async () => {
    const { seal, unseal } = await import('../src/lib/session');
    const t = await seal(sample('session'), 60);
    expect(t).not.toContain('access');
    expect(await unseal(t, 'session')).toEqual(sample('session'));
  });

  it('a pending cookie never works as a session (and the reverse)', async () => {
    const { seal, unseal } = await import('../src/lib/session');
    const p = await seal(sample('pending'), 60);
    expect(await unseal(p, 'session')).toBeNull();
    const s = await seal(sample('session'), 60);
    expect(await unseal(s, 'pending')).toBeNull();
  });

  it('a changed or foreign cookie is refused', async () => {
    const { seal, unseal } = await import('../src/lib/session');
    const t = await seal(sample('session'), 60);
    const flipped = t.slice(0, -3) + (t.endsWith('AAA') ? 'BBB' : 'AAA');
    expect(await unseal(flipped, 'session')).toBeNull();
    expect(await unseal('garbage', 'session')).toBeNull();
    expect(await unseal(undefined, 'session')).toBeNull();
  });

  it('an expired cookie is refused', async () => {
    const { seal, unseal } = await import('../src/lib/session');
    const t = await seal(sample('session'), 1);
    await new Promise((r) => setTimeout(r, 2200));
    expect(await unseal(t, 'session')).toBeNull();
  });

  it('another secret cannot open it', async () => {
    const { seal } = await import('../src/lib/session');
    const t = await seal(sample('session'), 60);
    process.env.SESSION_SECRET = 'y'.repeat(48);
    const { unseal } = await import('../src/lib/session');
    expect(await unseal(t, 'session')).toBeNull();
    process.env.SESSION_SECRET = 'x'.repeat(48);
  });

  it('refuses a weak secret', async () => {
    const { env } = await import('../src/lib/env');
    process.env.SESSION_SECRET = 'short';
    expect(() => env.sessionSecret).toThrow();
    process.env.SESSION_SECRET = 'x'.repeat(48);
  });
});

describe('the code is the guard, not the screen', () => {
  it('every server action asks who is calling', () => {
    const actions = src.filter((f) => /actions\.ts$/.test(f) && !f.includes('login'));
    expect(actions.length).toBeGreaterThan(3);
    for (const f of actions) {
      const code = read(f);
      if (f.endsWith(join('(app)', 'actions.ts'))) continue; // logout: ends a session
      expect(code, f).toContain('requireStaff(');
    }
  });

  it('write actions need an administrating role', () => {
    for (const f of src.filter((f) => /(users|requests|notifications|updates)[\\/].*actions\.ts$/.test(f))) {
      expect(read(f), f).toMatch(/requireStaff\('super_admin', 'admin'\)/);
    }
    expect(read(src.find((f) => /staff[\\/]actions\.ts$/.test(f))!)).toMatch(
      /requireStaff\('super_admin'\)/,
    );
  });

  it('the service key is only imported by server code that needs it', () => {
    const users = src.filter((f) => read(f).includes('serviceClient'));
    for (const f of users) {
      expect(read(f).startsWith("'use client'"), f).toBe(false);
    }
    expect(users.map((f) => f.replace(/\\/g, '/')).sort()).toEqual(
      [
        'src/lib/supabase.ts',
        'src/app/login/actions.ts',
        'src/app/(app)/actions.ts',
        'src/app/(app)/staff/actions.ts',
      ].sort(),
    );
  });

  it('no secret reaches the browser', () => {
    for (const f of src) {
      expect(read(f), f).not.toMatch(/NEXT_PUBLIC_/);
    }
    const next = readFileSync('next.config.mjs', 'utf8');
    expect(next).toContain("frame-ancestors 'none'");
    expect(next).toContain("connect-src 'self'");
    expect(next).toContain('Strict-Transport-Security');
  });

  it('pages that change nothing are not reachable without the guard', () => {
    for (const f of src.filter((f) => /\(app\)[\\/].*page\.tsx$/.test(f))) {
      expect(read(f), f).toContain('requireStaff(');
    }
  });

  it('only the sign-in, health and install files are public', () => {
    const mw = read('src/middleware.ts');
    for (const open of ['/login', '/api/health', '/manifest.webmanifest', '/sw.js']) {
      expect(mw).toContain(`'${open}'`);
    }
    expect(mw).not.toContain("'/users'");
    expect(mw).toContain("path === '/verify'");
  });
});

describe('messages', () => {
  it('a refusal reads in Arabic and never leaks the raw message', async () => {
    const { explain } = await import('../src/lib/errors');
    const { DbError } = await import('../src/lib/supabase');
    expect(explain(new DbError('platform_forbidden'))).toContain('صلاحية');
    expect(explain(new DbError('relation "audit_log" does not exist'))).toBe('تعذّر تنفيذ العملية');
    expect(explain(new Error('secret internals'))).toBe('تعذّر تنفيذ العملية');
  });
});
