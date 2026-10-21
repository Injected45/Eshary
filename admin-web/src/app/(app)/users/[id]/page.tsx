import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ConfirmButton } from '@/components/ConfirmButton';
import { Flash } from '@/components/Flash';
import { canWrite, requireStaff } from '@/lib/auth';
import { auditLabel, fmtDateTime, statusLabel, statusTone } from '@/lib/format';
import { rpc } from '@/lib/supabase';
import {
  confirmPaymentAction,
  extendTrialAction,
  lifetimeAction,
  notesAction,
  reactivateAction,
  suspendAction,
} from './actions';

type Detail = {
  userId: string;
  displayName: string;
  email: string | null;
  phone: string | null;
  status: string;
  licenseType: string | null;
  trialEndsAt: string | null;
  paidUntil: string | null;
  activatedAt: string | null;
  suspendedAt: string | null;
  suspendedReason: string | null;
  paidReference: string | null;
  notes: string | null;
  createdAt: string;
  lastSignInAt: string | null;
  history: {
    at: string;
    kind: string;
    by: string | null;
    note: string | null;
  }[];
};

type Settings = {
  trial_presets_hours?: number[];
  paid_presets_days?: number[];
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function UserPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; err?: string }>;
}) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const sp = await searchParams;
  const me = await requireStaff();
  const writer = canWrite(me.role);

  let u: Detail;
  try {
    u = await rpc<Detail>(me.client, 'platform_user_detail', { p_user: id });
  } catch {
    notFound();
  }
  const settings = writer ? await rpc<Settings>(me.client, 'platform_settings_get') : {};
  const hours = settings.trial_presets_hours ?? [72, 168];
  const days = settings.paid_presets_days ?? [30, 90, 365];

  const bind = <A extends (id: string, f: FormData) => Promise<void>>(fn: A) => fn.bind(null, id);

  return (
    <div className="stack">
      <div className="row">
        <Link href="/users" className="btn">← المستخدمون</Link>
        <h1 className="grow">{u.displayName}</h1>
        <span className={`badge ${statusTone[u.status] ?? 'muted'}`}>{statusLabel[u.status] ?? u.status}</span>
      </div>
      <Flash ok={sp.ok} err={sp.err} />

      <div className="cols">
        <section className="card">
          <h3>بيانات المستخدم</h3>
          <dl>
            <dt>الرقم التعريفي</dt><dd dir="ltr">{u.userId}</dd>
            <dt>الهاتف</dt><dd dir="ltr">{u.phone ?? '—'}</dd>
            <dt>البريد</dt><dd dir="ltr">{u.email ?? '—'}</dd>
            <dt>تاريخ التسجيل</dt><dd>{fmtDateTime(u.createdAt)}</dd>
            <dt>آخر دخول</dt><dd>{fmtDateTime(u.lastSignInAt)}</dd>
            <dt>نوع التفعيل</dt>
            <dd>{u.licenseType === 'lifetime' ? 'نهائي' : u.licenseType === 'paid' ? 'مدفوع' : u.licenseType === 'trial' ? 'تجريبي' : '—'}</dd>
            <dt>بداية التفعيل</dt><dd>{fmtDateTime(u.activatedAt)}</dd>
            <dt>نهاية التجربة</dt><dd>{fmtDateTime(u.trialEndsAt)}</dd>
            <dt>نهاية الاشتراك</dt><dd>{fmtDateTime(u.paidUntil)}</dd>
            {u.paidReference ? (<><dt>مرجع الدفع</dt><dd>{u.paidReference}</dd></>) : null}
            {u.suspendedAt ? (<><dt>سبب الإيقاف</dt><dd>{u.suspendedReason ?? '—'}</dd></>) : null}
          </dl>
        </section>

        {writer ? (
          <section className="card stack">
            <h3>إجراءات التفعيل</h3>

            <form action={bind(extendTrialAction)} className="stack">
              <strong>تمديد / منح فترة تجريبية</strong>
              <div className="row">
                <input name="hours" type="number" min={1} max={2160} defaultValue={hours[0]} list="hours" required style={{ width: 120 }} />
                <datalist id="hours">{hours.map((h) => <option key={h} value={h} />)}</datalist>
                <span className="muted">ساعة</span>
              </div>
              <input name="reason" placeholder="السبب (إلزامي)" required maxLength={300} />
              <ConfirmButton message="تمديد الفترة التجريبية لهذا المستخدم؟">تمديد</ConfirmButton>
            </form>

            <form action={bind(confirmPaymentAction)} className="stack">
              <strong>تأكيد دفع وتمديد الاشتراك</strong>
              <div className="row">
                <input name="days" type="number" min={1} max={3650} defaultValue={days[0]} list="days" required style={{ width: 120 }} />
                <datalist id="days">{days.map((d) => <option key={d} value={d} />)}</datalist>
                <span className="muted">يوم</span>
              </div>
              <input name="reference" placeholder="رقم مرجع الدفع (إلزامي)" required maxLength={120} />
              <input name="reason" placeholder="ملاحظة (اختياري)" maxLength={300} />
              <ConfirmButton message="تأكيد الدفع وتفعيل الاشتراك؟">تأكيد الدفع</ConfirmButton>
            </form>

            {u.email ? (
              <form action={bind(lifetimeAction)} className="stack">
                <input type="hidden" name="email" value={u.email} />
                <strong>التفعيل النهائي</strong>
                <ConfirmButton message="تفعيل هذا الحساب نهائيًا بلا تاريخ انتهاء؟">تفعيل نهائي</ConfirmButton>
              </form>
            ) : null}

            {u.status === 'blocked' ? (
              <form action={bind(reactivateAction)} className="stack">
                <strong>إعادة التفعيل</strong>
                <input name="reason" placeholder="ملاحظة (اختياري)" maxLength={300} />
                <ConfirmButton message="إعادة تفعيل الحساب؟" className="btn primary">إعادة التفعيل</ConfirmButton>
              </form>
            ) : (
              <form action={bind(suspendAction)} className="stack">
                <strong>إيقاف الحساب</strong>
                <input name="reason" placeholder="سبب الإيقاف (إلزامي)" required maxLength={300} />
                <ConfirmButton message="إيقاف هذا الحساب؟ سيفقد المستخدم الوصول فورًا." className="btn danger">إيقاف الحساب</ConfirmButton>
              </form>
            )}
          </section>
        ) : null}
      </div>

      {writer ? (
        <form action={bind(notesAction)} className="card stack">
          <h3>ملاحظات إدارية داخلية</h3>
          <textarea name="notes" defaultValue={u.notes ?? ''} maxLength={2000} />
          <button className="btn primary" type="submit" style={{ alignSelf: 'flex-start' }}>حفظ الملاحظات</button>
        </form>
      ) : null}

      <section className="card table-wrap">
        <h3>سجل الإجراءات على هذا الحساب</h3>
        <table>
          <thead><tr><th>الوقت</th><th>الإجراء</th><th>بواسطة</th><th>ملاحظة</th></tr></thead>
          <tbody>
            {u.history.length === 0 ? (
              <tr><td colSpan={4} className="muted">لا توجد إجراءات مسجلة</td></tr>
            ) : (
              u.history.map((h, i) => (
                <tr key={i}>
                  <td>{fmtDateTime(h.at)}</td>
                  <td>{auditLabel[h.kind] ?? h.kind}</td>
                  <td>{h.by ?? '—'}</td>
                  <td className="wrap">{h.note ?? ''}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>
    </div>
  );
}
