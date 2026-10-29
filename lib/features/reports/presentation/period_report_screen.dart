import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../treasury/domain/account_books.dart';
import '../data/reports_repository.dart';
import '../domain/reports.dart';
import 'report_pdf.dart';
import 'report_period_picker.dart';
import 'report_widgets.dart';

/// «تقرير الفترة»: today by default (the end-of-day report), or any period —
/// sales and purchases per book, the realized profit and the margin, the
/// dollars and dinars at the start and the end, credit, cancellations, per
/// account and per day, against the previous period.
class PeriodReportScreen extends ConsumerStatefulWidget {
  const PeriodReportScreen({super.key});

  @override
  ConsumerState<PeriodReportScreen> createState() => _PeriodReportScreenState();
}

class _PeriodReportScreenState extends ConsumerState<PeriodReportScreen> {
  ReportPeriod _period = ReportPeriod.today();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(periodReportProvider(_period.range));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('تقرير الفترة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
            onPressed: async.valueOrNull == null
                ? null
                : () => exportPeriodPdf(
                      context,
                      ref,
                      report: async.value!,
                      period: _period,
                    ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(periodReportProvider),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, contentBottomPadding(context)),
        children: [
          ReportPeriodPicker(
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: 8),
          Text(
            _period.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMid),
          ),
          const SizedBox(height: 8),
          async.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) =>
                ReportMessage(friendlyError(e), color: AppColors.negative),
            data: (r) => _ReportBody(report: r),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});
  final PeriodReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final profitChange =
        changeText(PeriodReport.change(r.profit, r.previousProfit));
    final saleChange =
        changeText(PeriodReport.change(r.saleUsd, r.previousSaleUsd));
    final buyChange =
        changeText(PeriodReport.change(r.buyUsd, r.previousBuyUsd));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // the headline
        ReportTileRow([
          ReportTile(
            label: 'الربح المحقق',
            value: signedLydText(r.profit),
            color: signedColor(r.profit),
            sub:
                profitChange == null ? null : '$profitChange عن الفترة السابقة',
          ),
          ReportTile(
            label: 'العمليات',
            value: '${r.saleN + r.buyN}',
            sub: 'بيع ${r.saleN} · شراء ${r.buyN}',
          ),
        ]),
        ReportTileRow([
          ReportTile(
            label: 'إجمالي البيع',
            value: usdText(r.saleUsd),
            sub: saleChange == null ? null : '$saleChange عن الفترة السابقة',
          ),
          ReportTile(
            label: 'إجمالي الشراء',
            value: usdText(r.buyUsd),
            sub: buyChange == null ? null : '$buyChange عن الفترة السابقة',
          ),
        ]),
        if (r.unpricedN > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${r.unpricedN} عملية بيع بلا سعر أو بلا تكلفة: خارج حساب الربح.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.warning),
            ),
          ),

        const ReportSectionTitle('حسب الدفتر'),
        for (final b in r.books) _BookCard(b: b),

        const ReportSectionTitle('الأرصدة أول الفترة وآخرها'),
        ReportCard(children: [
          for (final b in r.books)
            ReportLine(
              'دولار ${bookLabel(b.book)}',
              '${usdText(b.usdStart)}  ←  ${usdText(b.usdEnd)}',
            ),
          if (r.lyd.open) ...[
            ReportLine(
              'دينار الخزينة',
              '${lydText(r.lyd.cashStart)}  ←  ${lydText(r.lyd.cashEnd)}',
            ),
            ReportLine(
              'دينار المصرف',
              '${lydText(r.lyd.bankStart)}  ←  ${lydText(r.lyd.bankEnd)}',
            ),
          ] else
            const ReportLine('الدينار', 'خزينة الدينار لم تُفتح'),
        ]),

        const ReportSectionTitle('الآجل'),
        ReportCard(children: [
          ReportLine('بعنا بالآجل (لنا على العملاء)', lydText(r.creditGiven)),
          ReportLine('حصّلنا من العملاء', lydText(r.creditCollected)),
          ReportLine('اشترينا بالآجل (علينا)', lydText(r.creditTaken)),
          ReportLine('سددنا للدائنين', lydText(r.creditPaid)),
          const Divider(height: 14),
          ReportLine('لنا على العملاء آخر الفترة', lydText(r.owedToUs),
              bold: true),
          ReportLine('علينا للدائنين آخر الفترة', lydText(r.weOwe), bold: true),
        ]),

        if (r.cancelledN > 0) ...[
          const ReportSectionTitle('الإلغاءات'),
          ReportCard(children: [
            ReportLine('عدد العمليات الملغاة', '${r.cancelledN}'),
            if (r.cancelledSaleUsd > 0)
              ReportLine('بيع ملغى', usdText(r.cancelledSaleUsd)),
            if (r.cancelledBuyUsd > 0)
              ReportLine('شراء ملغى', usdText(r.cancelledBuyUsd)),
          ]),
        ],

        if (r.byAccount.isNotEmpty) ...[
          const ReportSectionTitle('حسب الحساب'),
          for (final a in r.byAccount)
            ReportCard(children: [
              Text(
                '${a.sub ?? ''} — ${a.label} (${bookLabel(a.book ?? kBookBank)})',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              ReportLine(
                'بيع ${a.saleN}',
                '${usdText(a.saleUsd)} · ${lydText(a.saleLyd)}',
              ),
              ReportLine(
                'شراء ${a.buyN}',
                '${usdText(a.buyUsd)} · ${lydText(a.buyLyd)}',
              ),
              ReportLine('الربح', signedLydText(a.profit),
                  color: signedColor(a.profit)),
            ]),
        ],

        if (r.byDay.length > 1) ...[
          const ReportSectionTitle('حسب اليوم'),
          ReportCard(children: [
            for (final d in r.byDay)
              ReportLine(
                DateFormat('yyyy/MM/dd').format(d.day!),
                'بيع ${usdText(d.saleUsd)} · شراء ${usdText(d.buyUsd)} · '
                '${signedLydText(d.profit)}',
              ),
          ]),
        ],

        if (r.isEmpty) const ReportMessage('لا توجد عمليات في هذه الفترة.'),
      ],
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.b});
  final BookFigures b;

  @override
  Widget build(BuildContext context) {
    String rate(double? v) => v == null ? '—' : formatRate(v);
    return ReportCard(children: [
      Text(
        'الدفتر ${bookLabel(b.book)}',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      const SizedBox(height: 6),
      ReportLine(
          'بيع ${b.saleN}', '${usdText(b.saleUsd)} · ${lydText(b.saleLyd)}'),
      ReportLine(
          'شراء ${b.buyN}', '${usdText(b.buyUsd)} · ${lydText(b.buyLyd)}'),
      ReportLine('متوسط سعر البيع', rate(b.avgSellRate)),
      ReportLine('متوسط سعر الشراء', rate(b.avgBuyRate)),
      ReportLine('متوسط تكلفة المباع', rate(b.avgCostSold)),
      ReportLine('ربح الدولار الواحد', rate(b.marginPerUsd)),
      const Divider(height: 14),
      ReportLine('الربح المحقق', signedLydText(b.profit),
          color: signedColor(b.profit), bold: true),
    ]);
  }
}
