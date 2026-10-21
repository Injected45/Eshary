import { requireStaff } from '@/lib/auth';
import { fmtDateTime } from '@/lib/format';
import { rpc } from '@/lib/supabase';

type Sys = {
  database: boolean;
  serverNow: string;
  timeTrusted: boolean;
  whatsappSentLastHour: number;
  whatsappFailedLastHour: number;
  schedulerLastRun: string | null;
  unreadAlerts: number;
  activeStaffSessions: number;
  recentAlerts: { at: string; kind: string; body: string }[];
};

function Row({ ok, label, detail }: { ok: boolean | null; label: string; detail?: string }) {
  const tone = ok === null ? 'warn' : ok ? 'ok' : 'bad';
  return (
    <tr>
      <td><span className={`dot ${tone}`} />{label}</td>
      <td>{ok === null ? 'غير معروف' : ok ? 'سليم' : 'يحتاج انتباه'}</td>
      <td className="wrap muted">{detail ?? ''}</td>
    </tr>
  );
}

export default async function SystemPage() {
  const me = await requireStaff();
  let s: Sys | null = null;
  try {
    s = await rpc<Sys>(me.client, 'platform_system_status');
  } catch {
    s = null;
  }
  const lastRun = s?.schedulerLastRun ? new Date(s.schedulerLastRun).getTime() : null;
  const schedulerOk = lastRun === null ? null : Date.now() - lastRun < 5 * 60_000;

  return (
    <div className="stack">
      <h1>حالة النظام</h1>
      <div className="card table-wrap">
        <table>
          <thead><tr><th>الخدمة</th><th>الحالة</th><th>التفاصيل</th></tr></thead>
          <tbody>
            <Row ok label="خادم المنصة" detail="يعمل — هذه الصفحة وصلت منه" />
            <Row ok={s?.database ?? false} label="قاعدة البيانات" detail={s ? `وقت الخادم ${fmtDateTime(s.serverNow)}` : 'لا إجابة'} />
            <Row ok={s ? s.timeTrusted : false} label="ساعة الخادم (حارس الوقت)" detail={s && !s.timeTrusted ? 'تراجعت الساعة — راجع التنبيهات' : ''} />
            <Row
              ok={s ? s.whatsappFailedLastHour === 0 : false}
              label="خدمة واتساب (التحقق)"
              detail={s ? `آخر ساعة: ${s.whatsappSentLastHour} مرسلة، ${s.whatsappFailedLastHour} فاشلة` : ''}
            />
            <Row ok={schedulerOk} label="المجدول الدوري (انتهاء التجارب)" detail={s?.schedulerLastRun ? `آخر تشغيل ${fmtDateTime(s.schedulerLastRun)}` : 'لا يوجد سجل تشغيل'} />
            <Row ok={s ? s.unreadAlerts === 0 : false} label="التنبيهات التقنية" detail={s ? `${s.unreadAlerts} غير مقروءة` : ''} />
            <Row ok={null} label="الإشعارات الفورية (Push)" detail="لم تُربط بعد" />
            <Row ok={null} label="النسخ الاحتياطية" detail="تُدار من تطبيق إشاري (نسخة يومية 22:00)؛ مراقبتها هنا في المرحلة الثانية" />
          </tbody>
        </table>
      </div>

      <section className="card stack">
        <h3>آخر التنبيهات</h3>
        {s && s.recentAlerts.length > 0 ? (
          <div className="table-wrap">
            <table>
              <tbody>
                {s.recentAlerts.map((a, i) => (
                  <tr key={i}>
                    <td>{fmtDateTime(a.at)}</td>
                    <td>{a.kind}</td>
                    <td className="wrap">{a.body}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="muted">لا توجد تنبيهات</p>
        )}
        <p className="muted">جلسات إدارية نشطة الآن: {s?.activeStaffSessions ?? '—'}</p>
      </section>
    </div>
  );
}
