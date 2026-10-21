'use server';

import { redirect } from 'next/navigation';
import { requireStaff } from '@/lib/auth';
import { explain } from '@/lib/errors';
import { rpc } from '@/lib/supabase';

function back(ok?: string, err?: string): never {
  const q = new URLSearchParams();
  if (ok) q.set('ok', ok);
  if (err) q.set('err', err);
  redirect(`/settings?${q}`);
}

const list = (s: string) =>
  s.split(/[\s,،]+/).filter(Boolean).map((x) => Number(x));

export async function saveSettingAction(form: FormData) {
  const me = await requireStaff('super_admin');
  const key = String(form.get('key') ?? '');
  const raw = String(form.get('value') ?? '').trim();
  const value =
    key === 'trial_presets_hours' || key === 'paid_presets_days' ? list(raw) : Number(raw);
  if (Array.isArray(value) ? value.some((n) => !Number.isFinite(n)) : !Number.isFinite(value)) {
    back(undefined, 'القيمة غير صالحة');
  }
  try {
    await rpc(me.client, 'platform_setting_set', { p_key: key, p_value: value });
  } catch (e) {
    back(undefined, explain(e));
  }
  back('تم حفظ الإعداد');
}
