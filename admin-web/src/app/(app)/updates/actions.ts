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
  redirect(`/updates?${q}`);
}

/** Withdraws or restores a release: the apps follow at once (their next check). */
export async function setReleaseActiveAction(form: FormData) {
  const me = await requireStaff('super_admin', 'admin');
  const id = String(form.get('id') ?? '');
  const active = String(form.get('active') ?? '') === 'true';
  if (!UUID.test(id)) back();
  try {
    await rpc(me.client, 'platform_release_set_active', { p_id: id, p_active: active });
  } catch (e) {
    back(undefined, explain(e));
  }
  back(active ? 'أُعيد تفعيل الإصدار' : 'سُحب الإصدار: لن يُطلب من أحد تحديثه');
}
