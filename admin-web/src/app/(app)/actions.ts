'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { sessionCookie, unseal } from '@/lib/session';
import { rpc, serviceClient, userClient } from '@/lib/supabase';

/** Ends the verified session in the database and signs the token out. */
export async function logoutAction() {
  const jar = await cookies();
  const sealed = await unseal(jar.get(sessionCookie())?.value, 'session');
  jar.delete(sessionCookie());
  if (sealed) {
    await rpc(userClient(sealed.at), 'platform_logout').catch(() => {});
    await serviceClient().auth.admin.signOut(sealed.at, 'local').catch(() => {});
  }
  redirect('/login');
}
