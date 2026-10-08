import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Times are shown on a 24-hour clock (00:23, 13:05): many people do not tell
/// AM from PM.
void main() {
  test('no 12-hour clock format is left in the app', () {
    final bad = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        // 'hh' / 'h' hours or the AM/PM marker 'a' in a DateFormat pattern
        if (RegExp(r"DateFormat\('[^']*\bhh?:mm[^']*'").hasMatch(l) ||
            RegExp(r"DateFormat\('[^']*mm\s*a'").hasMatch(l) ||
            l.contains('DateFormat.jm') ||
            l.contains('DateFormat.Hm') == false && l.contains('.jm(')) {
          bad.add('${f.path}:${i + 1}: ${l.trim()}');
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('the formats print midnight and the afternoon as 24-hour times', () {
    final f = DateFormat('HH:mm');
    expect(f.format(DateTime(2026, 10, 9, 0, 23)), '00:23');
    expect(f.format(DateTime(2026, 10, 9, 12, 5)), '12:05');
    expect(f.format(DateTime(2026, 10, 9, 13, 5)), '13:05');
    expect(f.format(DateTime(2026, 10, 9, 23, 59)), '23:59');
    expect(
      DateFormat('yyyy-MM-dd | HH:mm').format(DateTime(2026, 10, 9, 0, 23)),
      '2026-10-09 | 00:23',
    );
  });
}
