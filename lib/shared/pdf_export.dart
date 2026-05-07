import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../features/transfers/domain/transfer.dart';
import 'formatters.dart';

class PdfExport {
  PdfExport._(this._regular, this._bold);
  final pw.Font _regular;
  final pw.Font _bold;

  static Future<PdfExport> load() async {
    final regular = await rootBundle.load(
      'assets/fonts/Almarai-Regular.ttf',
    );
    final bold = await rootBundle.load(
      'assets/fonts/Almarai-Bold.ttf',
    );
    return PdfExport._(pw.Font.ttf(regular), pw.Font.ttf(bold));
  }

  pw.ThemeData get _theme => pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
      );

  /// Builds a PDF for one of the daily / archive tables. Headers and rows
  /// are passed in so callers can drive the layout from their own data.
  Future<Uint8List> buildTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? totalLabel,
    String? totalValue,
  }) async {
    final doc = pw.Document(theme: _theme);
    final dataRows = <List<String>>[
      ...rows,
      if (totalLabel != null && totalValue != null)
        [
          totalLabel,
          ...List<String>.filled(headers.length - 2, '-'),
          totalValue,
        ],
    ];

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 18,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'تاريخ التصدير: ${dateTime.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.Divider(),
            pw.Expanded(
              child: pw.TableHelper.fromTextArray(
                headers: headers,
                data: dataRows,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11,
                ),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellAlignment: pw.Alignment.centerRight,
                cellPadding: const pw.EdgeInsets.all(4),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Landscape "سجل الحوالات اليومية" report. One row per transfer, eight
  /// RTL columns, total + spelled-out Arabic total below the table.
  Future<Uint8List> buildDailyTransfersReport({
    required List<Transfer> rows,
    required Map<String, String> companyNameById,
    required Map<String, String> exchangeNameById,
  }) async {
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final dayName = _arabicDayName(now);
    final dateStr = dateOnly.format(now);
    final timeStr = DateFormat('HH:mm').format(now);

    pw.Widget headerSection() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'سجل الحوالات اليومية',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 22,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'اليوم: $dayName    التاريخ: $dateStr    الوقت: $timeStr',
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.grey700,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 12),
          ],
        );

    if (rows.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          theme: _theme,
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                headerSection(),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'لا توجد سجلات',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return doc.save();
    }

    const headers = <String>[
      'ت',
      'الإشاري',
      'الشركة المنفذة',
      'من حساب',
      'المبلغ \$',
      'المستفيد',
      'حساب',
      'كود المستلم',
    ];

    final dataRows = <List<String>>[
      for (var i = 0; i < rows.length; i++)
        [
          '${i + 1}',
          rows[i].reference,
          exchangeNameById[rows[i].exchangeId] ?? '—',
          companyNameById[rows[i].companyId] ?? '—',
          '${formatMoney(rows[i].amount)} \$',
          rows[i].beneficiaryName,
          (rows[i].beneficiaryAccountCompany?.isEmpty ?? true)
              ? '—'
              : rows[i].beneficiaryAccountCompany!,
          (rows[i].beneficiaryCode?.isEmpty ?? true)
              ? '—'
              : rows[i].beneficiaryCode!,
        ],
    ];

    pw.Widget cell(String text, {required bool header}) => pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: header ? 6 : 4,
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: header ? 11 : 10,
              fontWeight:
                  header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            softWrap: false,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        );

    final reversedHeaders = headers.reversed.toList();
    final reversedDataRows = [
      for (final row in dataRows) row.reversed.toList(),
    ];

    final tableChildren = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF1F2F4),
        ),
        children: [for (final h in reversedHeaders) cell(h, header: true)],
      ),
      for (final row in reversedDataRows)
        pw.TableRow(
          children: [for (final c in row) cell(c, header: false)],
        ),
    ];

    final sum = rows.fold<double>(0, (a, r) => a + r.amount);
    final totalText = '${formatMoney(sum)} \$';
    final wordsText = _arabicNumberWords(sum.round());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                headerSection(),
                pw.Table(
                  border: pw.TableBorder(
                    top: const pw.BorderSide(
                      color: PdfColors.grey700,
                      width: 1.0,
                    ),
                    bottom: const pw.BorderSide(
                      color: PdfColors.grey700,
                      width: 1.0,
                    ),
                    left: const pw.BorderSide(
                      color: PdfColors.grey700,
                      width: 1.0,
                    ),
                    right: const pw.BorderSide(
                      color: PdfColors.grey700,
                      width: 1.0,
                    ),
                    horizontalInside: const pw.BorderSide(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                    verticalInside: const pw.BorderSide(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.2), // كود المستلم
                    1: pw.FlexColumnWidth(1.6), // حساب
                    2: pw.FlexColumnWidth(2.0), // المستفيد
                    3: pw.FlexColumnWidth(1.2), // المبلغ $
                    4: pw.FlexColumnWidth(2.0), // من حساب
                    5: pw.FlexColumnWidth(2.0), // الشركة المنفذة
                    6: pw.FlexColumnWidth(1.5), // الإشاري — bumped from 1.2 to 1.5
                    7: pw.FlexColumnWidth(0.6), // ت
                  },
                  children: tableChildren,
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'الإجمالي : $totalText',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 13,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'فقط $wordsText دولار أمريكي لا غير',
                        style: const pw.TextStyle(fontSize: 11),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Hand the bytes to the OS print/share sheet.
  static Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}

const _arabicDays = <String>[
  'الإثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

String _arabicDayName(DateTime d) => _arabicDays[d.weekday - 1];

const _ones = <String>[
  '',
  'واحد',
  'اثنان',
  'ثلاثة',
  'أربعة',
  'خمسة',
  'ستة',
  'سبعة',
  'ثمانية',
  'تسعة',
];

const _tens = <String>[
  'عشرة',
  'عشرون',
  'ثلاثون',
  'أربعون',
  'خمسون',
  'ستون',
  'سبعون',
  'ثمانون',
  'تسعون',
];

const _hundreds = <String>[
  '',
  'مائة',
  'مائتان',
  'ثلاثمائة',
  'أربعمائة',
  'خمسمائة',
  'ستمائة',
  'سبعمائة',
  'ثمانمائة',
  'تسعمائة',
];

String _wordsLessThan100(int n) {
  if (n == 0) return '';
  if (n < 10) return _ones[n];
  if (n == 10) return 'عشرة';
  if (n == 11) return 'أحد عشر';
  if (n == 12) return 'اثنا عشر';
  if (n < 20) return '${_ones[n - 10]} عشر';
  final t = n ~/ 10;
  final u = n % 10;
  final tensWord = _tens[t - 1];
  if (u == 0) return tensWord;
  return '${_ones[u]} و$tensWord';
}

String _wordsLessThan1000(int n) {
  if (n == 0) return '';
  final h = n ~/ 100;
  final r = n % 100;
  if (h == 0) return _wordsLessThan100(r);
  final hundredWord = _hundreds[h];
  if (r == 0) return hundredWord;
  return '$hundredWord و${_wordsLessThan100(r)}';
}

String _arabicNumberWords(int n) {
  if (n == 0) return 'صفر';
  if (n < 0) return 'سالب ${_arabicNumberWords(-n)}';

  final millions = n ~/ 1000000;
  final thousands = (n ~/ 1000) % 1000;
  final units = n % 1000;
  final parts = <String>[];

  if (millions > 0) {
    if (millions == 1) {
      parts.add('مليون');
    } else if (millions == 2) {
      parts.add('مليونان');
    } else if (millions <= 10) {
      parts.add('${_wordsLessThan1000(millions)} ملايين');
    } else {
      parts.add('${_wordsLessThan1000(millions)} مليون');
    }
  }

  if (thousands > 0) {
    if (thousands == 1) {
      parts.add('ألف');
    } else if (thousands == 2) {
      parts.add('ألفان');
    } else if (thousands <= 10) {
      parts.add('${_wordsLessThan1000(thousands)} آلاف');
    } else {
      parts.add('${_wordsLessThan1000(thousands)} ألف');
    }
  }

  if (units > 0) {
    parts.add(_wordsLessThan1000(units));
  }

  return parts.join(' و');
}
