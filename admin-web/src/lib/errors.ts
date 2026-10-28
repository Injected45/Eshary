import { DbError } from './supabase';

const messages: Record<string, string> = {
  platform_forbidden: 'ليست لديك صلاحية لهذا الإجراء',
  'admin only': 'ليست لديك صلاحية لهذا الإجراء',
  user_not_found: 'المستخدم غير موجود',
  reason_required: 'اكتب سبب الإجراء',
  invalid_hours: 'عدد الساعات غير صالح',
  invalid_days: 'عدد الأيام غير صالح',
  reference_required: 'رقم المرجع مطلوب لتأكيد الدفع',
  account_suspended: 'الحساب موقوف؛ أعد تفعيله أولًا',
  not_suspended: 'الحساب غير موقوف',
  admin_license_locked: 'لا يمكن تعديل ترخيص حساب مدير',
  request_not_found: 'الطلب غير موجود',
  request_closed: 'الطلب مغلق',
  already_approved: 'الطلب موافق عليه مسبقًا',
  trial_used: 'هذا الرقم أخذ فترة تجريبية سابقًا',
  invalid_body: 'نص الإشعار قصير جدًا أو طويل جدًا',
  invalid_role: 'دور غير صالح',
  invalid_phone: 'رقم واتساب غير صالح (مثال: +218912345678)',
  cannot_change_self: 'لا يمكنك تعديل حسابك بنفسك',
  last_super_admin: 'لا يمكن إيقاف آخر مدير رئيسي',
  staff_not_found: 'الحساب الإداري غير موجود',
  unknown_setting: 'إعداد غير معروف',
  invalid_setting: 'قيمة الإعداد غير صالحة',
  notification_not_found: 'الإشعار غير موجود',
  release_not_found: 'الإصدار غير موجود',
  bootstrap_done: 'تمت التهيئة الأولى مسبقًا',
};

/** Arabic text for a refusal; never the raw database message. */
export function explain(e: unknown): string {
  const raw = e instanceof DbError ? e.code : e instanceof Error ? e.message : '';
  for (const [k, v] of Object.entries(messages)) {
    if (raw.includes(k)) return v;
  }
  return 'تعذّر تنفيذ العملية';
}
