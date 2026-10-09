import 'package:intl/intl.dart';

/// The name a shared PDF carries outside (WhatsApp, Files…): the same title
/// that is printed at the top of the report, then whose operations it is,
/// then the period, e.g.
///
///   كشف حساب الرحالة الأولى لدى شركة بهار روز - 2026-10-08.pdf
///   تفاصيل حركة الدخول والخروج للحوالات - الموظف رافع المهدي - من 2026-10-01 إلى 2026-10-08.pdf
///
/// so a file is recognised by its name without opening it. Characters a file
/// name cannot hold ( / \ : * ? " < > | ) become spaces.
String pdfFileName(
  String title, {
  String? who,
  DateTime? start,
  DateTime? end,
}) {
  final parts = <String>[
    _clean(title),
    if (who != null && _clean(who).isNotEmpty) _clean(who),
    _period(start, end),
  ];
  var name = parts.where((p) => p.isNotEmpty).join(' - ');
  // Keep it well inside the 255-byte limit of a file name (Arabic letters
  // take two bytes each).
  if (name.length > 110) name = name.substring(0, 110).trim();
  return '$name.pdf';
}

String _clean(String s) => s
    .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _day = DateFormat('yyyy-MM-dd');

String _period(DateTime? start, DateTime? end) {
  final a = start ?? end ?? DateTime.now();
  final b = end ?? a;
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  return sameDay ? _day.format(a) : 'من ${_day.format(a)} إلى ${_day.format(b)}';
}
