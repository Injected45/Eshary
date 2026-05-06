import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import 'history_details_screen.dart';

class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedBuys =
        ref.watch(archivedBuysProvider).value ?? const <CurrencyBuy>[];
    final archivedTransfers =
        ref.watch(archivedTransfersProvider).value ?? const <Transfer>[];

    final incomeTotal =
        archivedBuys.fold<double>(0, (s, b) => s + b.usdAmount);
    final outgoingTotal =
        archivedTransfers.fold<double>(0, (s, t) => s + t.amount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                income: true,
                total: incomeTotal,
                archivedCount: archivedBuys.length,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                income: false,
                total: outgoingTotal,
                archivedCount: archivedTransfers.length,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DetailNavTile(
          income: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const HistoryDetailsScreen(kind: HistoryKind.income),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DetailNavTile(
          income: false,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const HistoryDetailsScreen(kind: HistoryKind.outgoing),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'شركة الرحالة للبرمجيات . جميع الحقوق محفوظة 2026 ©',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.income,
    required this.total,
    required this.archivedCount,
  });
  final bool income;
  final double total;
  final int archivedCount;

  @override
  Widget build(BuildContext context) {
    final tint = income ? AppColors.positive : AppColors.negative;
    final hasArchive = archivedCount > 0;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tint, width: 1.5),
              color: tint.withValues(alpha: 0.08),
            ),
            child: FaIcon(
              income
                  ? FontAwesomeIcons.arrowTrendDown
                  : FontAwesomeIcons.arrowTrendUp,
              size: 22,
              color: tint,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            income ? 'إجمالي الدخول' : 'إجمالي الخروج',
            style: const TextStyle(
              color: AppColors.textMid,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          if (hasArchive)
            Text(
              '\$${formatMoney(total)}',
              style: TextStyle(
                color: tint,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            )
          else
            const Text(
              'لا توجد إقفالات بعد',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textLow,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailNavTile extends StatelessWidget {
  const _DetailNavTile({required this.income, required this.onTap});
  final bool income;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = income ? AppColors.positive : AppColors.negative;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tint, width: 1.5),
                  color: tint.withValues(alpha: 0.08),
                ),
                child: FaIcon(
                  income
                      ? FontAwesomeIcons.arrowTrendDown
                      : FontAwesomeIcons.arrowTrendUp,
                  size: 14,
                  color: tint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  income
                      ? 'عرض تفاصيل الدخول'
                      : 'عرض تفاصيل الخروج',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.glassFillStrong,
                  border: Border.all(color: AppColors.glassBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const FaIcon(
                  FontAwesomeIcons.filePdf,
                  size: 14,
                  color: AppColors.textMid,
                ),
              ),
              const SizedBox(width: 6),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 12,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
