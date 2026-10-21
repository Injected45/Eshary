'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { decodeJwt } from 'jose';
import { clientIp } from '@/lib/request';
import {
  PENDING_SECONDS,
  SESSION_SECONDS,
  cookieOptions,
  pendingCookie,
  seal,
  sessionCookie,
  unseal,
} from '@/lib/session';
import { anonClient, rpc, serviceClient } from '@/lib/supabase';

export type FormState = { error?: string; info?: string } | undefined;

const GENERIC = 'بيانات الدخول غير صحيحة';
const NOT_READY = 'إعدادات الخادم ناقصة: ضع مفتاح service_role في ملف admin-web/.env.local';
const ready = () => Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY?.trim());

/** Step 1: e-mail and password. Right ones lead to the WhatsApp code, nothing else. */
export async function loginAction(_: FormState, form: FormData): Promise<FormState> {
  const email = String(form.get('email') ?? '').trim().toLowerCase().slice(0, 200);
  const password = String(form.get('password') ?? '').slice(0, 200);
  if (!email || !password) return { error: 'اكتب البريد وكلمة المرور' };
  if (!ready()) return { error: NOT_READY };

  const ip = await clientIp();
  const svc = serviceClient();

  // limits first: per address and per e-mail, counted in the database
  const okIp = await rpc<boolean>(svc, 'platform_throttle', {
    p_kind: 'login_ip', p_key: ip, p_limit: 20, p_minutes: 15,
  });
  const okMail = await rpc<boolean>(svc, 'platform_throttle', {
    p_kind: 'login_mail', p_key: email, p_limit: 8, p_minutes: 15,
  });
  if (!okIp || !okMail) return { error: 'محاولات كثيرة. حاول بعد قليل' };

  const { data, error } = await anonClient().auth.signInWithPassword({ email, password });
  if (error || !data.session) {
    await rpc(svc, 'platform_login_rejected', { p_email: email, p_ip: ip }).catch(() => {});
    return { error: GENERIC };
  }

  const session = data.session;
  const claims = decodeJwt(session.access_token);
  const sid = String(claims.session_id ?? '');
  const uid = data.user?.id ?? '';
  if (!sid || !uid) return { error: GENERIC };

  // a valid password of someone who is not active staff gets the same answer
  const started = await rpc<{ ok: boolean; code?: string }>(svc, 'platform_login_start', {
    p_user: uid, p_ip: ip,
  });
  if (!started.ok && started.code !== 'too_soon') {
    await svc.auth.admin.signOut(session.access_token, 'local').catch(() => {});
    if (started.code === 'not_staff') return { error: GENERIC };
    return { error: 'تعذّر إرسال رمز التحقق. حاول بعد قليل' };
  }

  const jar = await cookies();
  jar.delete(sessionCookie());
  jar.set(
    pendingCookie(),
    await seal(
      {
        typ: 'pending', uid, at: session.access_token, rt: session.refresh_token,
        sid, atExp: Number(claims.exp ?? 0),
      },
      PENDING_SECONDS,
    ),
    cookieOptions(PENDING_SECONDS),
  );
  redirect('/verify');
}

/** Step 2: the code. Only a right code turns the pending cookie into a session. */
export async function verifyAction(_: FormState, form: FormData): Promise<FormState> {
  const jar = await cookies();
  const pending = await unseal(jar.get(pendingCookie())?.value, 'pending');
  if (!pending) redirect('/login');

  const code = String(form.get('code') ?? '').replace(/\D/g, '').slice(0, 6);
  if (code.length !== 6) return { error: 'اكتب الرمز المكوّن من 6 أرقام' };
  if (!ready()) return { error: NOT_READY };

  const ip = await clientIp();
  const svc = serviceClient();
  const r = await rpc<{ ok: boolean; code?: string; left?: number }>(svc, 'platform_login_verify', {
    p_user: pending.uid, p_code: code, p_auth_session: pending.sid, p_ip: ip,
  });

  if (!r.ok) {
    if (r.code === 'invalid_code') {
      return { error: 'الرمز غير صحيح' };
    }
    // expired / cancelled / locked: the person starts again
    jar.delete(pendingCookie());
    await svc.auth.admin.signOut(pending.at, 'local').catch(() => {});
    redirect(`/login?e=${r.code === 'too_many_attempts' || r.code === 'locked' ? 'attempts' : 'code'}`);
  }

  jar.delete(pendingCookie());
  jar.set(
    sessionCookie(),
    await seal({ ...pending, typ: 'session' }, SESSION_SECONDS),
    cookieOptions(SESSION_SECONDS),
  );
  redirect('/');
}

/** A new code (the database enforces the 60 s gap and the hourly limit). */
export async function resendAction(_: FormState): Promise<FormState> {
  const jar = await cookies();
  const pending = await unseal(jar.get(pendingCookie())?.value, 'pending');
  if (!pending) redirect('/login');
  const r = await rpc<{ ok: boolean; code?: string; wait?: number }>(
    serviceClient(), 'platform_login_start', { p_user: pending.uid, p_ip: await clientIp() },
  );
  if (r.ok) return { info: 'أُرسل رمز جديد إلى واتساب' };
  if (r.code === 'too_soon') return { error: `انتظر ${r.wait ?? 60} ثانية قبل طلب رمز جديد` };
  return { error: 'تعذّر إرسال الرمز الآن' };
}

export async function cancelPendingAction() {
  const jar = await cookies();
  const pending = await unseal(jar.get(pendingCookie())?.value, 'pending');
  jar.delete(pendingCookie());
  if (pending) await serviceClient().auth.admin.signOut(pending.at, 'local').catch(() => {});
  redirect('/login');
}
