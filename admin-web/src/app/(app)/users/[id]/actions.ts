'use server';

import { redirect } from 'next/navigation';
import { requireStaff } from '@/lib/auth';
import { explain } from '@/lib/errors';
import { rpc } from '@/lib/supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function done(id: string, ok?: string, err?: string): never {
  const q = new URLSearchParams();
  if (ok) q.set('ok', ok);
  if (err) q.set('err', err);
  redirect(`/users/${id}?${q}`);
}

const text = (f: FormData, k: string, max = 300) =>
  String(f.get(k) ?? '').trim().slice(0, max);
const num = (f: FormData, k: string) => Number.parseInt(String(f.get(k) ?? ''), 10);

type Run = (id: string, form: FormData) => Promise<[fn: string, args: Record<string, unknown>, ok: string]>;

async function run(id: string, form: FormData, build: Run) {
  if (!UUID.test(id)) redirect('/users');
  // every action asks again who is calling: the screen is not the guard
  const me = await requireStaff('super_admin', 'admin');
  let message: string;
  try {
    const [fn, args, ok] = await build(id, form);
    await rpc(me.client, fn, args);
    message = ok;
  } catch (e) {
    done(id, undefined, explain(e));
  }
  done(id, message);
}

export async function extendTrialAction(id: string, form: FormData) {
  return run(id, form, async () => [
    'admin_subscription_action',
    { p_user: id, p_action: 'extend_trial', p_hours: num(form, 'hours'), p_reason: text(form, 'reason') },
    'تم تمديد الفترة التجريبية',
  ]);
}

export async function confirmPaymentAction(id: string, form: FormData) {
  return run(id, form, async () => [
    'admin_subscription_action',
    {
      p_user: id, p_action: 'confirm_payment', p_days: num(form, 'days'),
      p_reference: text(form, 'reference'), p_reason: text(form, 'reason') || null,
    },
    'تم تأكيد الدفع وتمديد الاشتراك',
  ]);
}

export async function suspendAction(id: string, form: FormData) {
  return run(id, form, async () => [
    'admin_subscription_action',
    { p_user: id, p_action: 'suspend', p_reason: text(form, 'reason') },
    'تم إيقاف الحساب',
  ]);
}

export async function reactivateAction(id: string, form: FormData) {
  return run(id, form, async () => [
    'admin_subscription_action',
    { p_user: id, p_action: 'reactivate', p_reason: text(form, 'reason') || null },
    'تمت إعادة تفعيل الحساب',
  ]);
}

export async function lifetimeAction(id: string, form: FormData) {
  return run(id, form, async () => [
    'admin_activate_lifetime',
    { p_user_email: text(form, 'email', 200) },
    'تم التفعيل النهائي',
  ]);
}

export async function notesAction(id: string, form: FormData) {
  return run(id, form, async () => [
    'platform_user_set_notes',
    { p_user: id, p_notes: text(form, 'notes', 2000) },
    'تم حفظ الملاحظات',
  ]);
}
