import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env } from './env';

const noSession = { persistSession: false, autoRefreshToken: false } as const;

/** Password sign-in only. */
export function anonClient(): SupabaseClient {
  return createClient(env.supabaseUrl, env.anonKey, { auth: noSession });
}

/**
 * The service key: the two code steps, creating a staff login, ending a
 * session. Server only; it never leaves this process.
 */
export function serviceClient(): SupabaseClient {
  return createClient(env.supabaseUrl, env.serviceKey, { auth: noSession });
}

/** Acts as the staff member: the database sees their JWT (and its session). */
export function userClient(accessToken: string): SupabaseClient {
  return createClient(env.supabaseUrl, env.anonKey, {
    auth: noSession,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}

export class DbError extends Error {
  constructor(
    public readonly code: string,
    message?: string,
  ) {
    super(message ?? code);
  }
}

/** Calls a database function; a refusal comes back as a DbError with its code. */
export async function rpc<T = unknown>(
  client: SupabaseClient,
  fn: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new DbError(error.message ?? 'error', error.message);
  return data as T;
}
