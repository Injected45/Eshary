import Link from 'next/link';
import { Flash } from '@/components/Flash';
import { requireStaff } from '@/lib/auth';
import { fmtDateTime } from '@/lib/format';
import { rpc } from '@/lib/supabase';

type Dash = {
  total: number;
  active: number;
  trial: number;
  pending: number;
  expired: number;
  blocked: number;
  expiringSoon: number;
  expiryWarningDays: number;
  pendingRequests: number;
  notificationsSent: number;
  unreadAlerts: number;
  serverNow: string;
  activeNow: number | null;
  openTickets: number | null;
};

function Stat({
  label,
  value,
  href,
  na,
}: {
  label: string;
  value: number | null;
  href?: string;
  na?: string;
}) {
  const body = (
    <>
      <div className="n">{value === null ? (na ?? 'غير متاح') : value}</div>
      <div className="l">{label}</div>
    </>
  );
  const cls = `stat${value === null ? ' na' : ''}`;
  return href && value !== null ? (
    <Link href={href} className={cls}>{body}</Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

export default async function Dashboard({
  searchParams,
}: {
  searchParams: Promise<{ err?: string; ok?: string }>;
}) {
  const me = await requireStaff();
  const sp = await searchParams;
  const d = await rpc<Dash>(me.client, 'platform_dashboard');
  const writer = me.role === 'super_admin' || me.role === 'admin';

  return (
    <div className="stack">
      <h1>لوحة التحكم</h1>
      <Flash ok={sp.ok} err={sp.err} />
      <div className="grid">
        <Stat label="إجمالي المستخدمين" value={d.total} href="/users" />
        <Stat label="المفعّلون" value={d.active} href="/users?status=active" />
        <Stat label="غير المفعّلين (بانتظار التفعيل)" value={d.pending} href="/users?status=pending" />
        <Stat label="في الفترة التجريبية" value={d.trial} href="/users?status=trial" />
        <Stat label="الحسابات الموقوفة" value={d.blocked} href="/users?status=blocked" />
        <Stat label="المنتهية صلاحيتها" value={d.expired} href="/users?status=expired" />
        <Stat label={`تنتهي خلال ${d.expiryWarningDays} أيام`} value={d.expiringSoon} />
        <Stat
          label="طلبات التفعيل المعلّقة"
          value={d.pendingRequests}
          href={writer ? '/requests' : undefined}
        />
        <Stat
          label="الإشعارات المنشأة"
          value={d.notificationsSent}
          href={writer ? '/notifications' : undefined}
        />
        <Stat label="تنبيهات النظام غير المقروءة" value={d.unreadAlerts} href="/system" />
        <Stat label="النشطون الآن" value={d.activeNow} na="لم يُربط بعد" />
        <Stat label="طلبات الدعم المفتوحة" value={d.openTickets} na="المرحلة الثانية" />
      </div>
      <p className="muted">وقت الخادم: {fmtDateTime(d.serverNow)} (طرابلس)</p>
    </div>
  );
}
