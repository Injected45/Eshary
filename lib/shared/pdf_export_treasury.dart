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
                _slash(rows[i].companyName, rows[i].accountName),
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
              '${t.exitsUnpriced} خروج بقيمة \$${formatMoney(t.unpricedUsd)} '
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
