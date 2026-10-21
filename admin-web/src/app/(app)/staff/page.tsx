import { ConfirmButton } from '@/components/ConfirmButton';
import { Flash } from '@/components/Flash';
import { requireStaff } from '@/lib/auth';
import { fmtDateTime, roleLabel } from '@/lib/format';
import { rpc } from '@/lib/supabase';
import { addStaffAction, setStaffAction } from './actions';

type S = {
  user_id: string;
  email: string;
  full_name: string;
  role: string;
  phone_masked: string;
  phone_verified: boolean;
  active: boolean;
  created_at: string;
};

export default async function StaffPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; err?: string }>;
}) {
  const me = await requireStaff('super_admin');
  const sp = await searchParams;
  const rows = await rpc<S[]>(me.client, 'platform_staff_list');

  return (
    <div className="stack">
      <h1>الحسابات الإدارية</h1>
      <Flash ok={sp.ok} err={sp.err} />

      <section className="card table-wrap">
        <table>
          <thead>
            <tr><th>الاسم</th><th>البريد</th><th>الدور</th><th>واتساب</th><th>الحالة</th><th>أُنشئ</th><th></th></tr>
          </thead>
          <tbody>
            {rows.map((s) => (
              <tr key={s.user_id}>
                <td>{s.full_name}</td>
                <td dir="ltr" style={{ textAlign: 'right' }}>{s.email}</td>
                <td>{roleLabel[s.role] ?? s.role}</td>
                <td dir="ltr" style={{ textAlign: 'right' }}>
                  {s.phone_masked} {s.phone_verified ? '✓' : '(لم يُوثَّق بعد)'}
                </td>
                <td><span className={`badge ${s.active ? 'ok' : 'bad'}`}>{s.active ? 'نشط' : 'معطّل'}</span></td>
                <td>{fmtDateTime(s.created_at)}</td>
                <td>
                  {s.user_id === me.userId ? (
                    <span className="muted">حسابك</span>
                  ) : (
                    <form action={setStaffAction} className="row">
                      <input type="hidden" name="id" value={s.user_id} />
                      <select name="role" defaultValue={s.role} style={{ width: 130 }}>
                        {Object.entries(roleLabel).map(([k, v]) => (
                          <option key={k} value={k}>{v}</option>
                        ))}
                      </select>
                      <button className="btn" type="submit">حفظ الدور</button>
                      <ConfirmButton
                        message={s.active ? 'تعطيل هذا الحساب وإنهاء جلساته فورًا؟' : 'إعادة تفعيل هذا الحساب؟'}
                        className={s.active ? 'btn danger' : 'btn'}
                        name="active"
                        value={String(!s.active)}
                      >
                        {s.active ? 'تعطيل' : 'تفعيل'}
                      </ConfirmButton>
                    </form>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <form action={addStaffAction} className="card stack">
        <h3>إضافة حساب إداري</h3>
        <p className="muted">
          يصل رمز واتساب إلى الرقم المكتوب هنا عند كل دخول، فاكتب رقم الموظف نفسه. أعطِه كلمة المرور
          بوسيلة آمنة.
        </p>
        <div className="cols">
          <label>الاسم<input name="name" required maxLength={80} /></label>
          <label>البريد<input name="email" type="email" required dir="ltr" autoComplete="off" /></label>
          <label>
            كلمة مرور مؤقتة (12 حرفًا فأكثر)
            <input name="password" type="password" required minLength={12} dir="ltr" autoComplete="new-password" />
          </label>
          <label>رقم واتساب (مع رمز الدولة)<input name="phone" required placeholder="+218912345678" dir="ltr" /></label>
          <label>
            الدور
            <select name="role" defaultValue="support">
              {Object.entries(roleLabel).map(([k, v]) => (
                <option key={k} value={k}>{v}</option>
              ))}
            </select>
          </label>
        </div>
        <button className="btn primary" type="submit" style={{ alignSelf: 'flex-start' }}>إضافة</button>
      </form>
    </div>
  );
}
