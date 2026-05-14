import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../features/clients/domain/client.dart';
import '../features/companies/domain/company.dart';
import '../features/companies/domain/exchange.dart';
import '../features/currency_buy/domain/currency_buy.dart';
import '../features/transfers/domain/transfer.dart';
import 'formatters.dart';

class PdfExport {
  PdfExport._(this._regular, this._bold, this._fallback, this._fallbackBold);
  final pw.Font _regular;
  final pw.Font _bold;
  final pw.Font _fallback;
  final pw.Font _fallbackBold;

  static Future<PdfExport> load() async {
    final regular = await rootBundle.load(
      'assets/fonts/Almarai-Regular.ttf',
    );
    final bold = await rootBundle.load(
      'assets/fonts/Almarai-Bold.ttf',
    );
    // Noto Naskh handles glyphs Almarai renders poorly (e.g. hamza-below إ).
    final fallback = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final fallbackBold = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Bold.ttf',
    );
    return PdfExport._(
      pw.Font.ttf(regular),
      pw.Font.ttf(bold),
      pw.Font.ttf(fallback),
      pw.Font.ttf(fallbackBold),
    );
  }

  pw.ThemeData get _theme => pw.ThemeData.withFont(
        base: _regular,
        bold: _bold,
        fontFallback: [_fallback, _fallbackBold],
      );

  /// Builds a PDF for one of the daily / archive tables. Headers and rows
  /// are passed in so callers can drive the layout from their own data.
  Future<Uint8List> buildTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? totalLabel,
    String? totalValue,
    String? notificationText,
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

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
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
                    ],
                  ),
                ),
                if (notificationText != null &&
                    notificationText.trim().isNotEmpty)
                  _notificationBox(notificationText.trim())
                else if (logoImage != null)
                  pw.SizedBox(width: 52),
              ],
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
    String? notificationText,
    String? exportedBy,
    String? employeeName,
  }) async {
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final dayName = _arabicDayName(now);
    final dateStr = dateOnly.format(now);
    final timeStr = DateFormat('HH:mm').format(now);

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pw.Widget headerSection() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (notificationText != null &&
                    notificationText.trim().isNotEmpty)
                  _notificationBox(notificationText.trim())
                else
                  pw.SizedBox(width: 52),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'سجل خروج الحوالات غير مرحلة',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 22,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                if (logoImage != null)
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(left: 8),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Spacer(),
                pw.Text(
                  'اليوم: $dayName    التاريخ: $dateStr    الوقت: $timeStr',
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
            // Employee identity strip — shown only when an employee
            // generated the PDF. Right-aligned (start of an RTL row).
            if (employeeName != null && employeeName.trim().isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFEFF4FB),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                      border: pw.Border.all(
                        color: const PdfColor.fromInt(0xFFC9D7E8),
                        width: 0.6,
                      ),
                    ),
                    child: pw.Text(
                      'اسم الموظف: ${employeeName.trim()}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: PdfColors.blueGrey800,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
              ),
            ],
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
                pw.Container(
                  alignment: pw.Alignment.centerLeft,
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return doc.save();
    }

    // Logical order (right→left): ت | الإشاري | من حسابي | في شركة (المُنفِذة)
    // | المبلغ | في شركة (المستفيد) | الى المستفيد | كود رقم
    const headers = <String>[
      'ت',
      'الإشاري',
      'من حسابي',
      'في شركة',
      'المبلغ',
      'في شركة',
      'الى المستفيد',
      'كود رقم',
    ];

    final dataRows = <List<String>>[
      for (var i = 0; i < rows.length; i++)
        [
          '${i + 1}',
          rows[i].reference,
          companyNameById[rows[i].companyId] ?? '—',
          exchangeNameById[rows[i].exchangeId] ?? '—',
          '${formatMoney(rows[i].amount)} \$',
          (rows[i].beneficiaryAccountCompany?.isEmpty ?? true)
              ? '—'
              : rows[i].beneficiaryAccountCompany!,
          rows[i].beneficiaryName.isEmpty ? '—' : rows[i].beneficiaryName,
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
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
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
                  // Reversed indices: 0 = leftmost (كود رقم) … 7 = rightmost (ت).
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.2), // كود رقم
                    1: pw.FlexColumnWidth(2.0), // الى المستفيد
                    2: pw.FlexColumnWidth(1.8), // في شركة (المستفيد)
                    3: pw.FlexColumnWidth(1.2), // المبلغ
                    4: pw.FlexColumnWidth(1.8), // في شركة (المنفِّذة)
                    5: pw.FlexColumnWidth(2.0), // من حسابي
                    6: pw.FlexColumnWidth(1.5), // الإشاري
                    7: pw.FlexColumnWidth(0.6), // ت
                  },
                  children: tableChildren,
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 4),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: pw.BoxDecoration(
                    gradient: const pw.LinearGradient(
                      colors: [
                        PdfColor.fromInt(0xFFFFF5F5),
                        PdfColor.fromInt(0xFFFFFFFF),
                      ],
                      begin: pw.Alignment.centerRight,
                      end: pw.Alignment.centerLeft,
                    ),
                    borderRadius: pw.BorderRadius.all(
                      pw.Radius.circular(12),
                    ),
                    border: pw.Border.all(
                      color: const PdfColor.fromInt(0xFFEAC8C8),
                      width: 1.0,
                    ),
                  ),
                  child: pw.Directionality(
                    textDirection: pw.TextDirection.rtl,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.red800,
                                borderRadius: pw.BorderRadius.all(
                                  pw.Radius.circular(6),
                                ),
                              ),
                              child: pw.Text(
                                'الإجمالي',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                  color: PdfColors.white,
                                ),
                                textDirection: pw.TextDirection.rtl,
                              ),
                            ),
                            pw.SizedBox(width: 12),
                            pw.Text(
                              totalText,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 17,
                                color: PdfColors.red800,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ],
                        ),
                        pw.Container(
                          width: 0.8,
                          height: 28,
                          margin: const pw.EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          color: const PdfColor.fromInt(0xFFEAC8C8),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            'فقط $wordsText دولار أمريكي لا غير',
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: PdfColors.grey800,
                            ),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.left,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
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

  /// "سجل دخول الحوالات غير المرحلة" — landscape A4 report mirroring
  /// `buildDailyTransfersReport` but for incoming currency buys. Columns
  /// (right→left): ت | دخول من شركة | حساب | الإشاري | القيمة | لشركة |
  /// حسابي | كود.
  Future<Uint8List> buildDailyBuysReport({
    required List<CurrencyBuy> rows,
    required Map<String, String> companyNameById,
    required Map<String, Exchange> exchangeById,
    required Map<String, Client> clientById,
    String? notificationText,
    String? exportedBy,
    String? employeeName,
  }) async {
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final dayName = _arabicDayName(now);
    final dateStr = dateOnly.format(now);
    final timeStr = DateFormat('HH:mm').format(now);

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pw.Widget headerSection() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (notificationText != null &&
                    notificationText.trim().isNotEmpty)
                  _notificationBox(notificationText.trim())
                else
                  pw.SizedBox(width: 52),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'سجل دخول الحوالات غير المرحلة',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 22,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                if (logoImage != null)
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(left: 8),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Spacer(),
                pw.Text(
                  'اليوم: $dayName    التاريخ: $dateStr    الوقت: $timeStr',
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
            // Employee identity strip — shown only when an employee
            // generated the PDF. Right-aligned (start of an RTL row).
            if (employeeName != null && employeeName.trim().isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFEFF4FB),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                      border: pw.Border.all(
                        color: const PdfColor.fromInt(0xFFC9D7E8),
                        width: 0.6,
                      ),
                    ),
                    child: pw.Text(
                      'اسم الموظف: ${employeeName.trim()}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: PdfColors.blueGrey800,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
              ),
            ],
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
                pw.Container(
                  alignment: pw.Alignment.centerLeft,
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return doc.save();
    }

    // Logical order (right→left): ت | دخول من شركة | حساب | الإشاري |
    // القيمة | لشركة | حسابي | كود
    const headers = <String>[
      'ت',
      'دخول من شركة',
      'حساب',
      'الإشاري',
      'القيمة',
      'لشركة',
      'حسابي',
      'كود',
    ];

    String senderCompanyOf(CurrencyBuy b) {
      final c = clientById[b.clientId];
      final fromClient = (c?.company ?? '').trim();
      if (fromClient.isNotEmpty) return fromClient;
      final fromAccount = (b.clientFromAccount ?? '').trim();
      return fromAccount.isEmpty ? '—' : fromAccount;
    }

    final dataRows = <List<String>>[
      for (var i = 0; i < rows.length; i++)
        [
          '${i + 1}',
          senderCompanyOf(rows[i]),
          clientById[rows[i].clientId]?.name ?? '—',
          rows[i].reference.isEmpty ? '—' : rows[i].reference,
          '${formatMoney(rows[i].usdAmount)} \$',
          exchangeById[rows[i].exchangeId]?.name ?? '—',
          companyNameById[rows[i].myCompanyId] ?? '—',
          (exchangeById[rows[i].exchangeId]?.ourCode ?? '').trim().isEmpty
              ? '—'
              : exchangeById[rows[i].exchangeId]!.ourCode!,
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

    final sum = rows.fold<double>(0, (a, r) => a + r.usdAmount);
    final totalText = '${formatMoney(sum)} \$';
    final wordsText = _arabicNumberWords(sum.round());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey600,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
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
                  // Reversed indices: 0 = leftmost (كود) … 7 = rightmost (ت).
                  columnWidths: const {
                    0: pw.FlexColumnWidth(0.9), // كود
                    1: pw.FlexColumnWidth(1.6), // حسابي
                    2: pw.FlexColumnWidth(1.8), // لشركة
                    3: pw.FlexColumnWidth(1.2), // القيمة
                    4: pw.FlexColumnWidth(1.5), // الإشاري
                    5: pw.FlexColumnWidth(1.6), // حساب
                    6: pw.FlexColumnWidth(2.0), // دخول من شركة
                    7: pw.FlexColumnWidth(0.6), // ت
                  },
                  children: tableChildren,
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 4),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  decoration: pw.BoxDecoration(
                    gradient: const pw.LinearGradient(
                      colors: [
                        PdfColor.fromInt(0xFFF0FBF1),
                        PdfColor.fromInt(0xFFFFFFFF),
                      ],
                      begin: pw.Alignment.centerRight,
                      end: pw.Alignment.centerLeft,
                    ),
                    borderRadius: pw.BorderRadius.all(
                      pw.Radius.circular(12),
                    ),
                    border: pw.Border.all(
                      color: const PdfColor.fromInt(0xFFCBE7D0),
                      width: 1.0,
                    ),
                  ),
                  child: pw.Directionality(
                    textDirection: pw.TextDirection.rtl,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.green800,
                                borderRadius: pw.BorderRadius.all(
                                  pw.Radius.circular(6),
                                ),
                              ),
                              child: pw.Text(
                                'الإجمالي',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                  color: PdfColors.white,
                                ),
                                textDirection: pw.TextDirection.rtl,
                              ),
                            ),
                            pw.SizedBox(width: 12),
                            pw.Text(
                              totalText,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 17,
                                color: PdfColors.green800,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ],
                        ),
                        pw.Container(
                          width: 0.8,
                          height: 28,
                          margin: const pw.EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          color: const PdfColor.fromInt(0xFFCBE7D0),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            'فقط $wordsText دولار أمريكي لا غير',
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: PdfColors.grey800,
                            ),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.left,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
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

  /// "تفاصيل حركة الدخول والخروج للحوالات" — landscape A4. One row per
  /// archived buy/transfer inside the selected period. Columns:
  /// ت | الوقت | التاريخ | النوع | إشاري | إشاري المرسل | قيمة العملية |
  /// الرصيد قبل | الرصيد بعد | فرق تراكمي | حساباتي | الجهة
  Future<Uint8List> buildDetailedTransfersReport({
    required List<CurrencyBuy> buys,
    required List<Transfer> transfers,
    required Map<String, Company> companyById,
    required Map<String, Exchange> exchangeById,
    required Map<String, Client> clientById,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
    String? notificationText,
    String? employeeName,
  }) async {
    final doc = pw.Document(theme: _theme);
    final dayFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('hh:mm a');
    final exportFmt = DateFormat('yyyy-MM-dd | hh:mm a');

    String slash(String? a, String? b) {
      final x = (a ?? '').trim();
      final y = (b ?? '').trim();
      if (x.isEmpty && y.isEmpty) return '—';
      if (x.isEmpty) return y;
      if (y.isEmpty) return x;
      return '$x / $y';
    }

    final ops = <_DetailedOp>[];
    for (final b in buys) {
      final myCompany = companyById[b.myCompanyId]?.name;
      final myExchangeRow = exchangeById[b.exchangeId];
      final myExchange = myExchangeRow?.name;
      final myCode = (myExchangeRow?.ourCode ?? '').trim();
      final client = b.clientId != null ? clientById[b.clientId!] : null;
      final partyCompany = client?.company ?? '';
      final partyName = client?.name ?? b.clientFromAccount ?? '';
      ops.add(
        _DetailedOp(
          t: b.archivedAt ?? b.createdAt,
          kind: 'دخول',
          isIncome: true,
          // For دخول: own column shows MY account code (وجهة الدخول),
          // sender column shows the reference that arrived from الجهة المرسلة.
          reference: myCode.isEmpty ? '—' : myCode,
          senderReference: b.reference.isEmpty ? '—' : b.reference,
          amount: b.usdAmount,
          myAccount: slash(myCompany, myExchange),
          party: slash(partyCompany, partyName),
        ),
      );
    }
    for (final t in transfers) {
      final myCompany = companyById[t.companyId]?.name;
      final myExchange = exchangeById[t.exchangeId]?.name;
      ops.add(
        _DetailedOp(
          t: t.archivedAt ?? t.createdAt,
          kind: 'خروج',
          isIncome: false,
          // For خروج: own column shows my transfer reference, sender
          // column shows the beneficiary's account code (كود المستلم).
          reference: t.reference.isEmpty ? '—' : t.reference,
          senderReference:
              (t.beneficiaryCode == null || t.beneficiaryCode!.isEmpty)
                  ? '—'
                  : t.beneficiaryCode!,
          amount: t.amount,
          myAccount: slash(myCompany, myExchange),
          party: slash(t.beneficiaryAccountCompany, t.beneficiaryName),
        ),
      );
    }
    ops.sort((a, b) => a.t.compareTo(b.t));

    final rangeLabel = '${dayFmt.format(start)} → ${dayFmt.format(end)}';
    final exportedAt = exportFmt.format(DateTime.now());

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pw.Widget headerSection() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.6,
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'إشاري',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: PdfColors.grey700,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'تفاصيل حركة الدخول والخروج للحوالات',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 18,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'الفترة: $rangeLabel    تاريخ التصدير: $exportedAt',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                (notificationText != null &&
                        notificationText.trim().isNotEmpty)
                    ? _notificationBox(notificationText.trim())
                    : pw.SizedBox(width: 52),
              ],
            ),
            pw.SizedBox(height: 4),
          ],
        );

    pw.Widget footerSection(pw.Context ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        );

    if (ops.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          theme: _theme,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                headerSection(),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'لا توجد عمليات في الفترة المحددة',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                footerSection(ctx),
              ],
            ),
          ),
        ),
      );
      return doc.save();
    }

    // Logical order (right→left as user reads):
    // ت | الوقت | التاريخ | قيمة العملية | الإشاري | حساباتي | الجهة |
    // إشاري المرسل | الرصيد قبل | الرصيد بعد | فرق تراكمي | النوع
    const headers = <String>[
      'ت',
      'الوقت',
      'التاريخ',
      'قيمة العملية',
      'الإشاري',
      'حساباتي',
      'الجهة',
      'إشاري المرسل',
      'الرصيد قبل',
      'الرصيد بعد',
      'فرق تراكمي',
      'النوع',
    ];

    // Per-column horizontal alignment: long Arabic text → right; rest → center.
    const rightAlignedCols = <int>{5, 6}; // حساباتي, الجهة

    pw.Widget cell(
      String text, {
      required bool header,
      PdfColor? color,
      bool rightAlign = false,
    }) =>
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: 3,
            vertical: header ? 6 : 4,
          ),
          alignment:
              rightAlign ? pw.Alignment.centerRight : pw.Alignment.center,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: header ? 9 : 8,
              fontWeight:
                  header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: rightAlign ? pw.TextAlign.right : pw.TextAlign.center,
            softWrap: true,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
        );

    final reversedHeaders = headers.reversed.toList();

    double running = 0;
    final tableChildren = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF1F2F4),
        ),
        children: [
          for (var j = 0; j < reversedHeaders.length; j++)
            cell(
              reversedHeaders[j],
              header: true,
              rightAlign:
                  rightAlignedCols.contains(reversedHeaders.length - 1 - j),
            ),
        ],
      ),
      for (var i = 0; i < ops.length; i++)
        pw.TableRow(
          decoration: i.isOdd
              ? const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFAFAFB),
                )
              : null,
          children: () {
            final op = ops[i];
            final delta = op.isIncome ? op.amount : -op.amount;
            final balanceBefore = running;
            final balanceAfter = running + delta;
            running = balanceAfter;
            // Order matches `headers` above.
            final cells = <String>[
              '${i + 1}',
              timeFmt.format(op.t),
              dayFmt.format(op.t),
              '${op.isIncome ? '+' : '-'}${formatMoney(op.amount)}',
              op.reference,
              op.myAccount,
              op.party,
              op.senderReference,
              formatMoney(balanceBefore),
              formatMoney(balanceAfter),
              '${balanceAfter >= 0 ? '+' : '-'}${formatMoney(balanceAfter.abs())}',
              op.kind,
            ];
            final colorByOriginalIndex = <int, PdfColor>{
              3: op.isIncome
                  ? PdfColors.green800
                  : PdfColors.red800, // قيمة العملية
              10: balanceAfter >= 0
                  ? PdfColors.green800
                  : PdfColors.red800, // فرق تراكمي
              11: op.isIncome
                  ? PdfColors.green800
                  : PdfColors.red800, // النوع
            };
            final reversed = cells.reversed.toList();
            final result = <pw.Widget>[];
            for (var j = 0; j < reversed.length; j++) {
              final orig = cells.length - 1 - j;
              result.add(
                cell(
                  reversed[j],
                  header: false,
                  color: colorByOriginalIndex[orig],
                  rightAlign: rightAlignedCols.contains(orig),
                ),
              );
            }
            return result;
          }(),
        ),
    ];

    final incomeTotal =
        ops.where((o) => o.isIncome).fold<double>(0, (s, o) => s + o.amount);
    final outgoingTotal = ops
        .where((o) => !o.isIncome)
        .fold<double>(0, (s, o) => s + o.amount);
    final movementDiff = incomeTotal - outgoingTotal;

    pw.Widget summaryTile(String label, String value, PdfColor color) =>
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFF7F8FA),
            borderRadius: pw.BorderRadius.circular(4),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
            ],
          ),
        );

    final closingBalance = running;
    final movementSign = movementDiff >= 0 ? '+' : '-';
    final movementColor = movementDiff >= 0
        ? PdfColors.green800
        : PdfColors.red800;
    final closingColor = closingBalance >= 0
        ? PdfColors.green800
        : PdfColors.red800;

    // Build header/table/summary as separate list items so MultiPage can
    // paginate naturally — wrapping them in a single Column would force the
    // engine to treat the whole report as one indivisible widget and push
    // the table to a new page, leaving a blank gap below the header.
    final tableWidget = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Table(
        border: pw.TableBorder.all(
          color: PdfColors.grey400,
          width: 0.4,
        ),
        // Reversed indices: 0 = leftmost (النوع) … 11 = rightmost (ت).
        columnWidths: const {
          0: pw.FlexColumnWidth(0.9), // النوع
          1: pw.FlexColumnWidth(1.3), // فرق تراكمي
          2: pw.FlexColumnWidth(1.3), // الرصيد بعد
          3: pw.FlexColumnWidth(1.3), // الرصيد قبل
          4: pw.FlexColumnWidth(1.2), // إشاري المرسل
          5: pw.FlexColumnWidth(2.2), // الجهة
          6: pw.FlexColumnWidth(2.0), // حساباتي
          7: pw.FlexColumnWidth(1.2), // إشاري
          8: pw.FlexColumnWidth(1.3), // قيمة العملية
          9: pw.FlexColumnWidth(1.0), // التاريخ
          10: pw.FlexColumnWidth(0.9), // الوقت
          11: pw.FlexColumnWidth(0.5), // ت
        },
        children: tableChildren,
      ),
    );

    // Top summary row above the table — RTL: first child is rightmost.
    // Order: إجمالي الدخول | إجمالي الخروج | فرق الحركة.
    // (عدد العمليات removed — the ت column already enumerates rows.)
    final topSummaryRow = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: summaryTile(
              'إجمالي الدخول',
              '+\$${formatMoney(incomeTotal)}',
              PdfColors.green800,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: summaryTile(
              'إجمالي الخروج',
              '-\$${formatMoney(outgoingTotal)}',
              PdfColors.red800,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: summaryTile(
              'فرق الحركة',
              '$movementSign\$${formatMoney(movementDiff.abs())}',
              movementColor,
            ),
          ),
        ],
      ),
    );

    // Bottom row: الرصيد قبل | الرصيد بعد | فرق الحركة.
    final summaryRow = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: summaryTile(
              'الرصيد قبل',
              '\$${formatMoney(0)}',
              PdfColors.grey800,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: summaryTile(
              'الرصيد بعد',
              '${closingBalance >= 0 ? '' : '-'}\$${formatMoney(closingBalance.abs())}',
              closingColor,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: summaryTile(
              'فرق الحركة',
              '$movementSign\$${formatMoney(movementDiff.abs())}',
              movementColor,
            ),
          ),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        footer: footerSection,
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: headerSection(),
          ),
          topSummaryRow,
          pw.SizedBox(height: 10),
          // Identity strip — top of the table, aligned to the right
          // (start of an RTL row). Employee name when generated from
          // the employee app; "ADMIN" otherwise.
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                margin: const pw.EdgeInsets.only(bottom: 6),
                decoration: pw.BoxDecoration(
                  color: (employeeName != null &&
                          employeeName.trim().isNotEmpty)
                      ? const PdfColor.fromInt(0xFFEFF4FB)
                      : const PdfColor.fromInt(0xFFF1ECFB),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                  border: pw.Border.all(
                    color: (employeeName != null &&
                            employeeName.trim().isNotEmpty)
                        ? const PdfColor.fromInt(0xFFC9D7E8)
                        : const PdfColor.fromInt(0xFFD3C7E8),
                    width: 0.6,
                  ),
                ),
                child: pw.Text(
                  (employeeName != null &&
                          employeeName.trim().isNotEmpty)
                      ? 'اسم الموظف: ${employeeName.trim()}'
                      : 'ADMIN',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColors.blueGrey800,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            ),
          ),
          tableWidget,
          pw.SizedBox(height: 12),
          summaryRow,
        ],
      ),
    );

    return doc.save();
  }

  /// "حوالات الدخول إلى حساباتي" — landscape A4. One row per archived
  /// currency-buy inside the selected period. 8 columns, total + count
  /// row at the bottom (right ↔ left).
  Future<Uint8List> buildIncomeDetailsReport({
    required List<CurrencyBuy> buys,
    required Map<String, Company> companyById,
    required Map<String, Exchange> exchangeById,
    required Map<String, Client> clientById,
    required DateTime start,
    required DateTime end,
    String? title,
    String? exportedBy,
    String? notificationText,
  }) async {
    final doc = pw.Document(theme: _theme);
    final dayFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('hh:mm a');
    final exportFmt = DateFormat('yyyy-MM-dd | hh:mm a');
    const reportTitle = 'حوالات الدخول إلى حساباتي';

    String slash(String? a, String? b) {
      final x = (a ?? '').trim();
      final y = (b ?? '').trim();
      if (x.isEmpty && y.isEmpty) return '—';
      if (x.isEmpty) return y;
      if (y.isEmpty) return x;
      return '$x / $y';
    }

    final sorted = [...buys]..sort(
        (a, b) => (a.archivedAt ?? a.createdAt)
            .compareTo(b.archivedAt ?? b.createdAt),
      );

    final rangeLabel = '${dayFmt.format(start)} → ${dayFmt.format(end)}';
    final exportedAt = exportFmt.format(DateTime.now());

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pw.Widget headerSection() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.6,
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'إشاري',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: PdfColors.grey700,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        reportTitle,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 18,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'الفترة: $rangeLabel    تاريخ التصدير: $exportedAt',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                (notificationText != null &&
                        notificationText.trim().isNotEmpty)
                    ? _notificationBox(notificationText.trim())
                    : pw.SizedBox(width: 52),
              ],
            ),
            pw.SizedBox(height: 4),
          ],
        );

    pw.Widget footerSection(pw.Context ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        );

    if (sorted.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          theme: _theme,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                headerSection(),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'لا توجد عمليات دخول في الفترة المحددة',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                footerSection(ctx),
              ],
            ),
          ),
        ),
      );
      return doc.save();
    }

    // Logical order (right→left as user reads):
    // ت | الوقت | التاريخ | إشاري | حساباتي | كود الحساب | الجهة | القيمة
    const headers = <String>[
      'ت',
      'الوقت',
      'التاريخ',
      'إشاري',
      'حساباتي',
      'كود الحساب',
      'الجهة',
      'القيمة',
    ];

    // حساباتي (4) و الجهة (6) — نص عربي طويل، محاذاة لليمين.
    const rightAlignedCols = <int>{4, 6};

    pw.Widget cell(
      String text, {
      required bool header,
      PdfColor? color,
      bool rightAlign = false,
    }) =>
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: 3,
            vertical: header ? 6 : 4,
          ),
          alignment:
              rightAlign ? pw.Alignment.centerRight : pw.Alignment.center,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: header ? 9 : 8,
              fontWeight:
                  header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign:
                rightAlign ? pw.TextAlign.right : pw.TextAlign.center,
            softWrap: true,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
        );

    final reversedHeaders = headers.reversed.toList();

    final tableChildren = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF1F2F4),
        ),
        children: [
          for (var j = 0; j < reversedHeaders.length; j++)
            cell(
              reversedHeaders[j],
              header: true,
              rightAlign:
                  rightAlignedCols.contains(reversedHeaders.length - 1 - j),
            ),
        ],
      ),
      for (var i = 0; i < sorted.length; i++)
        pw.TableRow(
          decoration: i.isOdd
              ? const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFAFAFB),
                )
              : null,
          children: () {
            final b = sorted[i];
            final myCompany = companyById[b.myCompanyId]?.name;
            final myExchange = exchangeById[b.exchangeId];
            final myExchangeName = myExchange?.name;
            final myExchangeCode = (myExchange?.ourCode ?? '').trim();
            final client =
                b.clientId != null ? clientById[b.clientId!] : null;
            final partyName =
                client?.name ?? b.clientFromAccount ?? '';
            final partyCompany = client?.company ?? '';
            final reference = b.reference.isEmpty
                ? (b.id.length >= 8 ? b.id.substring(0, 8) : b.id)
                : b.reference;
            // Order matches `headers` above.
            final cells = <String>[
              '${i + 1}',
              timeFmt.format(b.archivedAt ?? b.createdAt),
              dayFmt.format(b.archivedAt ?? b.createdAt),
              reference,
              slash(myCompany, myExchangeName),
              myExchangeCode.isEmpty ? '—' : myExchangeCode,
              slash(partyCompany, partyName),
              '+${formatMoney(b.usdAmount)} \$',
            ];
            final colorByOriginalIndex = <int, PdfColor>{
              7: PdfColors.green800, // القيمة
            };
            final reversed = cells.reversed.toList();
            final result = <pw.Widget>[];
            for (var j = 0; j < reversed.length; j++) {
              final orig = cells.length - 1 - j;
              result.add(
                cell(
                  reversed[j],
                  header: false,
                  color: colorByOriginalIndex[orig],
                  rightAlign: rightAlignedCols.contains(orig),
                ),
              );
            }
            return result;
          }(),
        ),
    ];

    final totalUsd =
        sorted.fold<double>(0, (s, b) => s + b.usdAmount);

    final tableWidget = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Table(
        border: pw.TableBorder.all(
          color: PdfColors.grey400,
          width: 0.4,
        ),
        // Reversed indices: 0 = leftmost (القيمة) … 7 = rightmost (ت).
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4), // القيمة
          1: pw.FlexColumnWidth(2.4), // الجهة
          2: pw.FlexColumnWidth(1.2), // كود الحساب
          3: pw.FlexColumnWidth(2.0), // حساباتي
          4: pw.FlexColumnWidth(1.2), // إشاري
          5: pw.FlexColumnWidth(1.0), // التاريخ
          6: pw.FlexColumnWidth(0.9), // الوقت
          7: pw.FlexColumnWidth(0.5), // ت
        },
        children: tableChildren,
      ),
    );

    // RTL row: first child is rightmost. الإجمالي يمين، عدد المعاملات يسار.
    final totalRow = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'الإجمالي : +\$${formatMoney(totalUsd)}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
                color: PdfColors.green800,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.Text(
              'عدد المعاملات: ${sorted.length}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        footer: footerSection,
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: headerSection(),
          ),
          tableWidget,
          pw.SizedBox(height: 12),
          totalRow,
        ],
      ),
    );

    return doc.save();
  }

  /// "حوالات الخروج من حساباتي" — landscape A4. One row per archived
  /// transfer inside the selected period. 9 columns, total + count at
  /// bottom right.
  Future<Uint8List> buildOutgoingDetailsReport({
    required List<Transfer> transfers,
    required Map<String, Company> companyById,
    required Map<String, Exchange> exchangeById,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
    String? notificationText,
  }) async {
    final doc = pw.Document(theme: _theme);
    final dayFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('hh:mm a');
    final exportFmt = DateFormat('yyyy-MM-dd | hh:mm a');
    const reportTitle = 'حوالات الخروج من حساباتي';

    String slash(String? a, String? b) {
      final x = (a ?? '').trim();
      final y = (b ?? '').trim();
      if (x.isEmpty && y.isEmpty) return '—';
      if (x.isEmpty) return y;
      if (y.isEmpty) return x;
      return '$x / $y';
    }

    final sorted = [...transfers]..sort(
        (a, b) => (a.archivedAt ?? a.createdAt)
            .compareTo(b.archivedAt ?? b.createdAt),
      );

    final rangeLabel = '${dayFmt.format(start)} → ${dayFmt.format(end)}';
    final exportedAt = exportFmt.format(DateTime.now());

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage =
        logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    pw.Widget headerSection() => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    height: 44,
                    width: 44,
                    margin: const pw.EdgeInsets.only(right: 8),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.6,
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      'إشاري',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: PdfColors.grey700,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        reportTitle,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 18,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'الفترة: $rangeLabel    تاريخ التصدير: $exportedAt',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                (notificationText != null &&
                        notificationText.trim().isNotEmpty)
                    ? _notificationBox(notificationText.trim())
                    : pw.SizedBox(width: 52),
              ],
            ),
            pw.SizedBox(height: 4),
          ],
        );

    pw.Widget footerSection(pw.Context ctx) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
            'تم التصدير بواسطة: ${(exportedBy ?? '').trim().isEmpty ? 'admin' : exportedBy!.trim()}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        );

    if (sorted.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          theme: _theme,
          textDirection: pw.TextDirection.rtl,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                headerSection(),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      'لا توجد عمليات خروج في الفترة المحددة',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                footerSection(ctx),
              ],
            ),
          ),
        ),
      );
      return doc.save();
    }

    // Logical order (right→left as user reads):
    // ت | الوقت | التاريخ | إشاري | حساباتي | كود الحساب | الجهة | القيمة
    const headers = <String>[
      'ت',
      'الوقت',
      'التاريخ',
      'إشاري',
      'حساباتي',
      'كود الحساب',
      'الجهة',
      'القيمة',
    ];

    // حساباتي (4) و الجهة (6) — نص عربي طويل، محاذاة لليمين.
    const rightAlignedCols = <int>{4, 6};

    pw.Widget cell(
      String text, {
      required bool header,
      PdfColor? color,
      bool rightAlign = false,
    }) =>
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: 3,
            vertical: header ? 6 : 4,
          ),
          alignment:
              rightAlign ? pw.Alignment.centerRight : pw.Alignment.center,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: header ? 9 : 8,
              fontWeight:
                  header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign:
                rightAlign ? pw.TextAlign.right : pw.TextAlign.center,
            softWrap: true,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
        );

    final reversedHeaders = headers.reversed.toList();

    final tableChildren = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF1F2F4),
        ),
        children: [
          for (var j = 0; j < reversedHeaders.length; j++)
            cell(
              reversedHeaders[j],
              header: true,
              rightAlign:
                  rightAlignedCols.contains(reversedHeaders.length - 1 - j),
            ),
        ],
      ),
      for (var i = 0; i < sorted.length; i++)
        pw.TableRow(
          decoration: i.isOdd
              ? const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFAFAFB),
                )
              : null,
          children: () {
            final t = sorted[i];
            final myCompany = companyById[t.companyId]?.name;
            final myExchange = exchangeById[t.exchangeId]?.name;
            final beneficiaryAccountCode =
                (t.beneficiaryCode == null || t.beneficiaryCode!.isEmpty)
                    ? '—'
                    : t.beneficiaryCode!;
            final reference = t.reference.isEmpty
                ? (t.id.length >= 8 ? t.id.substring(0, 8) : t.id)
                : t.reference;
            // Order matches `headers` above.
            final cells = <String>[
              '${i + 1}',
              timeFmt.format(t.archivedAt ?? t.createdAt),
              dayFmt.format(t.archivedAt ?? t.createdAt),
              reference,
              slash(myCompany, myExchange),
              beneficiaryAccountCode,
              slash(t.beneficiaryAccountCompany, t.beneficiaryName),
              '-${formatMoney(t.amount)} \$',
            ];
            final colorByOriginalIndex = <int, PdfColor>{
              7: PdfColors.red800, // القيمة
            };
            final reversed = cells.reversed.toList();
            final result = <pw.Widget>[];
            for (var j = 0; j < reversed.length; j++) {
              final orig = cells.length - 1 - j;
              result.add(
                cell(
                  reversed[j],
                  header: false,
                  color: colorByOriginalIndex[orig],
                  rightAlign: rightAlignedCols.contains(orig),
                ),
              );
            }
            return result;
          }(),
        ),
    ];

    final totalAmount =
        sorted.fold<double>(0, (s, t) => s + t.amount);

    final tableWidget = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Table(
        border: pw.TableBorder.all(
          color: PdfColors.grey400,
          width: 0.4,
        ),
        // Reversed indices: 0 = leftmost (القيمة) … 7 = rightmost (ت).
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4), // القيمة
          1: pw.FlexColumnWidth(2.4), // الجهة
          2: pw.FlexColumnWidth(1.2), // كود الحساب
          3: pw.FlexColumnWidth(2.0), // حساباتي
          4: pw.FlexColumnWidth(1.2), // إشاري
          5: pw.FlexColumnWidth(1.0), // التاريخ
          6: pw.FlexColumnWidth(0.9), // الوقت
          7: pw.FlexColumnWidth(0.5), // ت
        },
        children: tableChildren,
      ),
    );

    // RTL row: first child is rightmost. الإجمالي يمين، عدد العمليات يسار.
    final totalRow = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'الإجمالي : -\$${formatMoney(totalAmount)}',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
                color: PdfColors.red800,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.Text(
              'عدد العمليات: ${sorted.length}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        footer: footerSection,
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: headerSection(),
          ),
          tableWidget,
          pw.SizedBox(height: 12),
          totalRow,
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

class _DetailedOp {
  _DetailedOp({
    required this.t,
    required this.kind,
    required this.isIncome,
    required this.reference,
    required this.senderReference,
    required this.amount,
    required this.myAccount,
    required this.party,
  });
  final DateTime t;
  final String kind;
  final bool isIncome;
  final String reference;
  final String senderReference;
  final double amount;
  final String myAccount;
  final String party;
}

pw.Widget _notificationBox(String text) => pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFF8E1),
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.right,
        maxLines: 3,
        overflow: pw.TextOverflow.clip,
      ),
    );

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
