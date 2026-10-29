part of 'pdf_export.dart';

// The «التقارير» tab (migration 0095), in the look of the period reports:
//
//   تقرير الفترة     sales, purchases, profit and margin per book, the
//                    balances at the start and the end, credit,
//                    cancellations, per account and per day
//   أداء الموظفين    per employee of a period
//   أعمار الديون     who owes us and since when, and whom we owe

String _bookName(String? b) => b == 'bank' ? 'مصرفي' : 'نقدي';
String _rateOrDash(double? v) => v == null ? '—' : formatRate(v);

extension BusinessReports on PdfExport {
  pw.Widget _section(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: _ArText(
            t,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
      );

  Future<Uint8List> buildPeriodReport({
    required PeriodReport report,
    required DateTime first,
    required DateTime last,
    String? exportedBy,
  }) async {
    final r = report;
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final money = (double v) => formatMoney(v);
    _addReportPages(
      doc,
      theme: _theme,
      at: now,
      by: exportedBy,
      body: [
        _periodHeader(
          title: 'تقرير الفترة',
          period: periodLabel(first, last),
          logo: await _loadLogo(),
        ),
        pw.SizedBox(height: 6),
        _statRow([
          _statTile(
              'الربح المحقق', _signedLyd(r.profit), _profitPdfColor(r.profit)),
          _statTile(
              'العمليات',
              '${r.saleN + r.buyN} (بيع ${r.saleN} · شراء ${r.buyN})',
              PdfColors.grey900),
          _statTile('إجمالي البيع', '\$${money(r.saleUsd)}', PdfColors.grey900),
          _statTile('إجمالي الشراء', '\$${money(r.buyUsd)}', PdfColors.grey900),
        ]),
        _section('حسب الدفتر'),
        _reportTable(
          headers: const [
            'الدفتر',
            'بيع (عدد)',
            'بيع \$',
            'بيع د.ل',
            'شراء (عدد)',
            'شراء \$',
            'شراء د.ل',
            'متوسط البيع',
            'متوسط الشراء',
            'تكلفة المباع',
            'الربح',
          ],
          widths: const [1, 0.8, 1.2, 1.3, 0.8, 1.2, 1.3, 1, 1, 1, 1.3],
          rows: [
            for (final b in r.books)
              [
                _bookName(b.book),
                '${b.saleN}',
                money(b.saleUsd),
                money(b.saleLyd),
                '${b.buyN}',
                money(b.buyUsd),
                money(b.buyLyd),
                _rateOrDash(b.avgSellRate),
                _rateOrDash(b.avgBuyRate),
                _rateOrDash(b.avgCostSold),
                _signedLyd(b.profit),
              ],
          ],
          colorOf: (row, col) =>
              col == 10 ? _profitPdfColor(r.books[row].profit) : null,
        ),
        _section('الأرصدة أول الفترة وآخرها'),
        _reportTable(
          headers: const ['البند', 'أول الفترة', 'آخر الفترة', 'التغير'],
          widths: const [2, 1.5, 1.5, 1.5],
          rows: [
            for (final b in r.books)
              [
                'دولار ${_bookName(b.book)}',
                '\$${money(b.usdStart)}',
                '\$${money(b.usdEnd)}',
                '\$${money(b.usdEnd - b.usdStart)}',
              ],
            if (r.lyd.open) ...[
              [
                'دينار الخزينة',
                '${money(r.lyd.cashStart)} د.ل',
                '${money(r.lyd.cashEnd)} د.ل',
                _signedLyd(r.lyd.cashEnd - r.lyd.cashStart),
              ],
              [
                'دينار المصرف',
                '${money(r.lyd.bankStart)} د.ل',
                '${money(r.lyd.bankEnd)} د.ل',
                _signedLyd(r.lyd.bankEnd - r.lyd.bankStart),
              ],
            ],
          ],
        ),
        _section('الآجل والإلغاءات'),
        _reportTable(
          headers: const ['البند', 'القيمة'],
          widths: const [3, 2],
          rows: [
            ['بعنا بالآجل', '${money(r.creditGiven)} د.ل'],
            ['حصّلنا من العملاء', '${money(r.creditCollected)} د.ل'],
            ['اشترينا بالآجل', '${money(r.creditTaken)} د.ل'],
            ['سددنا للدائنين', '${money(r.creditPaid)} د.ل'],
            ['لنا على العملاء آخر الفترة', '${money(r.owedToUs)} د.ل'],
            ['علينا للدائنين آخر الفترة', '${money(r.weOwe)} د.ل'],
            ['العمليات الملغاة', '${r.cancelledN}'],
          ],
        ),
        if (r.byAccount.isNotEmpty) ...[
          _section('حسب الحساب'),
          _reportTable(
            headers: const [
              'الشركة',
              'الحساب',
              'الدفتر',
              'بيع \$',
              'بيع د.ل',
              'شراء \$',
              'شراء د.ل',
              'الربح',
            ],
            widths: const [1.6, 1.6, 0.9, 1.2, 1.3, 1.2, 1.3, 1.3],
            rows: [
              for (final a in r.byAccount)
                [
                  a.sub ?? '',
                  a.label,
                  _bookName(a.book),
                  money(a.saleUsd),
                  money(a.saleLyd),
                  money(a.buyUsd),
                  money(a.buyLyd),
                  _signedLyd(a.profit),
                ],
            ],
          ),
        ],
        if (r.byDay.length > 1) ...[
          _section('حسب اليوم'),
          _reportTable(
            headers: const [
              'اليوم',
              'بيع (عدد)',
              'بيع \$',
              'بيع د.ل',
              'شراء (عدد)',
              'شراء \$',
              'شراء د.ل',
              'الربح',
            ],
            widths: const [1.3, 0.8, 1.2, 1.3, 0.8, 1.2, 1.3, 1.3],
            rows: [
              for (final d in r.byDay)
                [
                  DateFormat('yyyy/MM/dd').format(d.day!),
                  '${d.saleN}',
                  money(d.saleUsd),
                  money(d.saleLyd),
                  '${d.buyN}',
                  money(d.buyUsd),
                  money(d.buyLyd),
                  _signedLyd(d.profit),
                ],
            ],
          ),
        ],
        _section('مقارنة بالفترة السابقة'),
        _reportTable(
          headers: const ['البند', 'هذه الفترة', 'الفترة السابقة'],
          widths: const [2, 1.5, 1.5],
          rows: [
            ['عمليات البيع', '${r.saleN}', '${r.previousSaleN}'],
            ['البيع \$', money(r.saleUsd), money(r.previousSaleUsd)],
            ['عمليات الشراء', '${r.buyN}', '${r.previousBuyN}'],
            ['الشراء \$', money(r.buyUsd), money(r.previousBuyUsd)],
            [
              'الربح المحقق',
              _signedLyd(r.profit),
              _signedLyd(r.previousProfit)
            ],
          ],
        ),
      ],
    );
    return doc.save();
  }

  Future<Uint8List> buildEmployeesReport({
    required PeriodReport report,
    required DateTime first,
    required DateTime last,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    _addReportPages(
      doc,
      theme: _theme,
      at: now,
      by: exportedBy,
      body: [
        _periodHeader(
          title: 'أداء الموظفين',
          period: periodLabel(first, last),
          logo: await _loadLogo(),
        ),
        pw.SizedBox(height: 6),
        _reportTable(
          headers: const [
            'الموظف',
            'العمليات',
            'بيع (عدد)',
            'بيع \$',
            'شراء (عدد)',
            'شراء \$',
            'ربح مبيعاته',
            'باع بالآجل',
            'ملغاة',
          ],
          widths: const [2, 0.9, 0.9, 1.3, 0.9, 1.3, 1.4, 1.3, 0.8],
          rows: [
            for (final e in report.byEmployee)
              [
                e.label,
                '${e.operations}',
                '${e.saleN}',
                formatMoney(e.saleUsd),
                '${e.buyN}',
                formatMoney(e.buyUsd),
                _signedLyd(e.profit),
                '${formatMoney(e.creditGiven)} د.ل',
                '${e.cancelledN}',
              ],
          ],
          colorOf: (row, col) =>
              col == 6 ? _profitPdfColor(report.byEmployee[row].profit) : null,
        ),
      ],
    );
    return doc.save();
  }

  Future<Uint8List> buildDebtAgingReport({
    required DebtAging aging,
    String? exportedBy,
  }) async {
    final a = aging;
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final f = DateFormat('yyyy/MM/dd');
    _addReportPages(
      doc,
      theme: _theme,
      at: now,
      by: exportedBy,
      body: [
        _periodHeader(
          title: 'أعمار الديون',
          period: periodLabel(now, now),
          logo: await _loadLogo(),
        ),
        pw.SizedBox(height: 6),
        _statRow([
          _statTile('لنا على العملاء', '${formatMoney(a.owedToUs)} د.ل',
              PdfColors.grey900),
          _statTile('أكثر من 90 يومًا', '${formatMoney(a.older)} د.ل',
              a.older > 0 ? PdfColors.red800 : PdfColors.grey900),
          _statTile('تجاوزوا الحد', '${a.overLimit}',
              a.overLimit > 0 ? PdfColors.red800 : PdfColors.grey900),
          _statTile('علينا للدائنين', '${formatMoney(a.weOwe)} د.ل',
              PdfColors.grey900),
        ]),
        _section('العملاء المدينون'),
        _reportTable(
          headers: const [
            'العميل',
            'المستحق',
            'حتى 7 أيام',
            '8–30',
            '31–90',
            'أكثر من 90',
            'أقدم دين',
            'آخر تحصيل',
            'الحد',
          ],
          widths: const [2, 1.3, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1, 1.1],
          rows: [
            for (final d in a.debtors)
              [
                d.company == null || d.company!.isEmpty
                    ? d.name
                    : '${d.name} — ${d.company}',
                formatMoney(d.owed),
                formatMoney(d.d7),
                formatMoney(d.d30),
                formatMoney(d.d90),
                formatMoney(d.older),
                d.oldest == null ? '—' : f.format(d.oldest!),
                d.lastCollect == null ? '—' : f.format(d.lastCollect!),
                d.overLimit
                    ? 'متجاوز'
                    : (d.limit == null ? '—' : formatMoney(d.limit!)),
              ],
          ],
          colorOf: (row, col) => (col == 8 && a.debtors[row].overLimit) ||
                  (col == 5 && a.debtors[row].older > 0)
              ? PdfColors.red800
              : null,
        ),
        if (a.creditors.isNotEmpty) ...[
          _section('الدائنون (علينا)'),
          _reportTable(
            headers: const ['الجهة', 'المستحق لها'],
            widths: const [3, 2],
            rows: [
              for (final c in a.creditors)
                [
                  c.company == null || c.company!.isEmpty
                      ? c.name
                      : '${c.name} — ${c.company}',
                  '${formatMoney(c.owed)} د.ل',
                ],
            ],
          ),
        ],
      ],
    );
    return doc.save();
  }
}
