import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme.dart';
import '../features/employee_auth/presentation/employee_auth_providers.dart';
import '../features/sub_users/domain/sub_user.dart';
import '../features/sub_users/presentation/sub_users_providers.dart';
import 'formatters.dart';

/// Filter values:
///   - `kCreatorAll` → show every row
///   - `kCreatorAdmin` → only rows the admin authored directly
///   - any other string is interpreted as a sub_user.id
const String kCreatorAll = 'all';
const String kCreatorAdmin = 'admin';

bool creatorPasses(String filter, String? createdByEmployeeId) {
  if (filter == kCreatorAll) return true;
  if (filter == kCreatorAdmin) return createdByEmployeeId == null;
  return createdByEmployeeId == filter;
}

/// Collapsed dropdown placed above a daily / pending table. Tapping the
/// field opens a popup listing "كل العمليات", "أنا", and every employee
/// that has at least one row in the current data set, each annotated
/// with its operation count and summed amount.
///
/// Hidden for employee sessions — they only ever see their own rows.
class CreatorFilter<T> extends ConsumerWidget {
  const CreatorFilter({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.rows,
    required this.amountOf,
    required this.creatorOf,
    required this.amountColor,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  /// All rows under the current container (daily / pending). The dropdown
  /// reads them to compute per-creator counters; the table itself is
  /// filtered separately via [creatorPasses].
  final List<T> rows;
  final double Function(T row) amountOf;
  final String? Function(T row) creatorOf;

  /// Colour used for the amount text in each menu item (positive green
  /// for inflows, negative red for outflows, warning yellow for pending).
  final Color amountColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEmployeeProvider)) return const SizedBox.shrink();

    final employees =
        ref.watch(subUsersListProvider).value ?? const <SubUser>[];

    // Aggregate per-creator. null key = admin-authored rows.
    final counts = <String?, int>{};
    final totals = <String?, double>{};
    for (final r in rows) {
      final k = creatorOf(r);
      counts[k] = (counts[k] ?? 0) + 1;
      totals[k] = (totals[k] ?? 0) + amountOf(r);
    }

    final hasAdminRows = counts.containsKey(null);
    final activeEmployees =
        employees.where((e) => counts.containsKey(e.id)).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: PopupMenuButton<String>(
        initialValue: selected,
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        color: AppColors.bgDeep,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.glassBorderStrong),
        ),
        itemBuilder: (_) => [
          _menuItem(
            value: kCreatorAll,
            label: 'كل العمليات',
            icon: FontAwesomeIcons.list,
            count: rows.length,
            total: rows.fold<double>(0, (a, r) => a + amountOf(r)),
            isSelected: selected == kCreatorAll,
          ),
          if (hasAdminRows)
            _menuItem(
              value: kCreatorAdmin,
              label: 'أنا',
              icon: FontAwesomeIcons.userShield,
              count: counts[null]!,
              total: totals[null]!,
              isSelected: selected == kCreatorAdmin,
            ),
          if (activeEmployees.isNotEmpty) const PopupMenuDivider(),
          for (final e in activeEmployees)
            _menuItem(
              value: e.id,
              label: e.employeeName,
              icon: FontAwesomeIcons.userTie,
              count: counts[e.id]!,
              total: totals[e.id]!,
              isSelected: selected == e.id,
            ),
        ],
        child: _SelectedField(
          label: _labelFor(selected, employees),
          icon: _iconFor(selected),
        ),
      ),
    );
  }

  String _labelFor(String value, List<SubUser> employees) {
    if (value == kCreatorAll) return 'كل العمليات';
    if (value == kCreatorAdmin) return 'أنا';
    final match =
        employees.where((s) => s.id == value).map((s) => s.employeeName);
    return match.isEmpty ? 'كل العمليات' : match.first;
  }

  IconData _iconFor(String value) {
    if (value == kCreatorAll) return FontAwesomeIcons.list;
    if (value == kCreatorAdmin) return FontAwesomeIcons.userShield;
    return FontAwesomeIcons.userTie;
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required String label,
    required IconData icon,
    required int count,
    required double total,
    required bool isSelected,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          FaIcon(
            icon,
            size: 12,
            color: isSelected ? AppColors.accent : AppColors.textLow,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$count عملية',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textLow,
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
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: FaIcon(
                FontAwesomeIcons.check,
                size: 11,
                color: AppColors.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectedField extends StatelessWidget {
  const _SelectedField({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.15),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.4),
              ),
            ),
            child: FaIcon(icon, size: 10, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          const Text(
            'تصفية المنفّذ:',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textLow,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textHigh,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const FaIcon(
            FontAwesomeIcons.chevronDown,
            size: 11,
            color: AppColors.textLow,
          ),
        ],
      ),
    );
  }
}
