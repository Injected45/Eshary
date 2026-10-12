import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Times in the PDF reports (02:14) are drawn with a bigger, bold colon so it
/// stays clear in the small table text.
void main() {
  final core = File('lib/shared/pdf_export.dart').readAsStringSync();
  final period = File('lib/shared/pdf_export_period.dart').readAsStringSync();

  test('one helper draws the colon of a clock bigger and bold', () {
    expect(core, contains('pw.Widget _clockText('));
    expect(core, contains('fontSize: (style.fontSize ?? 8) + 4'));
    expect(core, contains('fontWeight: pw.FontWeight.bold'));
  });

  test('every report cell and the export footer use it', () {
    final cell = period.substring(period.indexOf('pw.Widget _reportCell'));
    expect(cell.substring(0, cell.indexOf('/// The report table')),
        contains('_clockText('));
    final footer =
        core.substring(core.indexOf('pw.Widget _exportFooter'));
    expect(footer.substring(0, footer.indexOf('class PdfExport')),
        contains('_clockText('));
  });
}
