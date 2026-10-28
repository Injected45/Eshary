import { ConfirmButton } from '@/components/ConfirmButton';
import { Flash } from '@/components/Flash';
import { canWrite, requireStaff } from '@/lib/auth';
import { fmtDateTime } from '@/lib/format';
import { rpc } from '@/lib/supabase';
import { setReleaseActiveAction } from './actions';

type Release = {
  id: string;
  build_number: number;
  version_name: string;
  mandatory: boolean;
  is_active: boolean;
  notes: string | null;
  created_at: string;
  files: Record<string, { size?: number }>;
};

const mb = (n?: number) => (n ? `${(n / 1048576).toFixed(1)} MB` : '—');

export default async function UpdatesPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; err?: string }>;
}) {
  const me = await requireStaff();
  const sp = await searchParams;
  const rows = await rpc<Release[]>(me.client, 'platform_releases_list');
  const writer = canWrite(me.role);
  const live = rows.find((r) => r.is_active);
  const forced = rows.find((r) => r.is_active && r.mandatory);

  return (
    <div className="stack">
      <h1>تحديثات التطبيق</h1>
      <Flash ok={sp.ok} err={sp.err} />

      <section className="card stack">
        <p>
          {live ? (
            <>
              الإصدار المعروض الآن على الهواتف: <strong>{live.version_name}</strong> (رقم البناء{' '}
              {live.build_number}) —{' '}
              {forced && forced.build_number >= live.build_number
                ? 'تحديث إلزامي: كل هاتف أقدم منه يُمنع من العمل حتى يتحدّث.'
                : forced
                  ? `الحد الأدنى الإلزامي هو البناء ${forced.build_number}.`
                  : 'تحديث اختياري.'}
            </>
          ) : (
            'لا يوجد إصدار منشور نشط: لا يُطلب من أي هاتف أن يتحدّث.'
          )}
        </p>
        <p className="muted">
          يُنشر الإصدار الجديد من جهاز المطوّر بملف <code>publish-update.bat</code> بعد{' '}
          <code>build-apk.bat</code>. من هنا يمكنك <strong>سحب</strong> إصدار سيّئ فورًا (تتجاهله
          الهواتف عند فحصها التالي: عند فتح التطبيق أو العودة إليه) أو إعادته.
        </p>
      </section>

      <section className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>البناء</th>
              <th>الإصدار</th>
              <th>النوع</th>
              <th>الحالة</th>
              <th>الأحجام</th>
              <th>نُشر</th>
              <th>ما الجديد</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr><td colSpan={8} className="muted">لم يُنشر أي تحديث بعد</td></tr>
            ) : (
              rows.map((r) => (
                <tr key={r.id}>
                  <td>{r.build_number}</td>
                  <td>{r.version_name}</td>
                  <td>{r.mandatory ? 'إلزامي' : 'اختياري'}</td>
                  <td>
                    <span className={`badge ${r.is_active ? 'ok' : 'muted'}`}>
                      {r.is_active ? 'نشط' : 'مسحوب'}
                    </span>
                  </td>
                  <td dir="ltr" style={{ textAlign: 'right' }}>
                    64: {mb(r.files['arm64-v8a']?.size)} · 32: {mb(r.files['armeabi-v7a']?.size)}
                  </td>
                  <td>{fmtDateTime(r.created_at)}</td>
                  <td className="wrap">{r.notes ?? ''}</td>
                  <td>
                    {writer ? (
                      <form action={setReleaseActiveAction}>
                        <input type="hidden" name="id" value={r.id} />
                        <input type="hidden" name="active" value={String(!r.is_active)} />
                        {r.is_active ? (
                          <ConfirmButton
                            message={`سحب الإصدار ${r.version_name}؟ ستتجاهله الهواتف فورًا.`}
                            className="btn danger"
                          >
                            سحب
                          </ConfirmButton>
                        ) : (
                          <button className="btn" type="submit">إعادة</button>
                        )}
                      </form>
                    ) : null}
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
