import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme.dart';
import '../features/employee_auth/presentation/employee_auth_providers.dart';
import '../features/sub_users/presentation/sub_users_providers.dart';
import 'formatters.dart';

/// Per-creator counter strip placed above a daily/pending table. For each
/// distinct author (admin + every employee with at least one row), shows
/// the operation count and the summed amount. Hidden for employee
/// sessions since they only ever see their own rows already.
class CreatorStats<T> extends ConsumerWidget {
  const CreatorStats({
    super.key,
    required this.rows,
    required this.amountOf,
    required this.creatorOf,
    required this.accent,
  });

  final List<T> rows;
  final double Function(T row) amountOf;
  final String? Function(T row) creatorOf;

  /// Colour used for the amount text — usually [AppColors.positive] for
  /// inflows and [AppColors.negative] for outflows.
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEmployeeProvider)) return const SizedBox.shrink();
    if (rows.isEmpty) return const SizedBox.shrink();

    // Aggregate: key = sub_user_id, or null for admin-authored rows.
    final counts = <String?, int>{};
    final totals = <String?, double>{};
    for (final r in rows) {
      final k = creatorOf(r);
      counts[k] = (counts[k] ?? 0) + 1;
      totals[k] = (totals[k] ?? 0) + amountOf(r);
    }

    final subUsers = ref.watch(subUsersListProvider).value ?? const [];
    String labelFor(String? id) {
      if (id == null) return 'أنا';
      final match = subUsers.where((s) => s.id == id).map((s) => s.employeeName);
      return match.isEmpty ? 'موظف محذوف' : match.first;
    }

    // Stable, predictable order: admin first, then employees sorted by
    // descending count so the busiest stand out.
    final keys = counts.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return counts[b]!.compareTo(counts[a]!);
      });

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final k in keys) ...[
              _StatTile(
                label: labelFor(k),
                count: counts[k]!,
                total: totals[k]!,
                isAdmin: k == null,
                accent: accent,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.count,
    required this.total,
    required this.isAdmin,
    required this.accent,
  });

  final String label;
  final int count;
  final double total;
  final bool isAdmin;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tint = isAdmin ? AppColors.accent : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.20),
              border: Border.all(color: tint.withValues(alpha: 0.4)),
            ),
            child: FaIcon(
              isAdmin
                  ? FontAwesomeIcons.userShield
                  : FontAwesomeIcons.userTie,
              size: 11,
              color: tint,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHigh,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textLow,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(
                    ' • ',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textLow,
                    ),
                  ),
                  Text(
                    '\$${formatMoney(total)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
