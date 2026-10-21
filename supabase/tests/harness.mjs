import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MIG = fileURLToPath(new URL('../migrations', import.meta.url));

export async function freshDb({ upTo = Infinity } = {}) {
  const db = new PGlite({ extensions: { pgcrypto, uuid_ossp } });
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create role supabase_auth_admin nologin;
    create schema extensions;
    create extension pgcrypto schema extensions;
    create extension "uuid-ossp" schema extensions;
    alter database template1 set search_path = public, extensions;
    set search_path = public, extensions;
    create schema auth;
    create table auth.users (
      id uuid primary key default extensions.gen_random_uuid(),
      email text, phone text,
      encrypted_password text,
      raw_user_meta_data jsonb default '{}'::jsonb,
      raw_app_meta_data jsonb default '{}'::jsonb,
      is_anonymous boolean default false,
      email_confirmed_at timestamptz, last_sign_in_at timestamptz,
      created_at timestamptz default now(), updated_at timestamptz default now()
    );
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.role() returns text language sql stable as
      $$ select current_setting('request.jwt.claim.role', true) $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    grant usage on schema auth, extensions, public to anon, authenticated, service_role;
    create schema net;
    create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
      headers jsonb default '{}', timeout_milliseconds int default 1000) returns bigint
      language sql as $$ select 1::bigint $$;
    create table net._http_response (id bigint primary key, status_code int, error_msg text);
    create publication supabase_realtime;
    alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
    alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  `);
  const files = fs.readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) {
    const n = parseInt(f.slice(0, 4), 10);
    if (n > upTo) break;
    let sql = fs.readFileSync(path.join(MIG, f), 'utf8');
    if (process.env.VARIANT) {
      // what a copy-paste through a browser can do: no comment-only lines,
      // Windows line endings, extra trailing spaces
      sql = sql.replace(/^[ \t]*--.*$/gm, '').replace(/\n/g, '  \r\n');
    }
    sql = sql.replace(/create extension if not exists pg_net;/g, '')
             .replace(/create extension if not exists pgcrypto;/g, '');
    try {
      await db.exec('set search_path = public, extensions;\n' + sql);
    } catch (e) {
      throw new Error(`${f}: ${e.message}`);
    }
  }
  return db;
}

// Run `fn` as an authenticated user (RLS applies) with auth.uid() = uid.
export async function as(db, uid, fn) {
  return db.transaction(async (tx) => {
    await tx.exec(`set local role authenticated; select set_config('request.jwt.claim.sub', '${uid}', true);`);
    return fn(tx);
  });
}
