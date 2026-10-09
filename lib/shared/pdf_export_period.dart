part of 'pdf_export.dart';

// The three period reports share ONE look and ONE way of being built:
//
//   تفاصيل حركة الدخول والخروج للحوالات   (entries + exits, with the balance)
//   حوالات الدخول إلى حساباتي              (entries only)
//   حوالات الخروج من حساباتي               (exits only)
//
// Header (logo, title, period, notification) → identity strip (ADMIN or the
// employee) → one table with every column and datum centred, a grey header,
// zebra rows and the entry/exit colours → the totals once, under the table →
// the export line as the footer of every page. Landscape A4.

Future<pw.MemoryImage?> _loadLogo() async {
  try {
    final data = await rootBundle.load('assets/images/app_icon.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// "company / account" with whichever part exists, or a dash.
String _slash(String? a, String? b) {
  final x = (a ?? '').trim();
  final y = (b ?? '').trim();
  if (x.isEmpty && y.isEmpty) return '—';
  if (x.isEmpty) return y;
  if (y.isEmpty) return x;
  return '$x / $y';
}

/// Logo (right), title (centre), notification (left); the period sits on the
/// left edge of the page under them.
pw.Widget _periodHeader({
  required String title,
  required String period,
  required pw.MemoryImage? logo,
  String? notificationText,
  List<String> extraLines = const [],
}) =>
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _periodHeaderTop(
          title: title,
          logo: logo,
          notificationText: notificationText,
          extraLines: extraLines,
        ),
        // الفترة: on the left edge of the page.
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: _ArText(
            'الفترة: $period',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
      ],
    );

/// Logo (right), title and any extra lines (centre), notification (left).
pw.Widget _periodHeaderTop({
  required String title,
  required pw.MemoryImage? logo,
  String? notificationText,
  List<String> extraLines = const [],
}) =>
    pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            height: 44,
            width: 44,
            margin: const pw.EdgeInsets.only(right: 8),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          )
        else
          pw.Container(
            height: 44,
            width: 44,
            margin: const pw.EdgeInsets.only(right: 8),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: _ArText(
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
              _ArText(
                title,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 18,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              if (extraLines.isNotEmpty) pw.SizedBox(height: 6),
              for (final line in extraLines)
                _ArText(
                  line,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
            ],
          ),
        ),
        (notificationText != null && notificationText.trim().isNotEmpty)
            ? _notificationBox(notificationText.trim())
            : pw.SizedBox(width: 52),
      ],
    );

/// Who produced the report: the employee's name from the employee app, or
/// "ADMIN". Right-aligned (the start of an RTL row).
pw.Widget _identityStrip(String? employeeName) {
  final isEmployee = employeeName != null && employeeName.trim().isNotEmpty;
  return pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        margin: const pw.EdgeInsets.only(top: 4, bottom: 6),
        decoration: pw.BoxDecoration(
          color: isEmployee
              ? const PdfColor.fromInt(0xFFEFF4FB)
              : const PdfColor.fromInt(0xFFF1ECFB),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(
            color: isEmployee
                ? const PdfColor.fromInt(0xFFC9D7E8)
                : const PdfColor.fromInt(0xFFD3C7E8),
            width: 0.6,
          ),
        ),
        child: _ArText(
          isEmployee ? 'اسم الموظف: ${employeeName.trim()}' : 'ADMIN',
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
            color: PdfColors.blueGrey800,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      ),
    ),
  );
}

/// A table cell: text centred, long text wraps centred. Never clipped.
pw.Widget _reportCell(String text, {required bool header, PdfColor? color}) =>
    pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: header ? 6 : 4),
      // A fixed minimum height keeps every data row the same: a row whose text
      // needs the fallback font (a repaired ي) is a little taller than the
      // others, and the rows would otherwise be uneven.
      constraints: pw.BoxConstraints(minHeight: header ? 0 : 22),
      alignment: pw.Alignment.center,
      child: _ArText(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 8,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
        softWrap: true,
      ),
    );

