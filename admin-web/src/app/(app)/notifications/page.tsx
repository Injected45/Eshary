import { ConfirmButton } from '@/components/ConfirmButton';
import { Flash } from '@/components/Flash';
import { requireStaff } from '@/lib/auth';
import { fmtDateTime } from '@/lib/format';
import { rpc } from '@/lib/supabase';
import { createNotificationAction, toggleNotificationAction } from './actions';

type N = { id: string; title: string | null; body: string; is_active: boolean; created_at: string };

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; err?: string }>;
}) {
  const me = await requireStaff('super_admin', 'admin');
  const sp = await searchParams;
  const rows = await rpc<N[]>(me.client, 'platform_notifications_list');

  return (
    <div className="stack">
      <h1>مركز الإشعارات</h1>
      <Flash ok={sp.ok} err={sp.err} />

      <form action={createNotificationAction} className="card stack">
        <h3>إشعار جديد لجميع المستخدمين</h3>
        <p className="muted">
          يظهر الإشعار النشط في رأس تقارير PDF داخل تطبيق إشاري. الإرسال الفوري إلى هاتف
          مستخدم محدد (Push) لم يُربط بعد — يحتاج خدمة Firebase للتطبيق.
        </p>
        <input name="title" placeholder="العنوان (اختياري)" maxLength={120} />
        <textarea name="body" placeholder="نص الإشعار" required minLength={2} maxLength={600} />
        <ConfirmButton message="نشر هذا الإشعار لجميع المستخدمين؟" className="btn primary">
          نشر الإشعار
        </ConfirmButton>
      </form>

      <section className="card table-wrap">
        <h3>سجل الإشعارات</h3>
        <table>
          <thead><tr><th>الوقت</th><th>العنوان</th><th>النص</th><th>الحالة</th><th></th></tr></thead>
          <tbody>
            {rows.length === 0 ? (
              <tr><td colSpan={5} className="muted">لا توجد إشعارات</td></tr>
            ) : (
              rows.map((n) => (
                <tr key={n.id}>
                  <td>{fmtDateTime(n.created_at)}</td>
                  <td className="wrap">{n.title ?? '—'}</td>
                  <td className="wrap">{n.body}</td>
                  <td><span className={`badge ${n.is_active ? 'ok' : 'muted'}`}>{n.is_active ? 'نشط' : 'متوقف'}</span></td>
                  <td>
                    <form action={toggleNotificationAction}>
                      <input type="hidden" name="id" value={n.id} />
                      <input type="hidden" name="active" value={String(!n.is_active)} />
                      <button className="btn" type="submit">{n.is_active ? 'إيقاف' : 'تفعيل'}</button>
                    </form>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>
    </div>
  );
}
