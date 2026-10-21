'use server';

import { redirect } from 'next/navigation';
import { requireStaff } from '@/lib/auth';
import { explain } from '@/lib/errors';
import { rpc } from '@/lib/supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DECISIONS = ['approve_72', 'approve_168', 'renew_approval', 'request_info', 'reject', 'withdraw'];

export async function decideAction(form: FormData) {
  const me = await requireStaff('super_admin', 'admin');
  const id = String(form.get('id') ?? '');
  const decision = String(form.get('decision') ?? '');
  const note = String(form.get('note') ?? '').trim().slice(0, 300);
  if (!UUID.test(id) || !DECISIONS.includes(decision)) redirect('/requests');

  let q: URLSearchParams;
  try {
    await rpc(me.client, 'admin_trial_decide', {
      p_id: id,
      p_decision: decision,
      p_note: note || null,
    });
    q = new URLSearchParams({ ok: 'تم تنفيذ القرار' });
  } catch (e) {
    q = new URLSearchParams({ err: explain(e) });
  }
  redirect(`/requests?${q}`);
}
