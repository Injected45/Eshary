import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../data/treasury_repository.dart';
import '../domain/treasury_position.dart';
import 'cost_history_screen.dart';
import 'profit_section.dart';
import 'treasury_providers.dart';

/// A cost price as kept by the database (6 decimals), shown to 4.
String formatCost(double v) => v.toStringAsFixed(4);

/// A profit (+) or a loss (−) in dinars, signed.
String formatProfit(double v) =>
    v < 0 ? '−${formatMoney(-v)} د.ل' : '+${formatMoney(v)} د.ل';

Color profitColor(double v) => v < 0
    ? AppColors.negative
    : (v > 0 ? AppColors.positive : AppColors.textHigh);

/// The administrator's treasury: every account's dollars and their cost price
/// (weighted average, migration 0082). Only an entry with a rate moves a cost;
/// exits, commissions and edited balances leave it as it is.
class TreasuryScreen extends ConsumerWidget {
  const TreasuryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(treasuryProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الخزينة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () {
              ref.invalidate(treasuryProvider);
              ref.invalidate(profitReportProvider);
            },
          ),
        ],
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
        data: (rows) {
          final totals = TreasuryTotals.of(rows);
          return ListView(
            padding:
                EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
            children: [
              _SummaryCard(totals: totals),
              const SizedBox(height: 16),
              const ProfitSection(),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: Text(
                  'الحسابات',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHigh,
                  ),
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'لا توجد حسابات حتى الآن',
                      style: TextStyle(color: AppColors.textLow),
                    ),
                  ),
                )
              else
                for (final p in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AccountCostCard(position: p),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals});
  final TreasuryTotals totals;

  @override
  Widget build(BuildContext context) {
    final avg = totals.averageCost;
    return GlassCard(
      key: const ValueKey('treasury-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'متوسط سعر تكلفة الدولار',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMid),
          ),
          const SizedBox(height: 6),
          Text(
            avg == null ? '—' : '${formatCost(avg)} د.ل',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'الدولار المحسوب تكلفته',
                  value: '\$${formatMoney(totals.costedUsd)}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Figure(
                  label: 'قيمته الدفترية',
                  value: '${formatMoney(totals.bookValue)} د.ل',
                ),
              ),
            ],
          ),
          if (totals.unrealized != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ربح غير محقق لو بيع الآن بآخر سعر بيع',
                    style: TextStyle(fontSize: 12, color: AppColors.textMid),
                  ),
                ),
                Text(
                  formatProfit(totals.unrealized!),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: profitColor(totals.unrealized!),
                  ),
                ),
              ],
            ),
          ],
          if (totals.uncosted > 0) ...[
            const SizedBox(height: 12),
            Text(
              totals.uncosted == 1
                  ? 'حساب واحد فيه دولار بلا سعر تكلفة. حدّد سعر أول المدة له.'
                  : '${totals.uncosted} حسابات فيها دولار بلا سعر تكلفة. حدّد سعر أول المدة لها.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'يتغير سعر التكلفة مع كل دخول بسعره، ولا يغيّره الخروج.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textLow),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textLow),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textHigh,
          ),
        ),
      ],
    );
  }
}

class _AccountCostCard extends ConsumerWidget {
  const _AccountCostCard({required this.position});
  final TreasuryPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = position;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p.accountName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          Text(
            p.companyName,
            style: const TextStyle(fontSize: 12, color: AppColors.textLow),
          ),
          const SizedBox(height: 12),
          _Line('الرصيد', '\$${formatMoney(p.balance)}'),
          _Line(
            'سعر التكلفة (التعادل)',
            p.hasCost ? '${formatCost(p.costRate!)} د.ل' : 'لم يُحدَّد',
            color: p.hasCost ? AppColors.accent : AppColors.warning,
          ),
          _Line(
            'القيمة الدفترية',
            p.bookValue == null ? '—' : '${formatMoney(p.bookValue!)} د.ل',
          ),
          if (p.unrealized != null)
            _Line(
              'غير محقق (بسعر ${formatRate(p.marketRate!)})',
              formatProfit(p.unrealized!),
              color: profitColor(p.unrealized!),
            ),
          const SizedBox(height: 10),
          if (!p.hasCost)
            FilledButton.icon(
              key: ValueKey('set-opening-${p.exchangeId}'),
              onPressed: () => _setCost(context, ref, p),
              icon: const FaIcon(FontAwesomeIcons.scaleBalanced, size: 12),
              label: const Text('تحديد سعر أول المدة'),
            )
          else
            // two buttons: on a narrow phone the second one wraps under
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              children: [
                TextButton.icon(
                  key: ValueKey('cost-history-${p.exchangeId}'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CostHistoryScreen(position: p),
                    ),
                  ),
                  icon:
                      const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 11),
                  label: const Text('سجل التكلفة'),
                ),
                TextButton.icon(
                  key: ValueKey('correct-cost-${p.exchangeId}'),
                  onPressed: () => _setCost(context, ref, p),
                  icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 11),
                  label: const Text('تصحيح السعر'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _setCost(
    BuildContext context,
    WidgetRef ref,
    TreasuryPosition p,
  ) async {
    final rate = await showDialog<double>(
      context: context,
      builder: (_) => _CostDialog(position: p),
    );
    if (rate == null) return;
    try {
      await ref.read(treasuryRepositoryProvider).setCost(p.exchangeId, rate);
      ref.invalidate(treasuryProvider);
      if (context.mounted) {
        showTopSnackBar(
          context,
          SnackBar(
            content: Text(
              'سعر تكلفة ${p.accountName}: ${formatCost(rate)} د.ل',
            ),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.error('treasury.setCost', e, st);
      if (context.mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // a long label wraps instead of pushing the figure off the card
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMid),
            ),
          ),
          const SizedBox(width: 12),
          // a large figure shrinks to fit; it is never cut
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
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

/// Asks for the cost of ONE dollar of what the account holds now. Returns it,
/// or null when cancelled.
class _CostDialog extends StatefulWidget {
  const _CostDialog({required this.position});
  final TreasuryPosition position;

  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  final _rate = TextEditingController();

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.position;
    final rate = parseRate(_rate.text);
    final valid = rateInRange(rate);
    return AlertDialog(
      title: Text(p.hasCost ? 'تصحيح سعر التكلفة' : 'سعر تكلفة أول المدة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'رصيد ${p.accountName} الآن \$${formatMoney(p.balance)}. '
            'اكتب كم دينارًا كلّفك الدولار الواحد منه.',
          ),
          if (p.hasCost) ...[
            const SizedBox(height: 8),
            Text(
              'السعر الحالي ${formatCost(p.costRate!)} سيُستبدل، ويُحفظ التصحيح في السجل.',
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('cost-rate-field'),
            controller: _rate,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'سعر التكلفة (د.ل لكل \$)',
              hintText: 'مثال 7.10',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (rate > 0 && !valid) ...[
            const SizedBox(height: 10),
            const Text(
              'سعر غير معقول: يجب أن يكون بين 1 و 100 دينار للدولار.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.negative),
            ),
          ] else if (valid) ...[
            const SizedBox(height: 10),
            Text(
              // balance × cost to 6 decimals, as the database values it
              'القيمة الدفترية: ${formatMoney((p.balance * rate * 100).round() / 100)} د.ل',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textMid),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('cost-save'),
          onPressed: valid ? () => Navigator.of(context).pop(rate) : null,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
