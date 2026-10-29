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

  /// «كشف المديونيات»: who owes us and whom we owe, by name, with the cash
  /// and bank parts, what is older than 30 days, the oldest open debt and
  /// the last settlement.
  Future<Uint8List> buildDebtAgingReport({
    required DebtAging aging,
    String? exportedBy,
  }) async {
    final a = aging;
    final doc = pw.Document(theme: _theme);
    final now = DateTime.now();
    final f = DateFormat('yyyy/MM/dd');
    String date(DateTime? d) => d == null ? '—' : f.format(d);

    pw.Widget table(List<DebtRow> rows, {required bool ours}) => _reportTable(
          headers: [
            'م',
            'الاسم',
            'الشركة',
            'الكود',
            'نقدي',
            'مصرفي',
            'الإجمالي',
            'أكثر من 30 يومًا',
            'أقدم دين',
            ours ? 'آخر تحصيل' : 'آخر سداد',
            'الحالة',
          ],
          widths: const [0.5, 2, 1.5, 1, 1.2, 1.2, 1.3, 1.2, 1.1, 1.1, 1.1],
          rows: [
            for (var i = 0; i < rows.length; i++)
              [
                '${i + 1}',
                rows[i].name,
                rows[i].company ?? '',
                rows[i].code ?? '',
                formatMoney(rows[i].cash),
                formatMoney(rows[i].bank),
                formatMoney(rows[i].owed),
                formatMoney(rows[i].late30),
                date(rows[i].oldest),
                date(rows[i].lastSettle),
                rows[i].overLimit
                    ? 'تجاوز الحد'
                    : (rows[i].older > 0.005
                        ? 'متأخر +90'
                        : (rows[i].late30 > 0.005 ? 'متأخر +30' : '')),
              ],
            [
              '',
              'المجموع',
              '',
              '',
              formatMoney(rows.fold<double>(0, (s, r) => s + r.cash)),
              formatMoney(rows.fold<double>(0, (s, r) => s + r.bank)),
              formatMoney(rows.fold<double>(0, (s, r) => s + r.owed)),
              formatMoney(rows.fold<double>(0, (s, r) => s + r.late30)),
              '',
              '',
              '',
            ],
          ],
          colorOf: (row, col) => col == 10 &&
                  row < rows.length &&
                  (rows[row].overLimit || rows[row].older > 0.005)
              ? PdfColors.red800
              : null,
        );

    _addReportPages(
      doc,
      theme: _theme,
      at: now,
      by: exportedBy,
      body: [
        _periodHeader(
          title: 'كشف المديونيات',
          period: periodLabel(now, now),
          logo: await _loadLogo(),
        ),
        pw.SizedBox(height: 6),
        _statRow([
          _statTile('لنا على العملاء', '${formatMoney(a.owedToUs)} د.ل',
              PdfColors.green800),
          _statTile('علينا للدائنين', '${formatMoney(a.weOwe)} د.ل',
              PdfColors.red800),
          _statTile('الصافي', _signedLyd(a.net), _profitPdfColor(a.net)),
          _statTile('تجاوزوا الحد', '${a.overLimit}',
              a.overLimit > 0 ? PdfColors.red800 : PdfColors.grey900),
        ]),
        _section('لنا: العملاء المدينون (${a.debtors.length})'),
        if (a.debtors.isEmpty)
          _section('لا يوجد عميل مدين.')
        else
          table(a.debtors, ours: true),
        _section('علينا: الدائنون (${a.creditors.length})'),
        if (a.creditors.isEmpty)
          _section('لا يوجد دائن.')
        else
          table(a.creditors, ours: false),
      ],
    );
    return doc.save();
  }

  /// «الأرباح والخسائر»: the income statement of the period (every income,
  /// every expense or loss, the net) beside the previous period.
  Future<Uint8List> buildProfitLossReport({
    required IncomeStatement now,
    required IncomeStatement before,
    required DateTime first,
    required DateTime last,
    required String bookTitle,
    String? exportedBy,
  }) async {
    final doc = pw.Document(theme: _theme);
    final at = DateTime.now();
    double prev(IncomeLine l) => before.lines
        .where((b) => b.account == l.account)
        .fold<double>(0, (s, b) => s + b.amount);
    final income = now.income.fold<double>(0, (s, l) => s + l.amount);
    final expenses = -now.expenses.fold<double>(0, (s, l) => s + l.amount);
    String lyd(double v) => '${formatMoney(v)} د.ل';
    _addReportPages(
      doc,
      theme: _theme,
      at: at,
      by: exportedBy,
      body: [
        _periodHeader(
          title: 'الأرباح والخسائر',
          period: periodLabel(first, last),
          logo: await _loadLogo(),
          extraLines: [bookTitle],
        ),
        pw.SizedBox(height: 6),
        _statRow([
          _statTile(
            now.net < 0 ? 'صافي الخسارة' : 'صافي الربح',
            _signedLyd(now.net),
            _profitPdfColor(now.net),
          ),
          _statTile('الإيرادات', lyd(income), PdfColors.green800),
          _statTile('المصروفات والخسائر', lyd(expenses), PdfColors.red800),
          _statTile(
            'صافي الفترة السابقة',
            _signedLyd(before.net),
            _profitPdfColor(before.net),
          ),
        ]),
        _section('الإيرادات'),
        _reportTable(
          headers: const ['البند', 'هذه الفترة', 'الفترة السابقة'],
          widths: const [4, 2, 2],
          rows: [
            for (final l in now.income) [l.name, lyd(l.amount), lyd(prev(l))],
            if (now.income.isEmpty) ['لا شيء', '', ''],
            ['إجمالي الإيرادات', lyd(income), ''],
          ],
        ),
        _section('المصروفات والخسائر'),
        _reportTable(
          headers: const ['البند', 'هذه الفترة', 'الفترة السابقة'],
          widths: const [4, 2, 2],
          rows: [
            for (final l in now.expenses)
              [l.name, lyd(-l.amount), lyd(-prev(l))],
            if (now.expenses.isEmpty) ['لا شيء', '', ''],
            ['إجمالي المصروفات والخسائر', lyd(expenses), ''],
          ],
        ),
        _section('الخلاصة'),
        _reportTable(
          headers: const ['البند', 'هذه الفترة', 'الفترة السابقة'],
          widths: const [4, 2, 2],
          rows: [
            [
              now.net < 0 ? 'صافي الخسارة' : 'صافي الربح',
              _signedLyd(now.net),
              _signedLyd(before.net),
            ],
          ],
          colorOf: (row, col) => col == 1
              ? _profitPdfColor(now.net)
              : (col == 2 ? _profitPdfColor(before.net) : null),
        ),
      ],
    );
    return doc.save();
  }
}
