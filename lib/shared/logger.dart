import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLogKey = 'app_logs_v1';
const _kMaxEntries = 200;

class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final String level;
  final String message;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toIso8601String(),
        'lvl': level,
        'msg': message,
        if (error != null) 'err': error,
        if (stackTrace != null) 'st': stackTrace,
      };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        timestamp: DateTime.parse(j['ts'] as String),
        level: j['lvl'] as String,
        message: j['msg'] as String,
        error: j['err'] as String?,
        stackTrace: j['st'] as String?,
      );
}

class AppLogger {
  AppLogger._();

  static SharedPreferences? _prefs;

  static void init(SharedPreferences prefs) {
    _prefs = prefs;
  }

  static List<LogEntry> readAll() {
    final raw = _prefs?.getString(_kLogKey);
    if (raw == null || raw.isEmpty) return <LogEntry>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map(LogEntry.fromJson)
          .toList();
    } catch (_) {
      return <LogEntry>[];
    }
  }

  static Future<void> clear() async {
    await _prefs?.remove(_kLogKey);
  }

  static void info(String message) {
    _append(LogEntry(
      timestamp: DateTime.now(),
      level: 'info',
      message: message,
    ));
  }

  static void warning(String message, [Object? error, StackTrace? st]) {
    _append(LogEntry(
      timestamp: DateTime.now(),
      level: 'warning',
      message: message,
      error: error?.toString(),
      stackTrace: st?.toString(),
    ));
  }

  static void error(String message, [Object? error, StackTrace? st]) {
    _append(LogEntry(
      timestamp: DateTime.now(),
      level: 'error',
      message: message,
      error: error?.toString(),
      stackTrace: st?.toString(),
    ));
  }

  static void _append(LogEntry entry) {
    if (kDebugMode) {
      debugPrint(
        '[${entry.level}] ${entry.message}'
        '${entry.error != null ? " — ${entry.error}" : ""}',
      );
    }
    final p = _prefs;
    if (p == null) return;
    final list = readAll();
    list.add(entry);
    if (list.length > _kMaxEntries) {
      list.removeRange(0, list.length - _kMaxEntries);
    }
    p.setString(
      _kLogKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }
}

