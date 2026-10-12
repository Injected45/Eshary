import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../features/cancellations/domain/cancellation.dart';
import '../features/clients/domain/client.dart';
import '../features/companies/domain/company.dart';
import '../features/companies/domain/exchange.dart';
import '../features/currency_buy/domain/currency_buy.dart';
import '../features/transfers/domain/transfer.dart';
import 'formatters.dart';
import 'libya_time.dart';
import 'ledger.dart';
import 'period_label.dart';

part 'pdf_export_period.dart';

/// Almarai (the PDF body font) has no proper isolated form of the letter ي:
/// after ا د ذ ر ز و it is drawn as a zero-width stub, so "إشاري" prints as
/// "إشار" and "المهدي" as "المهد". Noto Naskh has it. The package falls back to
/// another font only for characters the main font LACKS, so an isolated ي is
/// rewritten to its presentation form U+FEF1, which Almarai lacks, and the
/// fallback font draws it.
String fixIsolatedYeh(String s) {
  const joinsForward = 'بتثجحخسشصضطظعغفقكلمنهيئـ';
  bool isMark(int c) => c >= 0x064B && c <= 0x0652;
  bool isLetter(int c) =>
      (c >= 0x0621 && c <= 0x064A) || (c >= 0x066E && c <= 0x06D3);
  final r = s.runes.toList();
  for (var i = 0; i < r.length; i++) {
    if (r[i] != 0x064A) continue;
    // the letter before (skipping vowel marks) and the next character
    var p = i - 1;
    while (p >= 0 && isMark(r[p])) {
      p--;
    }
    final prevJoins = p >= 0 && joinsForward.runes.contains(r[p]);
    var n = i + 1;
    while (n < r.length && isMark(r[n])) {
      n++;
    }
    final nextIsLetter = n < r.length && isLetter(r[n]);
    if (!prevJoins && !nextIsLetter) r[i] = 0xFEF1;
  }
  return String.fromCharCodes(r);
}

/// The fonts used to draw the rewritten ي (set when the exporter loads).
pw.Font? _yehFontRegular;
pw.Font? _yehFontBold;

/// `pw.Text` that repairs the isolated ي (see [fixIsolatedYeh]).
class _ArText extends pw.Text {
  _ArText(
    String text, {
    pw.TextStyle? style,
    super.textAlign,
    super.textDirection,
    super.softWrap,
    super.maxLines,
    super.overflow,
  }) : super(
          fixIsolatedYeh(text),
          style: _withYehFont(style),
        );

  /// Bold text takes the bold Noto glyph for the repaired ي.
  static pw.TextStyle? _withYehFont(pw.TextStyle? style) {
    final bold = _yehFontBold;
    final regular = _yehFontRegular;
    if (style == null || bold == null || regular == null) return style;
    final isBold = style.fontWeight == pw.FontWeight.bold;
    return style.copyWith(
      fontFallback: isBold ? [bold, regular] : [regular, bold],
    );
  }
}

/// Times in Libya time, 24-hour, drawn so they are always right:
///  - the hour, the colon and the minutes sit in one LEFT-TO-RIGHT group, so the
///    reading is "04:55" and never "55:04" (inside right-to-left text the three
///    pieces would swap places);
///  - the colon is bold, the same size as the digits, with a small even gap on
///    each side.
/// A string without a clock is an ordinary [_ArText].
final _clockRe = RegExp(r'\d{1,2}:\d{2}');

pw.Widget _clockGroup(String hhmm, pw.TextStyle style) {
  final parts = hhmm.split(':');
  final size = style.fontSize ?? 8;
  final gap = pw.SizedBox(width: size * 0.12);
  pw.Widget piece(String t, pw.TextStyle st) => _ArText(
        t,
        style: st,
        textDirection: pw.TextDirection.ltr,
      );
  return pw.Directionality(
    textDirection: pw.TextDirection.ltr,
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        piece(parts[0].padLeft(2, '0'), style),
        gap,
        piece(':', style.copyWith(fontWeight: pw.FontWeight.bold)),
        gap,
        piece(parts[1], style),
      ],
    ),
  );
}

