'use server';

import { redirect } from 'next/navigation';
import { requireStaff } from '@/lib/auth';
import { explain } from '@/lib/errors';
import { rpc } from '@/lib/supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function back(ok?: string, err?: string): never {
  const q = new URLSearchParams();
  if (ok) q.set('ok', ok);
  if (err) q.set('err', err);
  redirect(`/notifications?${q}`);
}

export async function createNotificationAction(form: FormData) {
  const me = await requireStaff('super_admin', 'admin');
  const title = String(form.get('title') ?? '').trim().slice(0, 120);
  const body = String(form.get('body') ?? '').trim().slice(0, 600);
  try {
    await rpc(me.client, 'platform_notification_create', { p_title: title || null, p_body: body });
  } catch (e) {
    back(undefined, explain(e));
  }
  back('تم نشر الإشعار لجميع المستخدمين');
}

export async function toggleNotificationAction(form: FormData) {
  const me = await requireStaff('super_admin', 'admin');
  const id = String(form.get('id') ?? '');
  const active = String(form.get('active') ?? '') === 'true';
  if (!UUID.test(id)) back();
  try {
    await rpc(me.client, 'platform_notification_set_active', { p_id: id, p_active: active });
  } catch (e) {
    back(undefined, explain(e));
  }
  back(active ? 'تم تفعيل الإشعار' : 'تم إيقاف الإشعار');
}