/// The report table. [headers] and [widths] are in reading order (right →
/// left, so the first is the rightmost); each row of [rows] follows the same
/// order. [colorOf] colours a cell by (row, column) in reading order.
pw.Widget _reportTable({
  required List<String> headers,
  required List<double> widths,
  required List<List<String>> rows,
  PdfColor? Function(int row, int column)? colorOf,
}) {
  final n = headers.length;
  assert(widths.length == n, 'one width per column');
  return pw.Directionality(
    textDirection: pw.TextDirection.rtl,
    child: pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
      // pdf tables lay columns out left → right, so the reading order is
      // reversed here.
      columnWidths: {
        for (var j = 0; j < n; j++) j: pw.FlexColumnWidth(widths[n - 1 - j]),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF1F2F4),
          ),
          children: [
            for (var j = 0; j < n; j++)
              _reportCell(headers[n - 1 - j], header: true),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: i.isOdd
                ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAFAFB))
                : null,
            children: [
              for (var j = 0; j < n; j++)
                _reportCell(
                  rows[i][n - 1 - j],
                  header: false,
                  color: colorOf?.call(i, n - 1 - j),
                ),
            ],
          ),
      ],
    ),
  );
}

pw.Widget _statTile(String label, String value, PdfColor color) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF7F8FA),
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _ArText(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.SizedBox(height: 4),
          _ArText(
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

/// The totals, once, under the table. RTL: the first tile is the rightmost.
pw.Widget _statRow(List<pw.Widget> tiles) => pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 8),
            pw.Expanded(child: tiles[i]),
          ],
        ],
      ),
    );

