import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/employee_auth_repository.dart';
import 'employee_auth_providers.dart';

/// "حسابي" for an employee who may see only their own work (accounts_own):
/// per account, what they executed — open and closed, exits and entries. No
/// balances are shown or sent. (With accounts_all the employee gets the full
/// accounts screen instead.)
class EmployeeMyAccountScreen extends ConsumerWidget {
  const EmployeeMyAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeMyAccountProvider);
    final top = contentTopPadding(context);

    return async.when(
      loading: () => Padding(
        padding: EdgeInsets.only(top: top),
        child: const LinearProgressIndicator(),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, contentBottomPadding(context)),
        child: GlassCard(
          child: Text(
            friendlyError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textLow),
          ),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            padding: EdgeInsets.fromLTRB(16, top, 16, contentBottomPadding(context)),
            child: Center(
              child: GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: const Text(
                  'لم تنفّذ أي عملية بعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textLow, fontSize: 14),
                ),
              ),
            ),
          );
        }

        double sum(double Function(MyAccountRow r) f) =>
            rows.fold<double>(0, (s, r) => s + f(r));
        final outTotal = sum((r) => r.outOpenTotal + r.outClosedTotal);
        final inTotal = sum((r) => r.inOpenTotal + r.inClosedTotal);
        // Only the type(s) the admin granted: exits-only shows no "دخول" rows.
        final seesExits = ref.watch(seesExitsProvider);
        final seesEntries = ref.watch(seesEntriesProvider);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(employeeMyAccountProvider);
            await ref.read(employeeMyAccountProvider.future);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, top, 16, contentBottomPadding(context)),
            children: [
              Row(
                children: [
                  if (seesExits)
                    Expanded(
                      child: _TotalTile(
                        label: 'إجمالي ما نفّذته خروجاً',
                        total: outTotal,
                        color: AppColors.negative,
                      ),
                    ),
                  if (seesExits && seesEntries) const SizedBox(width: 12),
                  if (seesEntries)
                    Expanded(
                      child: _TotalTile(
                        label: 'إجمالي ما نفّذته دخولاً',
                        total: inTotal,
                        color: AppColors.positive,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              for (final r in rows) ...[
                _AccountCard(
                  row: r,
                  showOutgoing: seesExits,
                  showIncoming: seesEntries,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TotalTile extends StatelessWidget {
  const _TotalTile({
    required this.label,
    required this.total,
    required this.color,
  });
  final String label;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textLow, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            '\$${formatMoney(total)}',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.row,
    required this.showOutgoing,
    required this.showIncoming,
  });
  final MyAccountRow row;
  final bool showOutgoing;
  final bool showIncoming;

  @override
  Widget build(BuildContext context) {
    final code = (row.ourCode ?? '').isEmpty ? '' : ' · ${row.ourCode}';
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.wallet,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${row.exchangeName} — ${row.companyName}$code',
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.glassBorder, height: 20),
          if (showOutgoing)
            _Line(
              label: 'خروج',
              count: row.outOpenCount + row.outClosedCount,
              total: row.outOpenTotal + row.outClosedTotal,
              color: AppColors.negative,
            ),
          if (showIncoming)
            _Line(
              label: 'دخول',
              count: row.inOpenCount + row.inClosedCount,
              total: row.inOpenTotal + row.inClosedTotal,
              color: AppColors.positive,
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label;
  final int count;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textMid, fontSize: 13),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 110,
            child: Text(
              '\$${formatMoney(total)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: count == 0 ? AppColors.textDim : color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
