'use client';

import { useActionState } from 'react';
import { cancelPendingAction, loginAction, resendAction, verifyAction } from './actions';

export function LoginForm() {
  const [state, action, pending] = useActionState(loginAction, undefined);
  return (
    <form action={action} className="stack">
      <label>
        البريد الإلكتروني
        <input name="email" type="email" autoComplete="username" required dir="ltr" />
      </label>
      <label>
        كلمة المرور
        <input name="password" type="password" autoComplete="current-password" required dir="ltr" />
      </label>
      {state?.error ? <p className="flash bad">{state.error}</p> : null}
      <button type="submit" className="btn primary" disabled={pending}>
        {pending ? 'جارٍ التحقق…' : 'تسجيل الدخول'}
      </button>
    </form>
  );
}

export function VerifyForm() {
  const [state, action, pending] = useActionState(verifyAction, undefined);
  const [resent, resend, resending] = useActionState(resendAction, undefined);
  return (
    <div className="stack">
      <form action={action} className="stack">
        <label>
          رمز التحقق المرسل إلى واتساب
          <input
            name="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            maxLength={6}
            required
            autoFocus
            dir="ltr"
            className="code"
          />
        </label>
        {state?.error ? <p className="flash bad">{state.error}</p> : null}
        <button type="submit" className="btn primary" disabled={pending}>
          {pending ? 'جارٍ التحقق…' : 'تأكيد الدخول'}
        </button>
      </form>
      <form action={resend}>
        <button type="submit" className="btn link" disabled={resending}>
          لم يصلني الرمز — إرسال رمز جديد
        </button>
        {resent?.info ? <p className="flash ok">{resent.info}</p> : null}
        {resent?.error ? <p className="flash bad">{resent.error}</p> : null}
      </form>
      <form action={cancelPendingAction}>
        <button type="submit" className="btn link">رجوع</button>
      </form>
    </div>
  );
}
