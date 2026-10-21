import { EncryptJWT, jwtDecrypt } from 'jose';
import { env } from './env';

/**
 * Two sealed (encrypted + authenticated) cookies, never readable by the page:
 *
 *   pending  after the PASSWORD, before the WhatsApp code. It cannot open any
 *            page: it only lets the code screen finish the sign-in.
 *   session  after the CODE. Holds the Supabase tokens the server uses on the
 *            staff member's behalf. The database still refuses everything
 *            unless it has the verified-session row for this session_id.
 */
export type Sealed = {
  typ: 'pending' | 'session';
  uid: string; // staff user id
  at: string; // Supabase access token
  rt: string; // Supabase refresh token
  sid: string; // Supabase session id (the JWT's session_id claim)
  atExp: number; // access token expiry (seconds since epoch)
};

export const PENDING_SECONDS = 10 * 60;
export const SESSION_SECONDS = 12 * 60 * 60;

const prefix = () => (env.isProd ? '__Host-' : '');
export const pendingCookie = () => `${prefix()}eshary_pending`;
export const sessionCookie = () => `${prefix()}eshary_session`;

async function key(): Promise<Uint8Array> {
  const bytes = new TextEncoder().encode(env.sessionSecret);
  return new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
}

export async function seal(data: Sealed, seconds: number): Promise<string> {
  return new EncryptJWT({ ...data })
    .setProtectedHeader({ alg: 'dir', enc: 'A256GCM' })
    .setIssuedAt()
    .setExpirationTime(`${seconds}s`)
    .encrypt(await key());
}

export async function unseal(
  token: string | undefined,
  typ: Sealed['typ'],
): Promise<Sealed | null> {
  if (!token) return null;
  try {
    const { payload } = await jwtDecrypt(token, await key());
    if (payload.typ !== typ) return null;
    const { uid, at, rt, sid, atExp } = payload as unknown as Sealed;
    if (!uid || !at || !rt || !sid || typeof atExp !== 'number') return null;
    return { typ, uid, at, rt, sid, atExp };
  } catch {
    return null;
  }
}

export function cookieOptions(seconds: number) {
  return {
    httpOnly: true,
    secure: env.isProd,
    sameSite: 'strict' as const,
    path: '/',
    maxAge: seconds,
  };
}
