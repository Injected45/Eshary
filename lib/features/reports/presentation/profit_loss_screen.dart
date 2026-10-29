import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../ledger/domain/ledger.dart';
import '../domain/reports.dart';
import 'report_pdf.dart';
import 'report_period_picker.dart';
import 'report_widgets.dart';

/// A period's profit and loss with the previous period of the same length.
typedef ProfitLoss = ({IncomeStatement now, IncomeStatement before});

/// The ledger's income statement (0092/0093) of a period and of the period
/// just before it, for one book or both (null).
final profitLossProvider = FutureProvider.autoDispose
    .family<ProfitLoss, ({DateTimeRange range, String? book})>(
        (ref, key) async {
  final repo = ref.watch(ledgerRepositoryProvider);
  final r = key.range;
  final before = r.start.subtract(r.end.difference(r.start));
  final (now, prev) = await (
    repo.incomeStatement(r.start, r.end, book: key.book),
    repo.incomeStatement(
      before,
      r.start.subtract(const Duration(microseconds: 1)),
      book: key.book,
    ),
  ).wait;
  return (now: now, before: prev);
});

double sumOf(List<IncomeLine> lines) =>
    lines.fold<double>(0, (s, l) => s + l.amount);

/// «الأرباح والخسائر»: every income and every expense or loss of the period
/// from the general ledger — the result of selling currency, conversions,
/// count differences, adjustments, commissions — and the net, against the
/// previous period. Per book or both.
class ProfitLossScreen extends ConsumerStatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  ConsumerState<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends ConsumerState<ProfitLossScreen> {
  ReportPeriod _period = ReportPeriod.today();
  String? _book;

  @override
  Widget build(BuildContext context) {
    final key = (range: _period.range, book: _book);
    final async = ref.watch(profitLossProvider(key));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الأرباح والخسائر'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
            onPressed: async.valueOrNull == null
                ? null
                : () => exportProfitLossPdf(
                      context,
                      ref,
                      now: async.value!.now,
                      before: async.value!.before,
                      period: _period,
                      bookTitle: _bookTitle(_book),
                    ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(profitLossProvider),
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
          SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('المجموع')),
              ButtonSegment(value: 'cash', label: Text('النقدي')),
              ButtonSegment(value: 'bank', label: Text('المصرفي')),
            ],
            selected: {_book},
            onSelectionChanged: (s) => setState(() => _book = s.first),
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
            data: (pl) => _Body(pl: pl),
          ),
        ],
      ),
    );
  }
}

String _bookTitle(String? book) => switch (book) {
      'cash' => 'الدفتر النقدي',
      'bank' => 'الدفتر المصرفي',
      _ => 'الدفتران معًا',
    };

class _Body extends StatelessWidget {
  const _Body({required this.pl});
  final ProfitLoss pl;

  @override
  Widget build(BuildContext context) {
    final now = pl.now;
    final before = pl.before;
    final income = sumOf(now.income);
    final expenses = -sumOf(now.expenses);
    final change = changeText(PeriodReport.change(now.net, before.net));
    double prevOf(IncomeLine l) => before.lines
        .where((b) => b.account == l.account)
        .fold<double>(0, (s, b) => s + b.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportTileRow([
          ReportTile(
            label: now.net < 0 ? 'صافي الخسارة' : 'صافي الربح',
            value: signedLydText(now.net),
            color: signedColor(now.net),
            sub: change == null
                ? 'الفترة السابقة ${signedLydText(before.net)}'
                : '$change عن الفترة السابقة',
          ),
        ]),
        ReportTileRow([
          ReportTile(
            label: 'إجمالي الإيرادات',
            value: lydText(income),
            color: AppColors.positive,
          ),
          ReportTile(
            label: 'إجمالي المصروفات والخسائر',
            value: lydText(expenses),
            color: expenses > 0 ? AppColors.negative : null,
          ),
        ]),
        const ReportSectionTitle('الإيرادات'),
        ReportCard(children: [
          if (now.income.isEmpty)
            const ReportLine('لا إيرادات في هذه الفترة', '')
          else
            for (final l in now.income)
              _PlLine(
                name: l.name,
                amount: l.amount,
                share: income > 0 ? l.amount / income : null,
                before: prevOf(l),
              ),
        ]),
        const ReportSectionTitle('المصروفات والخسائر'),
        ReportCard(children: [
          if (now.expenses.isEmpty)
            const ReportLine('لا مصروفات ولا خسائر في هذه الفترة', '')
          else
            for (final l in now.expenses)
              _PlLine(
                name: l.name,
                amount: -l.amount,
                share: expenses > 0 ? -l.amount / expenses : null,
                before: -prevOf(l),
                negative: true,
              ),
        ]),
        const ReportSectionTitle('الخلاصة'),
        ReportCard(children: [
          ReportLine('الإيرادات', lydText(income)),
          ReportLine('المصروفات والخسائر', lydText(expenses)),
          const Divider(height: 14),
          ReportLine(
            now.net < 0 ? 'صافي الخسارة' : 'صافي الربح',
            signedLydText(now.net),
            color: signedColor(now.net),
            bold: true,
          ),
          ReportLine('الفترة السابقة', signedLydText(before.net)),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'من الحسابات الختامية: ربح البيع = دينار البيع − تكلفة الدولار المباع. '
            'الإيداع والسحب من الخزينة رأس مال، لا ربح ولا خسارة.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textLow),
          ),
        ),
      ],
    );
  }
}

class _PlLine extends StatelessWidget {
  const _PlLine({
    required this.name,
    required this.amount,
    required this.share,
    required this.before,
    this.negative = false,
  });
  final String name;
  final double amount;
  final double? share;
  final double before;
  final bool negative;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  lydText(amount),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: negative ? AppColors.negative : AppColors.positive,
                  ),
                ),
              ],
            ),
            Text(
              [
                if (share != null) '${(share! * 100).round()} % من الإجمالي',
                'السابقة ${lydText(before)}',
              ].join('  ·  '),
              style: const TextStyle(fontSize: 11, color: AppColors.textLow),
            ),
          ],
        ),
      );
}
