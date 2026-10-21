// Server-side settings. Read lazily so a missing value gives a clear message
// (and the build does not need them).
function need(name: string): string {
  const v = process.env[name];
  if (!v || !v.trim()) {
    throw new Error(`Missing environment variable ${name}`);
  }
  return v.trim();
}

export const env = {
  get supabaseUrl() {
    return need('SUPABASE_URL').replace(/\/+$/, '');
  },
  get anonKey() {
    return need('SUPABASE_ANON_KEY');
  },
  get serviceKey() {
    return need('SUPABASE_SERVICE_ROLE_KEY');
  },
  get sessionSecret() {
    const s = need('SESSION_SECRET');
    if (s.length < 32) throw new Error('SESSION_SECRET must be at least 32 characters');
    return s;
  },
  get isProd() {
    return process.env.NODE_ENV === 'production';
  },
};
