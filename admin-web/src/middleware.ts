import { NextResponse, type NextRequest } from 'next/server';
import { decodeJwt } from 'jose';
import { env } from '@/lib/env';
import {
  SESSION_SECONDS,
  cookieOptions,
  pendingCookie,
  seal,
  sessionCookie,
  unseal,
} from '@/lib/session';

// Reachable without a session. Everything else needs the verified cookie.
const OPEN = new Set([
  '/login',
  '/api/health',
  '/manifest.webmanifest',
  '/sw.js',
  '/icon-192.png',
  '/icon-512.png',
  '/favicon.png',
]);

function toLogin(req: NextRequest, reason?: string) {
  const url = req.nextUrl.clone();
  url.pathname = '/login';
  url.search = reason ? `?e=${reason}` : '';
  const res = NextResponse.redirect(url);
  res.cookies.delete(sessionCookie());
  return res;
}

export async function middleware(req: NextRequest) {
  const path = req.nextUrl.pathname;
  if (OPEN.has(path)) return NextResponse.next();

  // The code screen: only with the cookie that the password step leaves.
  if (path === '/verify') {
    const pending = await unseal(req.cookies.get(pendingCookie())?.value, 'pending');
    return pending ? NextResponse.next() : toLogin(req);
  }

  const session = await unseal(req.cookies.get(sessionCookie())?.value, 'session');
  if (!session) return toLogin(req);

  // Keep the access token fresh (it lives about an hour). The session id stays
  // the same, so the verified-code row in the database stays valid.
  const now = Math.floor(Date.now() / 1000);
  if (session.atExp - now > 120) return NextResponse.next();

  try {
    const r = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST',
      headers: { apikey: env.anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: session.rt }),
    });
    if (!r.ok) return toLogin(req, 'session');
    const t = (await r.json()) as { access_token?: string; refresh_token?: string };
    if (!t.access_token || !t.refresh_token) return toLogin(req, 'session');
    const claims = decodeJwt(t.access_token);
    if (claims.session_id !== session.sid) return toLogin(req, 'session');
    const next = await seal(
      {
        typ: 'session',
        uid: session.uid,
        at: t.access_token,
        rt: t.refresh_token,
        sid: session.sid,
        atExp: Number(claims.exp ?? now + 3000),
      },
      SESSION_SECONDS,
    );
    // the page being rendered must see the new token too
    req.cookies.set(sessionCookie(), next);
    const res = NextResponse.next({ request: { headers: req.headers } });
    res.cookies.set(sessionCookie(), next, cookieOptions(SESSION_SECONDS));
    return res;
  } catch {
    return toLogin(req, 'session');
  }
}

export const config = {
  matcher: ['/((?!_next/static|_next/image).*)'],
};