/// One page with only the header and a message, for a period with nothing.
void _addEmptyReportPage(
  pw.Document doc, {
  required pw.ThemeData theme,
  required pw.Widget header,
  required String message,
  required DateTime at,
  String? by,
  PdfPageFormat? format,
  double margin = 20,
}) {
  doc.addPage(
    pw.Page(
      pageFormat: format ?? PdfPageFormat.a4.landscape,
      margin: pw.EdgeInsets.all(margin),
      theme: theme,
      textDirection: pw.TextDirection.rtl,
      build: (ctx) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          children: [
            header,
            pw.Expanded(
              child: pw.Center(
                child: _ArText(
                  message,
                  style: const pw.TextStyle(
                    fontSize: 14,
                    color: PdfColors.grey600,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            ),
            _exportFooter(at: at, by: by),
          ],
        ),
      ),
    ),
  );
}

/// The page body of every period report; the export line is the footer.
void _addReportPages(
  pw.Document doc, {
  required pw.ThemeData theme,
  required List<pw.Widget> body,
  required DateTime at,
  String? by,
  PdfPageFormat? format,
  double margin = 20,
}) {
  doc.addPage(
    pw.MultiPage(
      pageFormat: format ?? PdfPageFormat.a4.landscape,
      margin: pw.EdgeInsets.all(margin),
      theme: theme,
      textDirection: pw.TextDirection.rtl,
      header: (_) => pw.SizedBox(height: 0),
      footer: (ctx) => _exportFooter(at: at, by: by),
      build: (context) => body,
    ),
  );
}

class _DetailedOp {
  _DetailedOp({
    required this.t,
    required this.isIncome,
    required this.reference,
    required this.senderReference,
    required this.amount,
    required this.myAccount,
    required this.party,
  });
  final DateTime t;
  final bool isIncome;
  final String reference;
  final String senderReference;
  final double amount;
  final String myAccount;
  final String party;
}

/// One row of an entries-only or exits-only report.
class _KindRow {
  _KindRow({
    required this.t,
    required this.code,
    required this.myAccount,
    required this.reference,
    required this.party,
    required this.amount,
  });
  final DateTime t;
  final String code;
  final String myAccount;
  final String reference;
  final String party;
  final double amount;
}

extension PeriodReports on PdfExport {
  /// "تفاصيل حركة الدخول والخروج للحوالات": an accountant-style statement.
  /// An entry fills دخول (green), an exit fills خروج (red), and الرصيد is the
  /// running total. إشاري/كود holds the account code for an entry and the
  /// reference for an exit.
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
    final timeFmt = DateFormat('HH:mm');

    final ops = <_DetailedOp>[];
    for (final b in buys) {
      final myExchangeRow = exchangeById[b.exchangeId];
      final myCode = (myExchangeRow?.ourCode ?? '').trim();
      final client = b.clientId != null ? clientById[b.clientId!] : null;
      ops.add(
        _DetailedOp(
          t: b.archivedAt ?? b.createdAt,
          isIncome: true,
          // For دخول: this column shows MY account code (وجهة الدخول); the
          // sender column shows the reference that came from الجهة المرسلة.
          reference: myCode.isEmpty ? '—' : myCode,
          senderReference: b.reference.isEmpty ? '—' : b.reference,
          amount: b.usdAmount,
          myAccount: _slash(companyById[b.myCompanyId]?.name, myExchangeRow?.name),
          party: _slash(
            client?.company ?? '',
            client?.name ?? b.clientFromAccount ?? '',
          ),
        ),
      );
    }
    for (final t in transfers) {
      ops.add(
        _DetailedOp(
          t: t.archivedAt ?? t.createdAt,
          isIncome: false,
          // For خروج: this column shows my transfer reference; the sender
          // column shows the beneficiary's account code (كود المستلم).
          reference: t.reference.isEmpty ? '—' : t.reference,
          senderReference:
              (t.beneficiaryCode == null || t.beneficiaryCode!.isEmpty)
                  ? '—'
                  : t.beneficiaryCode!,
          amount: t.amount,
          myAccount: _slash(
            companyById[t.companyId]?.name,
            exchangeById[t.exchangeId]?.name,
          ),
          party: _slash(t.beneficiaryAccountCompany, t.beneficiaryName),
        ),
      );
    }
    ops.sort((a, b) => a.t.compareTo(b.t));

    final exportedAtTime = DateTime.now();
    final logo = await _loadLogo();
    final header = _periodHeader(
      title: 'تفاصيل حركة الدخول والخروج للحوالات',
      period: periodLabel(start, end),
      logo: logo,
      notificationText: notificationText,
    );

    if (ops.isEmpty) {
      _addEmptyReportPage(
        doc,
        theme: _theme,
        header: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [header, _identityStrip(employeeName)],
        ),
        message: 'لا توجد عمليات في الفترة المحددة',
        at: exportedAtTime,
        by: exportedBy,
      );
      return doc.save();
    }

    // Reading order (right → left). Every column and its data are centred.
    const headers = <String>[
      'ت',
      'الوقت',
      'التاريخ',
      'إشاري/كود',
      'حساباتي',
      'الجهة',
      'إشاري المرسل',
      'دخول',
      'خروج',
      'الرصيد',
    ];
    const widths = <double>[0.5, 0.9, 1.1, 1.4, 2.2, 2.4, 1.3, 1.4, 1.4, 1.5];

    final ledger = ledgerOf([
      for (final o in ops) (isIncome: o.isIncome, amount: o.amount),
    ]);

    final incomeTotal =
        ops.where((o) => o.isIncome).fold<double>(0, (s, o) => s + o.amount);
    final outgoingTotal =
        ops.where((o) => !o.isIncome).fold<double>(0, (s, o) => s + o.amount);
    final balance = incomeTotal - outgoingTotal;

    _addReportPages(
      doc,
      theme: _theme,
      at: exportedAtTime,
      by: exportedBy,
      body: [
        header,
        _identityStrip(employeeName),
        _reportTable(
          headers: headers,
          widths: widths,
          rows: [
            for (var i = 0; i < ops.length; i++)
              [
                '${i + 1}',
                timeFmt.format(ops[i].t),
                dayFmt.format(ops[i].t),
                ops[i].reference,
                ops[i].myAccount,
                ops[i].party,
                ops[i].senderReference,
                ledger[i].income == null ? '' : formatMoney(ledger[i].income!),
                ledger[i].outgoing == null
                    ? ''
                    : formatMoney(ledger[i].outgoing!),
                formatMoney(ledger[i].balance),
              ],
          ],
          colorOf: (row, column) {
            if (column == 7) return PdfColors.green800; // دخول
            if (column == 8) return PdfColors.red800; // خروج
            if (column == 9) {
              return ledger[row].balance >= 0
                  ? PdfColors.green800
                  : PdfColors.red800; // الرصيد
            }
            return null;
          },
        ),
        pw.SizedBox(height: 12),
        _statRow([
          _statTile(
            'إجمالي الدخول',
            '+\$${formatMoney(incomeTotal)}',
            PdfColors.green800,
          ),
          _statTile(
            'إجمالي الخروج',
            '-\$${formatMoney(outgoingTotal)}',
            PdfColors.red800,
          ),
          _statTile(
            'الرصيد',
            '${balance >= 0 ? '+' : '-'}\$${formatMoney(balance.abs())}',
            balance >= 0 ? PdfColors.green800 : PdfColors.red800,
          ),
        ]),
      ],
    );

    return doc.save();
  }

  /// "كشف حساب": the short statement دخول | خروج | الرصيد (running). Portrait
  /// A4, same look as the period reports. [rows] are oldest first; [showWho]
  /// adds a column naming who did each operation.
  Future<Uint8List> buildAccountStatement({
    required List<
            ({
              DateTime at,
              String who,
              String account,
              double? income,
              double? outgoing,
              double balance,
            })>
        rows,
    required double incomeTotal,
    required double outgoingTotal,
    double openingBalance = 0,
    required String scopeLabel,
    required String title,
    required String rangeLabel,
    required bool showWho,
    bool showAccount = false,
    String? exportedBy,
    String? notificationText,
  }) async {
    final doc = pw.Document(theme: _theme);
    final dayFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('HH:mm');
    final exportedAtTime = DateTime.now();
    final logo = await _loadLogo();
    final header = _periodHeader(
      title: title,
      period: rangeLabel,
      logo: logo,
      notificationText: notificationText,
      extraLines: ['الكشف: $scopeLabel'],
    );

    if (rows.isEmpty) {
      _addEmptyReportPage(
        doc,
        theme: _theme,
        header: header,
        message: 'لا توجد عمليات في هذه الفترة',
        at: exportedAtTime,
        by: exportedBy,
        format: PdfPageFormat.a4,
        margin: 28,
      );
      return doc.save();
    }

    // Reading order (right → left). الوقت and المنفذ are wide enough for a
    // full name; every column and its data are centred.
    final headers = <String>[
      'ت',
      'التاريخ',
      'الوقت',
      if (showAccount) 'الحساب',
      if (showWho) 'المنفذ',
      'دخول',
      'خروج',
      'الرصيد',
    ];
    final widths = <double>[0.5, 1.4, 1.3, if (showAccount) 3.2, if (showWho) 2.6, 1.4, 1.4, 1.6];
    final incomeColumn = headers.indexOf('دخول');
    final outgoingColumn = headers.indexOf('خروج');
    final balanceColumn = headers.indexOf('الرصيد');

    // رصيد افتتاحي: a first row and a first tile, when there is one.
    final showOpening = openingBalance != 0;
    final balance = openingBalance + incomeTotal - outgoingTotal;

    _addReportPages(
      doc,
      theme: _theme,
      at: exportedAtTime,
      by: exportedBy,
      format: PdfPageFormat.a4,
      margin: 28,
      body: [
        header,
        pw.SizedBox(height: 10),
        _reportTable(
          headers: headers,
          widths: widths,
          rows: [
            if (showOpening)
              [
                '',
                '',
                '',
                if (showAccount) '',
                if (showWho) 'رصيد افتتاحي',
                '',
                '',
                formatMoney(openingBalance),
              ],
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                dayFmt.format(rows[i].at),
                timeFmt.format(rows[i].at),
                if (showAccount) rows[i].account,
                if (showWho) rows[i].who,
                rows[i].income == null ? '' : formatMoney(rows[i].income!),
                rows[i].outgoing == null ? '' : formatMoney(rows[i].outgoing!),
                formatMoney(rows[i].balance),
              ],
          ],
          colorOf: (row, column) {
            if (showOpening && row == 0) {
              return column == balanceColumn ? PdfColors.grey800 : null;
            }
            final line = rows[showOpening ? row - 1 : row];
            if (column == incomeColumn) return PdfColors.green800;
            if (column == outgoingColumn) return PdfColors.red800;
            if (column == balanceColumn) {
              return line.balance >= 0 ? PdfColors.green800 : PdfColors.red800;
            }
            return null;
          },
        ),
        pw.SizedBox(height: 12),
        _statRow([
          if (showOpening)
            _statTile(
              'رصيد افتتاحي',
              '${openingBalance >= 0 ? '' : '-'}\$${formatMoney(openingBalance.abs())}',
              PdfColors.grey800,
            ),
          _statTile(
            'إجمالي الدخول',
            '+\$${formatMoney(incomeTotal)}',
            PdfColors.green800,
          ),
          _statTile(
            'إجمالي الخروج',
            '-\$${formatMoney(outgoingTotal)}',
            PdfColors.red800,
          ),
          _statTile(
            'الرصيد',
            '${balance >= 0 ? '+' : '-'}\$${formatMoney(balance.abs())}',
            balance >= 0 ? PdfColors.green800 : PdfColors.red800,
          ),
        ]),
      ],
    );

    return doc.save();
  }
  /// "حوالات الدخول إلى حساباتي": the entries of the period, same look as the
  /// movement statement.
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
    String? employeeName,
  }) {
    final rows = <_KindRow>[
      for (final b in buys)
        () {
          final exchange = exchangeById[b.exchangeId];
          final code = (exchange?.ourCode ?? '').trim();
          final client = b.clientId != null ? clientById[b.clientId!] : null;
          return _KindRow(
            t: b.archivedAt ?? b.createdAt,
            code: code.isEmpty ? '—' : code,
            myAccount: _slash(companyById[b.myCompanyId]?.name, exchange?.name),
            reference: b.reference.isEmpty
                ? (b.id.length >= 8 ? b.id.substring(0, 8) : b.id)
                : b.reference,
            party: _slash(
              client?.company ?? '',
              client?.name ?? b.clientFromAccount ?? '',
            ),
            amount: b.usdAmount,
          );
        }(),
    ];
    return _buildKindReport(
      title: 'حوالات الدخول إلى حساباتي',
      emptyMessage: 'لا توجد عمليات دخول في الفترة المحددة',
      income: true,
      rows: rows,
      start: start,
      end: end,
      exportedBy: exportedBy,
      notificationText: notificationText,
      employeeName: employeeName,
    );
  }

  /// "حوالات الخروج من حساباتي": the exits of the period, same look.
  Future<Uint8List> buildOutgoingDetailsReport({
    required List<Transfer> transfers,
    required Map<String, Company> companyById,
    required Map<String, Exchange> exchangeById,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
    String? notificationText,
    String? employeeName,
  }) {
    final rows = <_KindRow>[
      for (final t in transfers)
        _KindRow(
          t: t.archivedAt ?? t.createdAt,
          // For an exit this is the beneficiary's account code.
          code: (t.beneficiaryCode == null || t.beneficiaryCode!.isEmpty)
              ? '—'
              : t.beneficiaryCode!,
          myAccount: _slash(
            companyById[t.companyId]?.name,
            exchangeById[t.exchangeId]?.name,
          ),
          reference: t.reference.isEmpty
              ? (t.id.length >= 8 ? t.id.substring(0, 8) : t.id)
              : t.reference,
          party: _slash(t.beneficiaryAccountCompany, t.beneficiaryName),
          amount: t.amount,
        ),
    ];
    return _buildKindReport(
      title: 'حوالات الخروج من حساباتي',
      emptyMessage: 'لا توجد عمليات خروج في الفترة المحددة',
      income: false,
      rows: rows,
      start: start,
      end: end,
      exportedBy: exportedBy,
      notificationText: notificationText,
      employeeName: employeeName,
    );
  }

  Future<Uint8List> _buildKindReport({
    required String title,
    required String emptyMessage,
    required bool income,
    required List<_KindRow> rows,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
    String? notificationText,
    String? employeeName,
  }) async {
    final doc = pw.Document(theme: _theme);
    final dayFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('HH:mm');
    final sorted = [...rows]..sort((a, b) => a.t.compareTo(b.t));

    final exportedAtTime = DateTime.now();
    final logo = await _loadLogo();
    final header = _periodHeader(
      title: title,
      period: periodLabel(start, end),
      logo: logo,
      notificationText: notificationText,
    );

    if (sorted.isEmpty) {
      _addEmptyReportPage(
        doc,
        theme: _theme,
        header: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [header, _identityStrip(employeeName)],
        ),
        message: emptyMessage,
        at: exportedAtTime,
        by: exportedBy,
      );
      return doc.save();
    }

    // Reading order (right → left). كود الحساب comes first, then حساباتي, then
    // إشاري. Every column and its data are centred.
    const headers = <String>[
      'ت',
      'الوقت',
      'التاريخ',
      'كود الحساب',
      'حساباتي',
      'إشاري',
      'الجهة',
      'القيمة',
    ];
    const widths = <double>[0.5, 0.9, 1.1, 1.3, 2.2, 1.4, 2.6, 1.5];

    final total = sorted.fold<double>(0, (s, r) => s + r.amount);
    final color = income ? PdfColors.green800 : PdfColors.red800;
    final sign = income ? '+' : '-';

    _addReportPages(
      doc,
      theme: _theme,
      at: exportedAtTime,
      by: exportedBy,
      body: [
        header,
        _identityStrip(employeeName),
        _reportTable(
          headers: headers,
          widths: widths,
          rows: [
            for (var i = 0; i < sorted.length; i++)
              [
                '${i + 1}',
                timeFmt.format(sorted[i].t),
                dayFmt.format(sorted[i].t),
                sorted[i].code,
                sorted[i].myAccount,
                sorted[i].reference,
                sorted[i].party,
                '$sign${formatMoney(sorted[i].amount)} \$',
              ],
          ],
          colorOf: (row, column) => column == 7 ? color : null,
        ),
        pw.SizedBox(height: 12),
        _statRow([
          _statTile(
            income ? 'إجمالي الدخول' : 'إجمالي الخروج',
            '$sign\$${formatMoney(total)}',
            color,
          ),
          _statTile(
            'عدد المعاملات',
            '${sorted.length}',
            PdfColors.grey800,
          ),
        ]),
      ],
    );

    return doc.save();
  }
}
