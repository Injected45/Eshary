import Link from 'next/link';
import { requireStaff } from '@/lib/auth';
import { auditLabel, fmtDateTime } from '@/lib/format';
import { rpc } from '@/lib/supabase';

type A = {
  id: number;
  at: string;
  actor_email: string | null;
  kind: string;
  subject_type: string | null;
  subject_id: string | null;
  note: string | null;
};

const PAGE = 50;

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; kind?: string }>;
}) {
  const me = await requireStaff('super_admin', 'admin');
  const sp = await searchParams;
  const page = Math.max(0, Number.parseInt(sp.page ?? '0', 10) || 0);
  const kind = (sp.kind ?? '').replace(/[^a-z_]/g, '').slice(0, 60);
  const rows = await rpc<A[]>(me.client, 'platform_audit_list', {
    p_limit: PAGE + 1,
    p_offset: page * PAGE,
    p_kind: kind || null,
  });
  const more = rows.length > PAGE;
  const shown = rows.slice(0, PAGE);
  const link = (p: number) =>
    `/audit?${new URLSearchParams({ ...(kind ? { kind } : {}), page: String(p) })}`;

  return (
    <div className="stack">
      <h1>سجل العمليات الإدارية</h1>
      <p className="muted">سجل للقراءة فقط: لا يمكن تعديله أو حذفه من المنصة.</p>
      <form className="tools" method="get">
        <select name="kind" defaultValue={kind}>
          <option value="">كل الأنواع</option>
          {Object.entries(auditLabel).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
        <button className="btn primary" type="submit">تصفية</button>
      </form>
      <div className="card table-wrap">
        <table>
          <thead><tr><th>الوقت</th><th>الإجراء</th><th>المنفّذ</th><th>الهدف</th><th>ملاحظة</th></tr></thead>
          <tbody>
            {shown.length === 0 ? (
              <tr><td colSpan={5} className="muted">لا توجد سجلات</td></tr>
            ) : (
              shown.map((a) => (
                <tr key={a.id}>
                  <td>{fmtDateTime(a.at)}</td>
                  <td>{auditLabel[a.kind] ?? a.kind}</td>
                  <td dir="ltr" style={{ textAlign: 'right' }}>{a.actor_email ?? '—'}</td>
                  <td className="wrap" dir="ltr" style={{ textAlign: 'right' }}>
                    {a.subject_type === 'account' && a.subject_id ? (
                      <Link href={`/users/${a.subject_id}`}>{a.subject_id.slice(0, 8)}…</Link>
                    ) : (
                      `${a.subject_type ?? ''} ${a.subject_id ? a.subject_id.slice(0, 24) : ''}`.trim() || '—'
                    )}
                  </td>
                  <td className="wrap">{a.note ?? ''}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      <div className="pager">
        {page > 0 ? <Link className="btn" href={link(page - 1)}>السابق</Link> : null}
        <span className="muted">صفحة {page + 1}</span>
        {more ? <Link className="btn" href={link(page + 1)}>التالي</Link> : null}
      </div>
    </div>
  );
}
