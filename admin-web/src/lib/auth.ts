import { cache } from 'react';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import type { SupabaseClient } from '@supabase/supabase-js';
import { rpc, userClient } from './supabase';
import { sessionCookie, unseal } from './session';

export type Role = 'super_admin' | 'admin' | 'support' | 'viewer';

export type Staff = {
  userId: string;
  role: Role;
  name: string;
  /** Acts as this staff member; the database enforces everything again. */
  client: SupabaseClient;
};

/**
 * The signed-in staff member, or a redirect to the sign-in page.
 *
 * The role comes from the DATABASE on every request (platform_me), never from
 * the cookie: it answers only while the verified-code session is live and the
 * account is active. Passing roles limits the page to them.
 */
export const requireStaff = cache(async (...roles: Role[]): Promise<Staff> => {
  const jar = await cookies();
  const sealed = await unseal(jar.get(sessionCookie())?.value, 'session');
  if (!sealed) redirect('/login');

  const client = userClient(sealed.at);
  let me: { userId: string; role: Role; name: string } | null = null;
  try {
    me = await rpc(client, 'platform_me');
  } catch {
    me = null;
  }
  if (!me) redirect('/login?e=session');
  if (roles.length > 0 && !roles.includes(me.role)) redirect('/?err=forbidden');
  return { userId: me.userId, role: me.role, name: me.name, client };
});

export const canWrite = (role: Role) => role === 'super_admin' || role === 'admin';
