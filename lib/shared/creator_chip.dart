import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme.dart';
import '../features/sub_users/presentation/sub_users_providers.dart';

/// Small badge identifying who created a row: the admin themselves
/// ("أنا") or a named sub-user. Looks up the employee name from
/// [subUsersListProvider] so a deleted sub_user still renders something
/// (the raw id) rather than crashing.
class CreatorChip extends ConsumerWidget {
  const CreatorChip({super.key, required this.createdByEmployeeId});

  /// null → admin authored the row; non-null → employee id to resolve.
  final String? createdByEmployeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (createdByEmployeeId == null) {
      return _Pill(
        label: 'أنا',
        icon: FontAwesomeIcons.userShield,
        color: AppColors.accent,
      );
    }
    final all = ref.watch(subUsersListProvider).value;
    final found = all
        ?.where((s) => s.id == createdByEmployeeId)
        .map((s) => s.employeeName)
        .firstOrNull;
    return _Pill(
      label: found ?? 'موظف محذوف',
      icon: FontAwesomeIcons.userTie,
      color: found == null ? AppColors.textLow : AppColors.warning,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 10, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
