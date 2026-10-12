import 'package:intl/intl.dart';

/// Every time the app shows is the SERVER's moment (stamped by the database in
/// UTC) moved to Libya time, UTC+2 all year (Libya has no daylight saving), in
/// 24-hour form. It never depends on the phone's time zone or on its 12/24-hour
/// setting, so the same operation shows the same hour on every phone, in the
/// screens and in the PDF reports.
DateTime libyaTime(DateTime t) => t.toUtc().add(const Duration(hours: 2));

extension LibyaTime on DateTime {
  /// This moment on the Libya wall clock.
  DateTime get libya => libyaTime(this);
}

/// A [DateFormat] that always shows the moment in Libya time (see [libyaTime]).
/// Give it ANY instant (UTC or the phone's local DateTime: both name the same
/// moment); it converts exactly once, here. Use it for every time the app
/// shows, so no screen can show the phone's zone or UTC by mistake.
class LibyaDateFormat extends DateFormat {
  LibyaDateFormat(String pattern) : super(pattern);

  @override
  String format(DateTime date) => super.format(libyaTime(date));
}
