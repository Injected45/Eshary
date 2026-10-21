import { Flash } from '@/components/Flash';
import { requireStaff } from '@/lib/auth';
import { rpc } from '@/lib/supabase';
import { saveSettingAction } from './actions';

type Settings = {
  trial_presets_hours: number[];
  paid_presets_days: number[];
  expiry_warning_days: number;
  session_hours: number;
};

const FIELDS: { key: keyof Settings; label: string; hint: string; list: boolean }[] = [
  { key: 'trial_presets_hours', label: 'مدد التجربة المقترحة (بالساعات)', hint: 'مثال: 72 168', list: true },
  { key: 'paid_presets_days', label: 'مدد الاشتراك المقترحة (بالأيام)', hint: 'مثال: 30 90 365', list: true },
  { key: 'expiry_warning_days', label: 'التنبيه قبل انتهاء الاشتراك (بالأيام)', hint: '1 – 72', list: false },
  { key: 'session_hours', label: 'مدة الجلسة الإدارية بعد رمز واتساب (بالساعات)', hint: '1 – 72', list: false },
];

export default async function SettingsPage({
  searchParams,
}: {
  searchParams: Promise<{ ok?: string; err?: string }>;
}) {
  const me = await requireStaff('super_admin', 'admin');
  const sp = await searchParams;
  const s = await rpc<Settings>(me.client, 'platform_settings_get');
  const edit = me.role === 'super_admin';

  return (
    <div className="stack">
      <h1>الإعدادات العامة</h1>
      <Flash ok={sp.ok} err={sp.err} />

      <section className="card stack">
        <h3>التفعيل والجلسات</h3>
        {!edit ? <p className="muted">التعديل للمدير الرئيسي فقط.</p> : null}
        {FIELDS.map((f) => {
          const v = s[f.key];
          const shown = Array.isArray(v) ? v.join(' ') : String(v ?? '');
          return edit ? (
            <form key={f.key} action={saveSettingAction} className="row">
              <input type="hidden" name="key" value={f.key} />
              <label className="grow">
                {f.label}
                <input name="value" defaultValue={shown} placeholder={f.hint} dir="ltr" required />
              </label>
              <button className="btn primary" type="submit" style={{ alignSelf: 'flex-end' }}>حفظ</button>
            </form>
          ) : (
            <dl key={f.key}><dt>{f.label}</dt><dd dir="ltr">{shown}</dd></dl>
          );
        })}
        <p className="muted">
          هذه القيم تُقترح في شاشة المستخدم؛ الخادم هو من يحسب الصلاحية دائمًا بساعته.
        </p>
      </section>

      <section className="card">
        <h3>معلومات النظام</h3>
        <dl>
          <dt>المنصة</dt><dd>ESHARI Admin 0.1.0</dd>
          <dt>مفاتيح الخدمات</dt><dd>محفوظة في إعدادات الخادم ولا تُعرض هنا</dd>
          <dt>خدمة واتساب</dt><dd>بوابة المشروع الحالية (الإعداد في قاعدة البيانات)</dd>
        </dl>
      </section>
    </div>
  );
}
