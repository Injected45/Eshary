import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../archive/presentation/archive_filters.dart';
import '../domain/profit_report.dart';
import 'treasury_providers.dart';
import 'treasury_screen.dart' show formatCost, formatProfit, profitColor;

/// Realized profit of a period (migration 0084): today by default, or a range.
/// Every exit not cancelled, sold at its rate against the account's cost at
/// that moment; exits without a rate or a cost are counted apart.
class ProfitSection extends ConsumerStatefulWidget {
  const ProfitSection({super.key});

  @override
  ConsumerState<ProfitSection> createState() => _ProfitSectionState();
}

class _ProfitSectionState extends ConsumerState<ProfitSection> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;

  bool get _rangeReady => _from != null && _to != null && !_from!.isAfter(_to!);

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: _to ?? DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: _from ?? DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _to = picked);
  }

  @override
  Widget build(BuildContext context) {
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    final async = ref
        .watch(profitReportProvider(DateTimeRange(start: r.start, end: r.end)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            'الأرباح المحققة',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
        ),
        DateFilterBar(
          mode: _mode,
          from: _from,
          to: _to,
          onModeChanged: (m) => setState(() {
            _mode = m;
            if (m == DateFilterMode.today) {
              _from = null;
              _to = null;
            } else {
              _from ??= todayDate();
              _to ??= todayDate();
            }
          }),
          onPickFrom: _pickFrom,
          onPickTo: _pickTo,
          showInvalidHint: _mode == DateFilterMode.range && !_rangeReady,
        ),
        const SizedBox(height: 10),
        async.when(
          skipLoadingOnReload: true,
          skipError: true,
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(
            friendlyError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
          data: (rows) => ProfitCard(rows: rows),
        ),
      ],
    );
  }
}

/// The period's figures: totals, the rates derived from them, and one line per
/// account when there is more than one.
class ProfitCard extends StatelessWidget {
  const ProfitCard({super.key, required this.rows});
  final List<ProfitRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = ProfitTotals.of(rows);
    if (rows.isEmpty) {
      return const GlassCard(
        child: Text(
          'لا عمليات في هذه الفترة',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textLow),
        ),
      );
    }
    String rate(double? v) => v == null ? '—' : formatCost(v);
    return GlassCard(
      key: const ValueKey('profit-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'صافي الربح',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMid),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatProfit(t.profitLyd),
              key: const ValueKey('profit-total'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: profitColor(t.profitLyd),
              ),
            ),
          ),
          if (t.marginPercent != null)
            Text(
              'هامش ${t.marginPercent!.toStringAsFixed(2)}% على التكلفة',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textLow),
            ),
          const SizedBox(height: 12),
          const _Heading('البيع (الخروج)'),
          _Row('الدولار المباع', '\$${formatMoney(t.soldUsd)}'),
          _Row('قيمة البيع', '${formatMoney(t.salesLyd)} د.ل'),
          _Row('تكلفة الدولار المباع', '${formatMoney(t.costLyd)} د.ل'),
          _Row('متوسط سعر البيع', rate(t.avgSellRate)),
          _Row('متوسط تكلفة المباع', rate(t.avgCostRate)),
          _Row(
            'الربح لكل دولار',
            t.marginPerUsd == null ? '—' : formatCost(t.marginPerUsd!),
            color: t.marginPerUsd == null ? null : profitColor(t.marginPerUsd!),
          ),
          const SizedBox(height: 10),
          const _Heading('الشراء (الدخول)'),
          _Row('الدولار المشترى', '\$${formatMoney(t.boughtUsd)}'),
          _Row('المدفوع بالدينار', '${formatMoney(t.boughtLyd)} د.ل'),
          _Row('متوسط سعر الشراء', rate(t.avgBuyRate)),
          const SizedBox(height: 10),
          _Row(
            'صافي حركة الدينار (بيع − شراء)',
            formatProfit(t.netLydFlow),
            color: profitColor(t.netLydFlow),
          ),
          if (t.exitsUnpriced > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${t.exitsUnpriced} خروج بقيمة \$${formatMoney(t.unpricedUsd)} '
              'بلا سعر أو بلا تكلفة: لم يدخل في الربح.',
              key: const ValueKey('profit-unpriced'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ],
          if (rows.length > 1) ...[
            const SizedBox(height: 12),
            const _Heading('حسب الحساب'),
            for (final r in rows)
              _Row(
                '${r.accountName} — ${r.companyName}',
                formatProfit(r.profitLyd),
                color: profitColor(r.profitLyd),
              ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMid),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.textHigh,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