pw.Widget _clockText(
  String text, {
  required pw.TextStyle style,
  pw.TextDirection? textDirection,
  pw.TextAlign? textAlign,
  bool? softWrap,
}) {
  if (!_clockRe.hasMatch(text)) {
    return _ArText(
      text,
      style: style,
      textDirection: textDirection,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
  final size = style.fontSize ?? 8;
  pw.Widget line(String l) {
    final whole = RegExp(r'^\s*(\d{1,2}:\d{2})\s*$').firstMatch(l);
    if (whole != null) return _clockGroup(whole.group(1)!, style);
    if (!_clockRe.hasMatch(l)) {
      return _ArText(
        l,
        style: style,
        textDirection: textDirection,
        textAlign: textAlign,
        softWrap: softWrap,
      );
    }
    // a sentence with a clock inside: text pieces and clock groups, in
    // reading order (right to left)
    final pieces = <pw.Widget>[];
    var at = 0;
    for (final m in _clockRe.allMatches(l)) {
      final before = l.substring(at, m.start).trim();
      if (before.isNotEmpty) {
        pieces.add(
            _ArText(before, style: style, textDirection: pw.TextDirection.rtl));
        pieces.add(pw.SizedBox(width: size * 0.7));
      }
      pieces.add(_clockGroup(m.group(0)!, style));
      at = m.end;
    }
    final rest = l.substring(at).trim();
    if (rest.isNotEmpty) {
      pieces.add(pw.SizedBox(width: size * 0.7));
      pieces.add(
          _ArText(rest, style: style, textDirection: pw.TextDirection.rtl));
    }
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: pieces,
      ),
    );
  }

  final lines = text.split('\n');
  if (lines.length == 1) return line(text);
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [for (final l in lines) line(l)],
  );
}

/// A [DateFormat] that first moves the moment to Libya time (see [libyaTime]).
class _LibyaFmt {
  _LibyaFmt(String pattern) : _f = DateFormat(pattern);
  final DateFormat _f;
  String format(DateTime t) => _f.format(libyaTime(t));
}

