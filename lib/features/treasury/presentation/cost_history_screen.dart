import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/logger.dart';
import '../domain/profit_report.dart';
import '../domain/treasury_position.dart';
import 'treasury_providers.dart';
import 'treasury_screen.dart' show formatCost;

final LibyaDateFormat _fmt = LibyaDateFormat('yyyy/MM/dd  HH:mm');

/// Every change of one account's cost (account_cost_events), newest first:
/// what moved it, the balance and the cost before and after. Append-only.
class CostHistoryScreen extends ConsumerWidget {
  const CostHistoryScreen({super.key, required this.position});
  final TreasuryPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(costHistoryProvider(position.exchangeId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('سجل تكلفة ${position.accountName}'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            friendlyError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
        ),
        data: (events) => events.isEmpty
            ? const Center(
                child: Text(
                  'لا توجد حركات بعد',
                  style: TextStyle(color: AppColors.textLow),
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  contentBottomPadding(context),
                ),
                itemCount: events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _EventCard(event: events[i]),
              ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final CostEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final up = e.costBefore != null && e.costAfter > e.costBefore!;
    final down = e.costBefore != null && e.costAfter < e.costBefore!;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHigh,
                  ),
                ),
              ),
              Text(
                _fmt.format(e.createdAt),
                style: const TextStyle(fontSize: 11, color: AppColors.textLow),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (e.usdAmount != null && e.rate != null)
            Text(
              '\$${formatMoney(e.usdAmount!)} بسعر ${formatRate(e.rate!)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMid),
            ),
          Text(
            'الرصيد \$${formatMoney(e.balanceBefore)} ← \$${formatMoney(e.balanceAfter)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMid),
          ),
          const SizedBox(height: 4),
          Text(
            e.costBefore == null
                ? 'التكلفة: ${formatCost(e.costAfter)}'
                : 'التكلفة: ${formatCost(e.costBefore!)} ← ${formatCost(e.costAfter)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: up
                  ? AppColors.negative
                  : (down ? AppColors.positive : AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}
