import 'dart:io';

import 'package:eshary/shared/pdf_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shared PDF is recognised by its name (WhatsApp shows only the name).
void main() {
  final d8 = DateTime(2026, 10, 8, 9);
  final d1 = DateTime(2026, 10, 1);

  test('one account', () {
    expect(
      pdfFileName(
        'كشف حساب الرحالة الأولى لدى شركة بهار روز',
        start: d8,
        end: d8,
      ),
      'كشف حساب الرحالة الأولى لدى شركة بهار روز - 2026-10-08.pdf',
    );
  });

  test('all accounts, one employee, a period', () {
    expect(
      pdfFileName(
        'كشف حساب جميع الحسابات',
        who: 'الموظف رافع المهدي',
        start: d1,
        end: d8,
      ),
      'كشف حساب جميع الحسابات - الموظف رافع المهدي - من 2026-10-01 إلى 2026-10-08.pdf',
    );
  });

  test('cancellations', () {
    expect(
      pdfFileName('كشف الإلغاءات', start: d8, end: d8),
      'كشف الإلغاءات - 2026-10-08.pdf',
    );
  });

  test('characters a file name cannot hold are removed', () {
    final name = pdfFileName('كشف/حساب: "أ" <ب> | ج? *', start: d8);
    expect(name, 'كشف حساب أ ب ج - 2026-10-08.pdf');
    expect(name, isNot(matches(RegExp(r'[\\/:*?"<>|]'))));
  });

  test('a very long title stays a valid file name', () {
    final name = pdfFileName('كشف ' * 80, start: d8);
    expect(name.length, lessThanOrEqualTo(114));
    expect(name, endsWith('.pdf'));
  });

  test('no date given: today', () {
    final now = DateTime.now();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    expect(pdfFileName('سجل خروج الحوالات اليوم'), 'سجل خروج الحوالات اليوم - $day.pdf');
  });

  test('every shared PDF is named in Arabic by pdfFileName', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'sharePdf\(([\s\S]*?)\);').allMatches(src)) {
        final call = m.group(1)!;
        if (call.contains('Uint8List bytes')) continue; // the definition
        if (!call.contains('pdfFileName(') && !call.contains('filename')) {
          offenders.add('${f.path}: $call');
        }
        if (RegExp(r"'[a-z_]+\.pdf'").hasMatch(call)) {
          offenders.add('${f.path}: English name: $call');
        }
      }
      if (RegExp(r"'[a-z_]+(_\$\{[^}]+\})*\.pdf'").hasMatch(src)) {
        offenders.add('${f.path}: English file name left');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the daily reports no longer say "غير مرحلة"', () {
    final src = File('lib/shared/pdf_export.dart').readAsStringSync();
    expect(src, isNot(contains('غير مرحلة')));
    expect(src, isNot(contains('غير المرحلة')));
    expect(src, contains("'سجل خروج الحوالات اليوم'"));
    expect(src, contains("'سجل دخول الحوالات اليوم'"));
  });
}
