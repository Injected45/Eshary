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