/// Translate a raw exception into a short Arabic user-facing message.
String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('client_has_operations')) {
    return 'لا يمكن حذف هذه الجهة لارتباطها بعمليات مالية سابقة.';
  }
  if (s.contains('current_license_status') ||
      s.contains('account_licenses')) {
    return 'تعذّر التحقق من حالة الحساب.';
  }
  if (s.contains('pending currency buy') ||
      (s.contains('check_violation') && s.contains('pending'))) {
    return 'لا يمكن الترحيل: توجد عمليات شراء معلّقة. أكملها أو احذفها أولًا.';
  }
  if (s.contains('23503') || s.contains('foreign key constraint')) {
    return 'لا يمكن إتمام العملية: توجد بيانات مرتبطة. احذف العناصر التابعة أو رحّلها أولًا.';
  }
  if (s.contains('sub_users_phone_unique')) {
    return 'رقم الهاتف مسجَّل بالفعل لموظف آخر تابع لك. استخدم رقماً مختلفاً أو احذف الموظف الموجود.';
  }
  if (s.contains('branches_name_unique')) {
    return 'اسم الفرع مسجَّل بالفعل. استخدم اسماً مختلفاً.';
  }
  if (s.contains('23505') || s.contains('duplicate key')) {
    return 'هذا العنصر موجود مسبقًا.';
  }
  if (s.contains('not authorized') ||
      s.contains('permission denied') ||
      s.contains('42501')) {
    return 'غير مصرح بهذا الإجراء.';
  }
  if (s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection')) {
    return 'تعذّر الاتصال بالخادم. تحقق من الاتصال بالإنترنت.';
  }
  if (s.contains('Invalid login credentials')) {
    return 'بيانات الدخول غير صحيحة.';
  }
  if (s.contains('Email not confirmed')) {
    return 'البريد الإلكتروني غير مؤكد.';
  }
  if (s.contains('invalid_credentials')) {
    return 'رقم الهاتف أو كود الدخول غير صحيح.';
  }
  if (s.contains('device_mismatch')) {
    return 'هذا الحساب مرتبط بجهاز آخر. يرجى التواصل مع المدير لإعادة تفعيل الجهاز.';
  }
  if (s.contains('invalid_qr')) {
    return 'رمز QR غير صالح أو منتهي أو مستخدم. اطلب من المدير إصدار رمز جديد.';
  }
  if (s.contains('permission_denied')) {
    return 'ليست لديك صلاحية لهذا الإجراء. تواصل مع المدير.';
  }
  if (s.contains('insufficient_balance')) {
    return 'الرصيد المتاح في الحساب لا يكفي لهذه الحوالة. تحقق من الرصيد المتاح.';
  }
  if (s.contains('empty_message')) {
    return 'اكتب نص الرسالة أولاً.';
  }
  if (s.contains('no_recipients')) {
    return 'لا يوجد موظفون فعّالون لإرسال الرسالة إليهم.';
  }
  if (s.contains('invalid_recipients')) {
    return 'أحد الموظفين المختارين غير متاح. حدّث القائمة وأعد المحاولة.';
  }
  if (s.contains('license_inactive')) {
    return 'حساب الشركة غير مفعّل أو منتهٍ. تواصل مع الإدارة.';
  }
  if (s.contains('invalid_email_code')) {
    return 'رمز البريد الإلكتروني غير صحيح أو منتهي.';
  }
  if (s.contains('email_send_failed')) {
    return 'تعذّر إرسال رمز البريد الإلكتروني. تأكد من البريد وأعد المحاولة.';
  }
  if (s.contains('invalid_phone')) {
    return 'رقم الهاتف بالصيغة 09XXXXXXXX (10 أرقام).';
  }
  if (s.contains('identity_mismatch')) {
    return 'هذا البريد مسجَّل برقم هاتف مختلف. أدخل رقم الهاتف الذي سجّلت به.';
  }
  if (s.contains('phone_taken')) {
    return 'رقم الهاتف هذا مسجَّل لحساب آخر.';
  }
  if (s.contains('busy')) {
    return 'الخدمة مشغولة حالياً. حاول بعد قليل.';
  }
  if (s.contains('create_failed') || s.contains('link_failed') ||
      s.contains('server_error')) {
    return 'تعذّر إكمال الدخول الآن. حاول مرة أخرى بعد قليل.';
  }
  if (s.contains('invalid_otp')) {
    return 'رمز التحقق غير صحيح.';
  }
  if (s.contains('otp_expired')) {
    return 'انتهت صلاحية رمز التحقق. اطلب رمزاً جديداً.';
  }
  if (s.contains('too_many_attempts')) {
    return 'تجاوزت عدد المحاولات. انتظر قليلاً أو اطلب من المدير كوداً أو QR جديداً.';
  }
  if (s.contains('too_many_sends')) {
    return 'تم إرسال عدد كبير من الرموز. اطلب من المدير إصدار QR جديد أو حاول لاحقاً.';
  }
  if (s.contains('too_soon')) {
    return 'انتظر قليلاً قبل طلب رمز جديد.';
  }
  if (s.contains('send_failed')) {
    return 'تعذّر إرسال الرمز عبر واتساب. أعد المحاولة بعد قليل.';
  }
  if (s.contains('sms_not_configured')) {
    return 'خدمة إرسال الرموز غير مُعدّة بعد. تواصل مع المدير.';
  }
  if (s.contains('otp_required')) {
    return 'يجب تأكيد رمز التحقق أولاً.';
  }
  if (s.contains('email_mismatch')) {
    return 'هذا الإيميل لا يطابق الإيميل المسجَّل لدى المدير لهذا الموظف. استخدم الحساب الذي سجّله المدير.';
  }
  if (s.contains('email_required')) {
    return 'سجّل إيميل الموظف أولاً من بطاقته ثم أصدر الـ QR.';
  }
  if (s.contains('invalid_email')) {
    return 'صيغة البريد الإلكتروني غير صحيحة.';
  }
  if (s.contains('sub_user_disabled')) {
    return 'هذا الموظف معطّل. فعّله أولاً لإصدار QR.';
  }
  if (s.contains('device_id_required')) {
    return 'تعذّر التعرف على الجهاز.';
  }
  if (s.contains('not_authenticated')) {
    return 'فشل بدء الجلسة. أعد المحاولة.';
  }
  if (s.contains('Anonymous sign-ins are disabled')) {
    return 'تسجيل الدخول كموظف غير مُفعّل في إعدادات Supabase.';
  }
  return 'حدث خطأ غير متوقع. تم تسجيل الحدث.';
}
