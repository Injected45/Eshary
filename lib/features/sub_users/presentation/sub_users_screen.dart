import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../branches/presentation/branches_providers.dart';
import '../data/sub_users_repository.dart';
import '../domain/sub_user.dart';
import 'add_sub_user_dialog.dart';
import 'code_display_dialog.dart';
import 'employee_activity_screen.dart';
import 'sub_users_providers.dart';

class SubUsersScreen extends ConsumerWidget {
  const SubUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subUsersListProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('إدارة الموظفين'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              friendlyError(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textLow),
            ),
          ),
        ),
        data: (rows) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openAddDialog(context, ref),
                icon: const FaIcon(FontAwesomeIcons.userPlus, size: 14),
                label: const Text('إضافة موظف'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(
                  child: Column(
                    children: [
                      FaIcon(
                        FontAwesomeIcons.usersSlash,
                        size: 36,
                        color: AppColors.textLow,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'لا يوجد موظفون مسجلون بعد',
                        style: TextStyle(
                          color: AppColors.textLow,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...rows.map((u) => _SubUserCard(user: u)),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    final result = await showGlassDialog<AddSubUserResult>(
      context: context,
      builder: (_) => const AddSubUserDialog(),
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(subUsersListProvider);
    await showGlassDialog<void>(
      context: context,
      builder: (_) => CodeDisplayDialog(
        employeeName: result.name,
        phoneNumber: result.phone,
        code: result.plainCode,
      ),
    );
  }
}

class _SubUserCard extends ConsumerWidget {
  const _SubUserCard({required this.user});
  final SubUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const FaIcon(
                    FontAwesomeIcons.userTie,
                    size: 16,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.employeeName,
                        style: const TextStyle(
                          color: AppColors.textHigh,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.phoneNumber,
                        style: const TextStyle(
                          color: AppColors.textLow,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (user.branchId != null && user.branchId!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Consumer(
                            builder: (context, ref, _) {
                              final branches =
                                  ref.watch(branchesListProvider).value;
                              final name = branches
                                  ?.where((b) => b.id == user.branchId)
                                  .map((b) => b.name)
                                  .firstOrNull;
                              if (name == null) return const SizedBox.shrink();
                              return Text(
                                name,
                                style: const TextStyle(
                                  color: AppColors.textMid,
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _openActivity(context),
                  icon: const FaIcon(
                    FontAwesomeIcons.clockRotateLeft,
                    size: 14,
                    color: AppColors.textMid,
                  ),
                  tooltip: 'سجل النشاط',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _regenerateCode(context, ref),
                  icon: const FaIcon(
                    FontAwesomeIcons.key,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  tooltip: 'إظهار / توليد كود جديد',
                  visualDensity: VisualDensity.compact,
                ),
                _StatusBadge(status: user.status),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _RoleChip(role: user.role),
                const Spacer(),
                if (!user.loginCodeUsed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'لم يسجّل دخوله بعد',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.glassBorder, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _regenerateCode(context, ref),
                    icon: const FaIcon(
                      FontAwesomeIcons.arrowsRotate,
                      size: 12,
                    ),
                    label: const Text(
                      'كود جديد',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(
                        color: AppColors.accent.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleStatus(context, ref),
                    icon: FaIcon(
                      user.status == SubUserStatus.active
                          ? FontAwesomeIcons.userSlash
                          : FontAwesomeIcons.userCheck,
                      size: 12,
                    ),
                    label: Text(
                      user.status == SubUserStatus.active ? 'تعطيل' : 'تفعيل',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: user.status == SubUserStatus.active
                          ? AppColors.negative
                          : AppColors.positive,
                      side: BorderSide(
                        color: (user.status == SubUserStatus.active
                                ? AppColors.negative
                                : AppColors.positive)
                            .withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (user.deviceId != null && user.deviceId!.isNotEmpty)
                  IconButton(
                    onPressed: () => _resetDevice(context, ref),
                    icon: const FaIcon(
                      FontAwesomeIcons.mobileScreen,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    tooltip: 'إعادة ضبط الجهاز',
                  ),
                IconButton(
                  onPressed: () => _delete(context, ref),
                  icon: const FaIcon(
                    FontAwesomeIcons.trashCan,
                    size: 14,
                    color: AppColors.negative,
                  ),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openActivity(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeActivityScreen(subUser: user),
      ),
    );
  }

  Future<void> _regenerateCode(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('توليد كود جديد'),
        content: Text(
          'سيتم استبدال الكود السابق وفك ربط الجهاز عن ${user.employeeName}. '
          'سيحتاج الموظف لتسجيل الدخول من جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('توليد'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final newCode =
          await ref.read(subUsersRepositoryProvider).regenerateCode(user.id);
      if (!context.mounted) return;
      ref.invalidate(subUsersListProvider);
      await showGlassDialog<void>(
        context: context,
        builder: (_) => CodeDisplayDialog(
          employeeName: user.employeeName,
          phoneNumber: user.phoneNumber,
          code: newCode,
          isRegenerated: true,
        ),
      );
    } catch (e, st) {
      AppLogger.error('subUsers.regenerateCode', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _resetDevice(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إعادة ضبط الجهاز'),
        content: Text(
          'سيتم فك ربط ${user.employeeName} عن جهازه الحالي. '
          'يستطيع الدخول من جهاز جديد باستخدام نفس الكود الأصلي. '
          'الجلسة الحالية ستُغلق فوراً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إعادة الضبط'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(subUsersRepositoryProvider).resetDevice(user.id);
      ref.invalidate(subUsersListProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم فك ربط جهاز ${user.employeeName}'),
        ),
      );
    } catch (e, st) {
      AppLogger.error('subUsers.resetDevice', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _toggleStatus(BuildContext context, WidgetRef ref) async {
    final next = user.status == SubUserStatus.active
        ? SubUserStatus.disabled
        : SubUserStatus.active;
    try {
      await ref.read(subUsersRepositoryProvider).updateStatus(
            id: user.id,
            status: next,
          );
      ref.invalidate(subUsersListProvider);
    } catch (e, st) {
      AppLogger.error('subUsers.toggleStatus', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف موظف'),
        content: Text('حذف ${user.employeeName} نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(subUsersRepositoryProvider).delete(user.id);
      ref.invalidate(subUsersListProvider);
    } catch (e, st) {
      AppLogger.error('subUsers.delete', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final SubUserStatus status;

  @override
  Widget build(BuildContext context) {
    final isActive = status == SubUserStatus.active;
    final color = isActive ? AppColors.positive : AppColors.negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isActive ? 'نشط' : 'معطل',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final SubUserRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        subUserRoleLabel(role),
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
