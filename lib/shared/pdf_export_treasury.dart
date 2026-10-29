part of 'pdf_export.dart';

// The administrator's money reports, in the look of the period reports
// (header, one centred table, the totals as tiles, the export line):
//
//   تقرير الأرباح   the realized profit of a period, per account (0085)
//   تقرير الخزينة   every account's dollars, cost and book value, and the
//                   dinars in the box and the bank (0082, 0086)

String _signedLyd(double v) =>
    v < 0 ? '−${formatMoney(-v)} د.ل' : '+${formatMoney(v)} د.ل';

PdfColor _profitPdfColor(double v) =>
    v < 0 ? PdfColors.red800 : (v > 0 ? PdfColors.green800 : PdfColors.grey800);

extension TreasuryReports on PdfExport {
  /// "تقرير الأرباح": every account's dollars sold, their sale and cost in
  /// dinars, the profit, and what was bought, for [start]..[end].
  Future<Uint8List> buildProfitReport({
    required List<ProfitRow> rows,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final at = DateTime.now();
    final header = _periodHeader(
      title: 'تقرير الأرباح',
      period: periodLabel(start, end),
      logo: await _loadLogo(),
    );
    if (rows.isEmpty) {
      _addEmptyReportPage(
        doc,
        theme: _theme,
        header: header,
        message: 'لا عمليات في هذه الفترة',
        at: at,
        by: exportedBy,
      );
      return doc.save();
    }
    final t = ProfitTotals.of(rows);
    String rate(double? v) => v == null ? '—' : v.toStringAsFixed(4);

    _addReportPages(
      doc,
      theme: _theme,
      at: at,
      by: exportedBy,
      body: [
        header,
        _reportTable(
          headers: const [
            'ت',
            'الحساب',
            'الدولار المباع',
            'قيمة البيع',
            'تكلفة المباع',
            'الربح',
            'الدولار المشترى',
            'المدفوع للشراء',
          ],
          widths: const [0.5, 2.6, 1.3, 1.5, 1.5, 1.5, 1.3, 1.5],
          rows: [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                _slash(rows[i].companyName, rows[i].accountName) +
                    (rows[i].book == null
                        ? ''
                        : rows[i].book == 'bank'
                            ? ' · مصرفي'
                            : ' · نقدي'),
                '\$${formatMoney(rows[i].soldUsd)}',
                '${formatMoney(rows[i].salesLyd)} د.ل',
                '${formatMoney(rows[i].costLyd)} د.ل',
                _signedLyd(rows[i].profitLyd),
                '\$${formatMoney(rows[i].boughtUsd)}',
                '${formatMoney(rows[i].boughtLyd)} د.ل',
              ],
          ],
          colorOf: (row, column) =>
              column == 5 ? _profitPdfColor(rows[row].profitLyd) : null,
        ),
        pw.SizedBox(height: 12),
        _statRow([
          _statTile(
            'صافي الربح',
            _signedLyd(t.profitLyd),
            _profitPdfColor(t.profitLyd),
          ),
          if (t.marginPercent != null)
            _statTile(
              'الهامش على التكلفة',
              '${t.marginPercent!.toStringAsFixed(2)}%',
              PdfColors.grey800,
            ),
          _statTile('متوسط سعر البيع', rate(t.avgSellRate), PdfColors.grey800),
          _statTile(
            'متوسط تكلفة المباع',
            rate(t.avgCostRate),
            PdfColors.grey800,
          ),
          _statTile('متوسط سعر الشراء', rate(t.avgBuyRate), PdfColors.grey800),
        ]),
        if (t.exitsUnpriced > 0) ...[
          pw.SizedBox(height: 8),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: _ArText(
              '${t.exitsUnpriced} بيع بقيمة \$${formatMoney(t.unpricedUsd)} '
              'بلا سعر أو بلا تكلفة: لم يدخل في الربح.',
              style:
                  const pw.TextStyle(fontSize: 10, color: PdfColors.orange800),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
        ],
      ],
    );
    return doc.save();
  }

  /// "تقرير الخزينة": every account's balance, cost price, book value and
  /// unrealized profit (at the last sell rate), then the dinar treasury.
  Future<Uint8List> buildTreasuryReport({
    required List<TreasuryPosition> positions,
    LydSummary? dinars,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final at = DateTime.now();
    final header = _periodHeader(
      title: 'تقرير الخزينة',
      period: periodLabel(at, at),
      logo: await _loadLogo(),
    );
    final totals = TreasuryTotals.of(positions);
    String cost(double? v) => v == null ? 'لم يُحدَّد' : v.toStringAsFixed(4);

    _addReportPages(
      doc,
      theme: _theme,
      at: at,
      by: exportedBy,
      body: [
        header,
        _reportTable(
          headers: const [
            'ت',
            'الحساب',
            'الرصيد',
            'سعر التكلفة',
            'القيمة الدفترية',
            'غير محقق',
          ],
          widths: const [0.5, 3.0, 1.6, 1.4, 1.8, 1.6],
          rows: [
            for (var i = 0; i < positions.length; i++)
              [
                '${i + 1}',
                _slash(positions[i].companyName, positions[i].accountName),
                '\$${formatMoney(positions[i].balance)}',
                cost(positions[i].costRate),
                positions[i].bookValue == null
                    ? '—'
                    : '${formatMoney(positions[i].bookValue!)} د.ل',
                positions[i].unrealized == null
                    ? '—'
                    : _signedLyd(positions[i].unrealized!),
              ],
          ],
          colorOf: (row, column) =>
              column == 5 && positions[row].unrealized != null
                  ? _profitPdfColor(positions[row].unrealized!)
                  : null,
        ),
        pw.SizedBox(height: 12),
        _statRow([
          _statTile(
            'متوسط سعر التكلفة',
            totals.averageCost == null
                ? '—'
                : totals.averageCost!.toStringAsFixed(4),
            PdfColors.grey800,
          ),
          _statTile(
            'الدولار المحسوب تكلفته',
            '\$${formatMoney(totals.costedUsd)}',
            PdfColors.grey800,
          ),
          _statTile(
            'القيمة الدفترية',
            '${formatMoney((totals.bookValue * 100).round() / 100)} د.ل',
            PdfColors.grey800,
          ),
          if (totals.unrealized != null)
            _statTile(
              'غير محقق بآخر سعر بيع',
              _signedLyd(totals.unrealized!),
              _profitPdfColor(totals.unrealized!),
            ),
        ]),
        if (dinars != null && dinars.open) ...[
          pw.SizedBox(height: 16),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: _ArText(
              'خزينة الدينار',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 6),
          _statRow([
            _statTile(
              'الصندوق',
              '${formatMoney(dinars.cash)} د.ل',
              PdfColors.grey800,
            ),
            _statTile(
              'المصرف',
              '${formatMoney(dinars.bank)} د.ل',
              PdfColors.grey800,
            ),
            _statTile(
              'المجموع',
              '${formatMoney(dinars.total)} د.ل',
              PdfColors.blue800,
            ),
          ]),
        ],
      ],
    );
    return doc.save();
  }
}

extension CustomerReports on PdfExport {
  /// "كشف حساب عميل بالدينار" (migration 0091): the balance before the
  /// period, every line with its running balance, and the balance now.
  Future<Uint8List> buildCustomerStatement({
    required String customer,
    double? creditLimit,
    required CustomerStatement statement,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final at = DateTime.now();
    final dayFmt = _LibyaFmt('yyyy/MM/dd HH:mm');
    String side(double v) => v.abs() < 0.005
        ? 'مسدَّد'
        : (v > 0
            ? 'لنا ${formatMoney(v)} د.ل'
            : 'علينا ${formatMoney(-v)} د.ل');
    final header = _periodHeader(
      title: 'كشف حساب عميل بالدينار',
      period: periodLabel(start, end),
      logo: await _loadLogo(),
      extraLines: [
        customer,
        creditLimit == null
            ? 'بلا حد دين'
            : 'حد الدين ${formatMoney(creditLimit)} د.ل',
      ],
    );
    final running = statement.running;
    _addReportPages(
      doc,
      theme: _theme,
      at: at,
      by: exportedBy,
      body: [
        header,
        _reportTable(
          headers: const [
            'ت',
            'التاريخ',
            'البيان',
            'الإشاري',
            'الدولار',
            'السعر',
            'مدين',
            'دائن',
            'الرصيد',
          ],
          widths: const [0.5, 1.6, 1.6, 1.2, 1.2, 0.9, 1.3, 1.3, 1.8],
          rows: [
            [
              '',
              '',
              'الرصيد قبل الفترة',
              '',
              '',
              '',
              '',
              '',
              side(statement.opening),
            ],
            for (var i = 0; i < statement.entries.length; i++)
              () {
                final e = statement.entries[i];
                return [
                  '${i + 1}',
                  dayFmt.format(e.createdAt),
                  e.label,
                  (e.reference ?? '').isEmpty ? '—' : e.reference!,
                  e.usd == null ? '—' : '\$${formatMoney(e.usd!)}',
                  e.rate == null ? '—' : formatRate(e.rate!),
                  e.amount > 0 ? formatMoney(e.amount) : '',
                  e.amount < 0 ? formatMoney(-e.amount) : '',
                  side(running[i]),
                ];
              }(),
          ],
          colorOf: (row, column) => row == 0
              ? null
              : column == 6
                  ? PdfColors.green800
                  : (column == 7 ? PdfColors.red800 : null),
        ),
        pw.SizedBox(height: 12),
        _statRow([
          _statTile('قبل الفترة', side(statement.opening), PdfColors.grey800),
          _statTile(
            'الرصيد الآن',
            side(statement.closing),
            statement.closing > 0
                ? PdfColors.green800
                : (statement.closing < 0
                    ? PdfColors.red800
                    : PdfColors.grey800),
          ),
        ]),
      ],
    );
    return doc.save();
  }
}

extension LedgerReports on PdfExport {
  String _lyd(double v) =>
      v < 0 ? '−${formatMoney(-v)} د.ل' : '${formatMoney(v)} د.ل';

  pw.Widget _title(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: _ArText(
            t,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
      );

  /// "قائمة الدخل" (migration 0092): the income and the expenses of
  /// [start]..[end] from the journal, and the net profit.
  Future<Uint8List> buildIncomeStatement({
    required IncomeStatement statement,
    required DateTime start,
    required DateTime end,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final at = DateTime.now();
    final header = _periodHeader(
      title: 'قائمة الدخل',
      period: periodLabel(start, end),
      logo: await _loadLogo(),
    );
    _addReportPages(
      doc,
      theme: _theme,
      at: at,
      by: exportedBy,
      body: [
        header,
        _title('الإيرادات'),
        _reportTable(
          headers: const ['الحساب', 'المبلغ'],
          widths: const [4, 2],
          rows: [
            for (final l in statement.income) [l.name, _lyd(l.amount)],
            if (statement.income.isEmpty) ['لا شيء', ''],
          ],
        ),
        _title('المصروفات والخسائر'),
        _reportTable(
          headers: const ['الحساب', 'المبلغ'],
          widths: const [4, 2],
          rows: [
            for (final l in statement.expenses) [l.name, _lyd(-l.amount)],
            if (statement.expenses.isEmpty) ['لا شيء', ''],
          ],
        ),
        pw.SizedBox(height: 12),
        _statRow([
          _statTile(
            'صافي الربح',
            _lyd(statement.net),
            _profitPdfColor(statement.net),
          ),
        ]),
      ],
    );
    return doc.save();
  }

  /// "الميزانية" (migration 0092) at [at].
  Future<Uint8List> buildBalanceSheet({
    required BalanceSheet sheet,
    required DateTime at,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final header = _periodHeader(
      title: 'الميزانية',
      period: periodLabel(at, at),
      logo: await _loadLogo(),
    );
    final b = sheet;
    _addReportPages(
      doc,
      theme: _theme,
      at: now,
      by: exportedBy,
      body: [
        header,
        _title('الأصول'),
        _reportTable(
          headers: const ['البند', 'المبلغ'],
          widths: const [4, 2],
          rows: [
            ['الصندوق', _lyd(b.cash)],
            ['المصرف', _lyd(b.bank)],
            ['ذمم العملاء (لنا عليهم)', _lyd(b.receivable)],
            ['الدولار بالتكلفة', _lyd(b.dollarsAtCost)],
            if (b.unvalued.abs() >= 0.005)
              ['دولار غير مقيّم', _lyd(b.unvalued)],
            ['مجموع الأصول', _lyd(b.totalAssets)],
          ],
        ),
        _title('الالتزامات وحقوق الملكية'),
        _reportTable(
          headers: const ['البند', 'المبلغ'],
          widths: const [4, 2],
          rows: [
            ['ذمم دائنة (علينا للبائعين)', _lyd(b.payable)],
            ['رأس المال والأرصدة الافتتاحية', _lyd(b.capital)],
            if (b.revaluation.abs() >= 0.005)
              ['إعادة تقييم التكلفة', _lyd(b.revaluation)],
            if (b.outsideTreasury.abs() >= 0.005)
              ['نقدية خارج خزينة الدينار', _lyd(b.outsideTreasury)],
            ['الأرباح حتى التاريخ', _lyd(b.profitToDate)],
            ['المجموع', _lyd(b.totalLiabilitiesAndEquity)],
          ],
        ),
        _title('الدولار في كل حساب'),
        _reportTable(
          headers: const ['الحساب', 'الرصيد', 'التكلفة', 'القيمة'],
          widths: const [3, 1.5, 1.2, 2],
          rows: [
            for (final i in b.inventory)
              [
                _slash(i.companyName, i.accountName),
                '\$${formatMoney(i.balance)}',
                i.costRate == null ? '—' : i.costRate!.toStringAsFixed(4),
                i.bookValue == null ? 'بلا تكلفة' : _lyd(i.ledgerValue),
              ],
          ],
        ),
      ],
    );
    return doc.save();
  }

  /// "ميزان المراجعة" (migration 0092) at [at].
  Future<Uint8List> buildTrialBalance({
    required List<TrialLine> lines,
    required DateTime at,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final header = _periodHeader(
      title: 'ميزان المراجعة',
      period: periodLabel(at, at),
      logo: await _loadLogo(),
    );
    final t = trialTotals(lines);
    _addReportPages(
      doc,
      theme: _theme,
      at: now,
      by: exportedBy,
      body: [
        header,
        _reportTable(
          headers: const ['الرمز', 'الحساب', 'مدين', 'دائن', 'الرصيد'],
          widths: const [0.8, 3, 1.6, 1.6, 1.8],
          rows: [
            for (final l in lines)
              [
                l.account,
                l.name,
                formatMoney(l.debit),
                formatMoney(l.credit),
                l.balance >= 0
                    ? 'مدين ${formatMoney(l.balance)}'
                    : 'دائن ${formatMoney(-l.balance)}',
              ],
            ['', 'المجموع', formatMoney(t.debit), formatMoney(t.credit), ''],
          ],
        ),
      ],
    );
    return doc.save();
  }
}