/// The LAST line of every printed page: when the report was exported and by
/// whom. Used as the `MultiPage` footer (the pdf package paints it on the
/// page's bottom margin, so it sits at the very bottom whether the page is
/// full or nearly empty) and at the foot of the single-page layouts.
pw.Widget _exportFooter({required DateTime at, String? by}) {
  final name = (by ?? '').trim().isEmpty ? 'admin' : by!.trim();
  final when = DateFormat('yyyy-MM-dd | HH:mm').format(libyaTime(at));
  return pw.Container(
    width: double.infinity,
    alignment: pw.Alignment.center,
    padding: const pw.EdgeInsets.only(top: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
    ),
    child: _clockText(
      'تاريخ التصدير: $when      |      تم التصدير بواسطة: $name',
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      textDirection: pw.TextDirection.rtl,
      textAlign: pw.TextAlign.center,
    ),
  );
}

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
    final fallbackRegularFont = pw.Font.ttf(fallback);
    final fallbackBoldFont = pw.Font.ttf(fallbackBold);
    _yehFontRegular = fallbackRegularFont;
    _yehFontBold = fallbackBoldFont;
    return PdfExport._(
      pw.Font.ttf(regular),
      pw.Font.ttf(bold),
      fallbackRegularFont,
      fallbackBoldFont,
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
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final exportedAtTime = DateTime.now();
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
    final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      // MultiPage: the export line is its footer, painted on the bottom margin
      // of every page, and a long table continues on the next page.
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        footer: (ctx) => _exportFooter(at: exportedAtTime, by: exportedBy),
        build: (context) => [
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
                    _ArText(
                      title,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 18,
                      ),
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
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.black),
            headers: [for (final h in headers) fixIsolatedYeh(h)],
            data: [
              for (final row in dataRows)
                [for (final c in row) fixIsolatedYeh(c)],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: PdfColors.black,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.black,
            ),
            cellAlignment: pw.Alignment.centerRight,
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        ],
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

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

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
                    child: _ArText(
                      'سجل خروج الحوالات اليوم',
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
                _ArText(
                  'اليوم: $dayName    التاريخ: $dateStr',
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
                    child: _ArText(
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
                    child: _ArText(
                      'لا توجد سجلات',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                _exportFooter(at: now, by: exportedBy),
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
          rows[i].isCancelled
              ? '${formatMoney(rows[i].amount)} \$ ملغاة'
              : '${formatMoney(rows[i].amount)} \$',
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
          child: _ArText(
            text,
            style: pw.TextStyle(
              fontSize: header ? 11 : 10,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: PdfColors.black,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            softWrap: true,
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

    final sum = rows.fold<double>(0, (a, r) => a + r.netAmount);
    final totalText = '${formatMoney(sum)} \$';
    final wordsText = _arabicNumberWords(sum.round());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        footer: (ctx) => _exportFooter(at: now, by: exportedBy),
        // Separate list items (not one big Column) so MultiPage can break
        // the table across pages instead of throwing TooManyPagesException.
        build: (context) => [
          headerSection(),
          pw.Table(
            border: pw.TableBorder(
              top: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              bottom: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              left: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              right: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              horizontalInside: const pw.BorderSide(
                color: PdfColors.black,
                width: 0.5,
              ),
              verticalInside: const pw.BorderSide(
                color: PdfColors.black,
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
                        child: _ArText(
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
                      _ArText(
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
                    child: _ArText(
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
    );

    return doc.save();
  }

  /// "سجل دخول الحوالات اليوم" — landscape A4 report mirroring
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

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/images/app_icon.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {
      logoBytes = null;
    }
    final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

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
                    child: _ArText(
                      'سجل دخول الحوالات اليوم',
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
                _ArText(
                  'اليوم: $dayName    التاريخ: $dateStr',
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
                    child: _ArText(
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
                    child: _ArText(
                      'لا توجد سجلات',
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey600,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ),
                _exportFooter(at: now, by: exportedBy),
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
          rows[i].isCancelled
              ? '${formatMoney(rows[i].usdAmount)} \$ ملغاة'
              : '${formatMoney(rows[i].usdAmount)} \$',
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
          child: _ArText(
            text,
            style: pw.TextStyle(
              fontSize: header ? 11 : 10,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: PdfColors.black,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
            softWrap: true,
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

    final sum = rows.fold<double>(0, (a, r) => a + r.netAmount);
    final totalText = '${formatMoney(sum)} \$';
    final wordsText = _arabicNumberWords(sum.round());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: _theme,
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.SizedBox(height: 0),
        footer: (ctx) => _exportFooter(at: now, by: exportedBy),
        // Separate list items (not one big Column) so MultiPage can break
        // the table across pages instead of throwing TooManyPagesException.
        build: (context) => [
          headerSection(),
          pw.Table(
            border: pw.TableBorder(
              top: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              bottom: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              left: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              right: const pw.BorderSide(
                color: PdfColors.black,
                width: 1.0,
              ),
              horizontalInside: const pw.BorderSide(
                color: PdfColors.black,
                width: 0.5,
              ),
              verticalInside: const pw.BorderSide(
                color: PdfColors.black,
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
                        child: _ArText(
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
                      _ArText(
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
                    child: _ArText(
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
    );

    return doc.save();
  }

  /// Hand the bytes to the OS print/share sheet.
  static Future<void> sharePdf(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}

pw.Widget _notificationBox(String text) => pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFF8E1),
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: _ArText(
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
