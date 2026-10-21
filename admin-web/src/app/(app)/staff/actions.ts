'use server';

import { redirect } from 'next/navigation';
import { requireStaff } from '@/lib/auth';
import { explain } from '@/lib/errors';
import { rpc, serviceClient } from '@/lib/supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ROLES = ['super_admin', 'admin', 'support', 'viewer'];

function back(ok?: string, err?: string): never {
  const q = new URLSearchParams();
  if (ok) q.set('ok', ok);
  if (err) q.set('err', err);
  redirect(`/staff?${q}`);
}

/** Creates the login, then the staff row; if the second fails the login is removed. */
export async function addStaffAction(form: FormData) {
  const me = await requireStaff('super_admin');
  const email = String(form.get('email') ?? '').trim().toLowerCase().slice(0, 200);
  const password = String(form.get('password') ?? '');
  const name = String(form.get('name') ?? '').trim().slice(0, 80);
  const phone = String(form.get('phone') ?? '').trim().slice(0, 30);
  const role = String(form.get('role') ?? '');

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) back(undefined, 'البريد غير صالح');
  if (password.length < 12) back(undefined, 'كلمة المرور 12 حرفًا على الأقل');
  if (name.length < 2) back(undefined, 'اكتب اسم الموظف');
  if (!ROLES.includes(role)) back(undefined, 'دور غير صالح');

  const svc = serviceClient();
  const { data, error } = await svc.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { platform_staff: true },
  });
  if (error || !data.user) back(undefined, 'تعذّر إنشاء الحساب (قد يكون البريد مستخدمًا)');

  try {
    await rpc(svc, 'platform_staff_add', {
      p_user: data.user.id, p_role: role, p_name: name, p_phone: phone, p_by: me.userId,
    });
  } catch (e) {
    await svc.auth.admin.deleteUser(data.user.id).catch(() => {});
    back(undefined, explain(e));
  }
  back('تمت إضافة الحساب. سيُرسل رمز واتساب إلى الرقم المسجّل عند أول دخول');
}

export async function setStaffAction(form: FormData) {
  const me = await requireStaff('super_admin');
  const id = String(form.get('id') ?? '');
  const role = String(form.get('role') ?? '');
  const active = String(form.get('active') ?? '');
  if (!UUID.test(id)) back();
  try {
    await rpc(me.client, 'platform_staff_set', {
      p_user: id,
      p_role: ROLES.includes(role) ? role : null,
      p_active: active === 'true' ? true : active === 'false' ? false : null,
    });
  } catch (e) {
    back(undefined, explain(e));
  }
  back('تم حفظ التعديل وأُنهيت جلسات الحساب');
}
