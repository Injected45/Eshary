import 'dart:io';

import 'package:eshary/shared/libya_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every time is the server's moment shown on the Libya clock (UTC+2), in
/// 24-hour form, and drawn in the PDFs as one left-to-right group "HH:mm".
void main() {
  group('Libya time', () {
    test('UTC is moved two hours forward, 24-hour', () {
      final t = DateTime.utc(2026, 10, 12, 2, 55);
      expect(LibyaDateFormat('HH:mm').format(t), '04:55');
      expect(LibyaDateFormat('yyyy-MM-dd HH:mm').format(t), '2026-10-12 04:55');
    });

    test('after 22:00 UTC it is already the next day in Libya', () {
      final t = DateTime.utc(2026, 10, 12, 22, 30);
      expect(LibyaDateFormat('yyyy-MM-dd HH:mm').format(t), '2026-10-13 00:30');
    });

    test('afternoon stays 24-hour (no AM/PM, no 12-hour)', () {
      final t = DateTime.utc(2026, 10, 12, 16, 5);
      expect(LibyaDateFormat('HH:mm').format(t), '18:05');
    });

    test('the phone\'s own zone does not matter: local and UTC agree', () {
      final utc = DateTime.utc(2026, 10, 12, 8, 0);
      final local = utc.toLocal(); // the same moment on the phone's clock
      expect(LibyaDateFormat('HH:mm').format(local),
          LibyaDateFormat('HH:mm').format(utc));
    });
  });

  group('PDF clock drawing', () {
    final core = File('lib/shared/pdf_export.dart').readAsStringSync();
    final period = File('lib/shared/pdf_export_period.dart').readAsStringSync();

    test('hour, colon and minutes are one left-to-right group', () {
      expect(core, contains('pw.Widget _clockGroup('));
      final group = core.substring(core.indexOf('pw.Widget _clockGroup('));
      final body = group.substring(0, group.indexOf('pw.Widget _clockText('));
      expect(body, contains('textDirection: pw.TextDirection.ltr'));
      // the colon is bold at the SAME size as the digits (not enlarged)
      expect(
          body,
          contains(
              "piece(':', style.copyWith(fontWeight: pw.FontWeight.bold))"));
      expect(body, isNot(contains('fontSize:')));
    });

    test('every report cell and the export footer use it', () {
      final cell = period.substring(period.indexOf('pw.Widget _reportCell'));
      expect(cell.substring(0, cell.indexOf('/// The report table')),
          contains('_clockText('));
      final footer = core.substring(core.indexOf('pw.Widget _exportFooter'));
      expect(footer.substring(0, footer.indexOf('class PdfExport')),
          contains('_clockText('));
    });

    test('the PDFs show Libya time (never the raw UTC hour)', () {
      expect(period,
          isNot(contains("DateFormat('HH:mm')"))); // all go through _LibyaFmt
      expect(period, contains("_LibyaFmt('HH:mm')"));
      expect(core, contains('libyaTime(at)'));
    });
  });

  test('no screen formats a time with the plain, zone-dependent DateFormat',
      () {
    final offenders = <String>[];
    final skip = [
      'libya_time.dart',
      'pdf_export.dart',
      'pdf_export_period.dart',
      'transaction_details.dart',
      'period_label.dart',
      'pdf_file_name.dart',
      'archive_filters.dart'
    ];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (skip.any(f.path.endsWith)) continue;
      final src = f.readAsStringSync();
      // a pattern with an hour in it, built with the plain DateFormat
      if (RegExp(r"(?<!Libya)DateFormat\('[^']*[Hh][^']*'\)").hasMatch(src)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
