import { ConfirmButton } from '@/components/ConfirmButton';
import { Flash } from '@/components/Flash';
import { requireStaff } from '@/lib/auth';
import { fmtDateTime } from '@/lib/format';
import { rpc } from '@/lib/supabase';
import { decideAction } from './actions';

type Req = {
  id: string;
  manager_name: string;
  business_name: string;
  phone: string;
  status: string;
  bucket: string;
  review_note: string | null;
  requested_at: string;
  approved_at: string | null;
  trial_hours: number | null;
  phone_verified: boolean;
  message_status: string | null;
  user_id: string | null;
};

const bucketLabel: Record<string, [string, string]> = {
  pending_review: ['بانتظار المراجعة', 'warn'],
  needs_info: ['بانتظار معلومات', 'warn'],
  approved_waiting: ['موافق عليه — بانتظار المستخدم', 'info'],
  message_failed: ['موافق عليه — فشل إرسال الرسالة', 'bad'],
  approval_expired: ['انتهت صلاحية الموافقة', 'muted'],
  rejected_or_suspended: ['مرفوض', 'bad'],
  activated: ['مفعّل', 'ok'],
  paid: ['مدفوع', 'ok'],
};

const OPEN = new Set(['pending_review', 'needs_info', 'message_failed', 'approval_expired', 'approved_waiting']);

export default async function RequestsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; err?: string; all?: string }>;
}) {
  const me = await requireStaff('super_admin', 'admin');
  const sp = await searchParams;
  const rows = await rpc<Req[]>(me.client, 'admin_list_trial_requests');
  const shown = sp.all ? rows : rows.filter((r) => OPEN.has(r.bucket));

  return (
    <div className="stack">
      <div className="row">
        <h1 className="grow">طلبات التفعيل</h1>
        <a className="btn" href={sp.all ? '/requests' : '/requests?all=1'}>
          {sp.all ? 'المفتوحة فقط' : 'عرض كل الطلبات'}
        </a>
      </div>
      <Flash ok={sp.ok} err={sp.err} />

      {shown.length === 0 ? <p className="card muted">لا توجد طلبات</p> : null}
      {shown.map((r) => {
        const [label, tone] = bucketLabel[r.bucket] ?? [r.bucket, 'muted'];
        const open = r.status === 'pending_review' || r.status === 'needs_info';
        return (
          <section className="card stack" key={r.id}>
            <div className="row">
              <strong className="grow">{r.business_name} — {r.manager_name}</strong>
              <span className={`badge ${tone}`}>{label}</span>
            </div>
            <div className="muted">
              <span dir="ltr">{r.phone}</span> · طُلب {fmtDateTime(r.requested_at)}
              {r.trial_hours ? ` · تجربة ${r.trial_hours} ساعة` : ''}
              {r.review_note ? ` · ملاحظة: ${r.review_note}` : ''}
            </div>
            {r.status !== 'activated' && r.status !== 'rejected' ? (
              <form action={decideAction} className="row">
                <input type="hidden" name="id" value={r.id} />
                <input name="note" placeholder="ملاحظة (اختياري)" maxLength={300} style={{ flex: 1, minWidth: 180 }} />
                {open ? (
                  <>
                    <button className="btn primary" name="decision" value="approve_72" type="submit">موافقة 3 أيام</button>
                    <button className="btn primary" name="decision" value="approve_168" type="submit">موافقة 7 أيام</button>
                    <button className="btn" name="decision" value="request_info" type="submit">طلب معلومات</button>
                    <ConfirmButton message="رفض هذا الطلب؟" className="btn danger" name="decision" value="reject">رفض</ConfirmButton>
                  </>
                ) : (
                  <button className="btn" name="decision" value="renew_approval" type="submit">تجديد الموافقة وإعادة الإرسال</button>
                )}
              </form>
            ) : null}
          </section>
        );
      })}
    </div>
  );
}
