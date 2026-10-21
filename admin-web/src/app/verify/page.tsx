import { VerifyForm } from '../login/forms';

export default function VerifyPage() {
  return (
    <main className="auth">
      <div className="card auth-card">
        <img src="/icon-192.png" width={72} height={72} alt="" className="logo" />
        <h1>التحقق عبر واتساب</h1>
        <p className="muted">
          أرسلنا رمزًا من 6 أرقام إلى رقم واتساب المسجّل لحسابك. صلاحيته 5 دقائق
          ويُستخدم مرة واحدة.
        </p>
        <VerifyForm />
      </div>
    </main>
  );
}
