import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/logger.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/saved_clients_dialog.dart';
import '../data/customers_repository.dart';
import '../domain/customer_account.dart';
import 'customer_statement_screen.dart';

/// Every customer's dinar account, read again each time the screen opens.
final customerBalancesProvider =
    FutureProvider.autoDispose<List<CustomerBalance>>((ref) {
  return ref.watch(customersRepositoryProvider).balances();
});

String _lyd(double v) => '${formatMoney(v)} د.ل';

Color balanceColor(double v) => v > 0.005
    ? AppColors.positive
    : (v < -0.005 ? AppColors.negative : AppColors.textMid);

/// «ذمم العملاء» (migration 0091): what each customer owes us for dollars sold
/// on credit, what we owe each seller for dollars bought on credit, and the
/// limits. Administrator only.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  Future<void> _openOne(BuildContext context, WidgetRef ref) async {
    final picked = await showGlassDialog<Client>(
      context: context,
      builder: (_) => const SavedClientsDialog(),
    );
    if (picked == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerStatementScreen(
          clientId: picked.id,
          title: [
            picked.name,
            if ((picked.company ?? '').trim().isNotEmpty) picked.company!,
          ].join(' / '),
          creditLimit: picked.creditLimit,
        ),
      ),
    );
    ref.invalidate(customerBalancesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerBalancesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('ذمم العملاء'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('customer-open'),
            tooltip: 'حساب عميل',
            icon: const FaIcon(FontAwesomeIcons.userPlus, size: 15),
            onPressed: () => _openOne(context, ref),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(customerBalancesProvider),
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
        data: (all) {
          // each book on its own (0093): cash and bank dinars never add up
          Widget totals(String title, CustomerTotals t) => GlassCard(
                child: Column(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMid,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _Total(
                            'لنا على العملاء',
                            _lyd(t.receivable),
                            AppColors.positive,
                          ),
                        ),
                        Expanded(
                          child: _Total(
                            'علينا للبائعين',
                            _lyd(t.payable),
                            AppColors.negative,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
          return ListView(
            padding:
                EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
            children: [
              totals('الدفتر النقدي', CustomerTotals.of(all, book: 'cash')),
              const SizedBox(height: 8),
              totals('الدفتر المصرفي', CustomerTotals.of(all, book: 'bank')),
              const SizedBox(height: 12),
              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'لا توجد ذمم بعد. البيع أو الشراء بالآجل يفتح حساب '
                    'العميل هنا، ويمكنك فتح حساب عميل من الزر في الأعلى '
                    'لتحديد حد الدين أو رصيده الافتتاحي.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textLow),
                  ),
                ),
              for (final c in all)
                _CustomerCard(
                  c: c,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomerStatementScreen(
                          clientId: c.clientId,
                          title: c.title,
                          creditLimit: c.creditLimit,
                        ),
                      ),
                    );
                    ref.invalidate(customerBalancesProvider);
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMid),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.c, required this.onTap});
  final CustomerBalance c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = c.lastAt == null
        ? null
        : LibyaDateFormat('yyyy/MM/dd').format(c.lastAt!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          key: ValueKey('customer-${c.clientId}'),
          onTap: onTap,
          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              c.creditLimit == null
                  ? 'بلا حد دين'
                  : 'حد الدين ${_lyd(c.creditLimit!)}',
              if (when != null) 'آخر حركة $when',
            ].join(' · '),
            style: TextStyle(
              fontSize: 12,
              color: c.overLimit ? AppColors.warning : AppColors.textLow,
            ),
          ),
          // each book on its own line (0093): never one figure for both
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (label, b) in [
                ('نقدي', c.balanceCash),
                ('مصرفي', c.balanceBank),
              ])
                if (b.abs() >= 0.005)
                  Text(
                    '$label: ${customerBalanceLabel(b, formatMoney)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: balanceColor(b),
                    ),
                  ),
              if (c.balanceCash.abs() < 0.005 && c.balanceBank.abs() < 0.005)
                const Text('مسدَّد'),
            ],
          ),
        ),
      ),
    );
  }
}
