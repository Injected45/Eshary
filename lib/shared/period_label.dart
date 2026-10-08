import 'package:intl/intl.dart';

/// "الفترة": one date when [start] and [end] are the same day, otherwise
/// "من … إلى …". Plain words: an arrow glyph is missing from the PDF fonts and
/// prints as an empty box.
String periodLabel(DateTime start, DateTime end) {
  final f = DateFormat('yyyy/MM/dd');
  final a = f.format(start);
  final b = f.format(end);
  return a == b ? a : 'من $a إلى $b';
}
