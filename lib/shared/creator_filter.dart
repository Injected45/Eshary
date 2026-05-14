import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme.dart';
import '../features/employee_auth/presentation/employee_auth_providers.dart';
import '../features/sub_users/presentation/sub_users_providers.dart';

/// The currently-selected filter for daily / pending tables.
///   - `null` value `kCreatorAll` (literal "all") → show everything
///   - `kCreatorAdmin` (literal "admin") → only rows created directly by the admin
///   - any other string is interpreted as a sub_user.id
const String kCreatorAll = 'all';
const String kCreatorAdmin = 'admin';

/// Whether a row with the given [createdByEmployeeId] passes the filter.
bool creatorPasses(String filter, String? createdByEmployeeId) {
  if (filter == kCreatorAll) return true;
  if (filter == kCreatorAdmin) return createdByEmployeeId == null;
  return createdByEmployeeId == filter;
}

/// Horizontal chip strip placed above a daily/pending table so the admin
/// can scope the visible rows to "كل العمليات", their own, or a specific
/// employee. Employees see only their own rows already (Phase 3d) so this
/// widget renders nothing for them.
class CreatorFilter extends ConsumerWidget {
  const CreatorFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Employees never see this — they're already filtered to their own.
    if (ref.watch(isEmployeeProvider)) return const SizedBox.shrink();

    final subUsersAsync = ref.watch(subUsersListProvider);
    final employees = subUsersAsync.value ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Chip(
              label: 'الكل',
              icon: FontAwesomeIcons.list,
              value: kCreatorAll,
              selected: selected == kCreatorAll,
              onTap: onChanged,
            ),
            const SizedBox(width: 6),
            _Chip(
              label: 'أنا',
              icon: FontAwesomeIcons.userShield,
              value: kCreatorAdmin,
              selected: selected == kCreatorAdmin,
              onTap: onChanged,
            ),
            for (final e in employees) ...[
              const SizedBox(width: 6),
              _Chip(
                label: e.employeeName,
                icon: FontAwesomeIcons.userTie,
                value: e.id,
                selected: selected == e.id,
                onTap: onChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textLow;
    return InkWell(
      onTap: () => onTap(value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.5)
                : AppColors.glassBorder,
          ),
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
