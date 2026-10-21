const zone = 'Africa/Tripoli';

export function fmtDateTime(v: string | null | undefined): string {
  if (!v) return '—';
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return '—';
  return new Intl.DateTimeFormat('ar-LY-u-nu-latn', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(d);
}

export function fmtDate(v: string | null | undefined): string {
  if (!v) return '—';
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return '—';
  return new Intl.DateTimeFormat('ar-LY-u-nu-latn', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d);
}

export const statusLabel: Record<string, string> = {
  pending: 'بانتظار التفعيل',
  trial: 'تجريبي',
  active: 'مفعّل',
  expired: 'منتهي',
  blocked: 'موقوف',
};

export const statusTone: Record<string, string> = {
  pending: 'warn',
  trial: 'info',
  active: 'ok',
  expired: 'muted',
  blocked: 'bad',
};

export const roleLabel: Record<string, string> = {
  super_admin: 'مدير رئيسي',
  admin: 'مدير التطبيق',
  support: 'دعم فني',
  viewer: 'مراقب',
};

export const auditLabel: Record<string, string> = {
  platform_login_ok: 'دخول ناجح للمنصة',
  platform_login_failed: 'محاولة دخول فاشلة',
  platform_login_denied: 'دخول مرفوض',
  platform_code_sent: 'إرسال رمز التحقق',
  platform_code_refused: 'رفض إرسال رمز',
  platform_logout: 'تسجيل خروج',
  platform_staff_added: 'إضافة حساب إداري',
  platform_staff_changed: 'تعديل حساب إداري',
  platform_setting_changed: 'تعديل إعداد',
  notification_created: 'إنشاء إشعار',
  notification_toggled: 'تفعيل/إيقاف إشعار',
  user_notes_changed: 'تعديل ملاحظات مستخدم',
  trial_extended: 'تمديد تجربة',
  payment_confirmed: 'تأكيد دفع',
  account_suspended: 'إيقاف حساب',
  account_reactivated: 'إعادة تفعيل حساب',
};
