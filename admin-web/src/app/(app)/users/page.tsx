import Link from 'next/link';
import { requireStaff } from '@/lib/auth';
import { fmtDate, statusLabel, statusTone } from '@/lib/format';
import { rpc } from '@/lib/supabase';

type Row = {
  user_id: string;
  display_name: string;
  phone: string | null;
  status: string;
  license_type: string | null;
  trial_ends_at: string | null;
  paid_until: string | null;
  created_at: string;
  total_count: number;
};

const PAGE = 25;
const STATUSES = ['pending', 'trial', 'active', 'expired', 'blocked'];

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; page?: string }>;
}) {
  const me = await requireStaff();
  const sp = await searchParams;
  const q = (sp.q ?? '').trim().slice(0, 100);
  const status = STATUSES.includes(sp.status ?? '') ? sp.status! : '';
  const page = Math.max(0, Number.parseInt(sp.page ?? '0', 10) || 0);

  const rows = await rpc<Row[]>(me.client, 'platform_users_list', {
    p_search: q || null,
    p_status: status || null,
    p_limit: PAGE,
    p_offset: page * PAGE,
  });
  const total = rows[0]?.total_count ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE));
  const link = (p: number) =>
    `/users?${new URLSearchParams({ ...(q ? { q } : {}), ...(status ? { status } : {}), page: String(p) })}`;

  return (
    <div className="stack">
      <h1>إدارة مستخدمي إشاري</h1>
      <form className="tools" method="get">
        <input name="q" defaultValue={q} placeholder="بحث بالاسم أو الهاتف أو البريد أو الرقم التعريفي" style={{ minWidth: 280 }} />
        <select name="status" defaultValue={status}>
          <option value="">كل الحالات</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>{statusLabel[s]}</option>
          ))}
        </select>
        <button className="btn primary" type="submit">بحث</button>
      </form>

      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>الاسم</th>
              <th>الهاتف</th>
              <th>الحالة</th>
              <th>النوع</th>
              <th>ينتهي في</th>
              <th>التسجيل</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr><td colSpan={6} className="muted">لا يوجد مستخدمون مطابقون</td></tr>
            ) : (
              rows.map((r) => (
                <tr key={r.user_id}>
                  <td className="wrap"><Link href={`/users/${r.user_id}`}>{r.display_name}</Link></td>
                  <td dir="ltr" style={{ textAlign: 'right' }}>{r.phone ?? '—'}</td>
                  <td><span className={`badge ${statusTone[r.status] ?? 'muted'}`}>{statusLabel[r.status] ?? r.status}</span></td>
                  <td>{r.license_type === 'lifetime' ? 'نهائي' : r.license_type === 'trial' ? 'تجريبي' : r.license_type === 'paid' ? 'مدفوع' : '—'}</td>
                  <td>{fmtDate(r.status === 'trial' ? r.trial_ends_at : r.paid_until)}</td>
                  <td>{fmtDate(r.created_at)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="pager">
        {page > 0 ? <Link className="btn" href={link(page - 1)}>السابق</Link> : null}
        <span className="muted">صفحة {page + 1} من {pages} — {total} مستخدم</span>
        {page + 1 < pages ? <Link className="btn" href={link(page + 1)}>التالي</Link> : null}
      </div>
    </div>
  );
}
