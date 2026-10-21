import { LoginForm } from './forms';

const reasons: Record<string, string> = {
  session: 'انتهت الجلسة. سجّل الدخول من جديد',
  code: 'انتهى الرمز أو أُلغي. سجّل الدخول من جديد',
  attempts: 'تجاوزت عدد المحاولات المسموح. انتظر قليلًا ثم أعد المحاولة',
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ e?: string }>;
}) {
  const { e } = await searchParams;
  return (
    <main className="auth">
      <div className="card auth-card">
        <img src="/icon-192.png" width={72} height={72} alt="" className="logo" />
        <h1>إشاري</h1>
        <p className="muted">ESHARI Admin — منصة الإدارة والتحكم</p>
        {e && reasons[e] ? <p className="flash bad">{reasons[e]}</p> : null}
        <LoginForm />
      </div>
    </main>
  );
}
