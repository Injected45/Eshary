import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../branches/presentation/branches_providers.dart';
import '../data/sub_users_repository.dart';
import '../domain/employee_permissions.dart';
import '../domain/sub_user.dart';
import 'add_sub_user_dialog.dart';
import 'code_display_dialog.dart';
import 'employee_activity_screen.dart';
import 'employee_permissions_dialog.dart';
import 'qr_display_dialog.dart';
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
        skipLoadingOnReload: true,
        skipError: true,
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
          padding: EdgeInsets.fromLTRB(16, 8, 16, contentBottomPadding(context)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textHigh,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => _editPhone(context, ref),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user.phoneNumber,
                              style: const TextStyle(
                                color: AppColors.textLow,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 6),
                            const FaIcon(
                              FontAwesomeIcons.pen,
                              size: 9,
                              color: AppColors.textLow,
                            ),
                          ],
                        ),
                      ),
                      if (user.googleEmail != null &&
                          user.googleEmail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            user.googleEmail!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMid,
                              fontSize: 11,
                            ),
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
                const SizedBox(width: 8),
                _StatusBadge(status: user.status),
              ],
            ),
            const SizedBox(height: 10),
            // Quick actions on their own line, so they no longer squeeze the
            // name and the phone number above.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
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
                  onPressed: () => _openPermissions(context),
                  icon: const FaIcon(
                    FontAwesomeIcons.userShield,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  tooltip: 'صلاحيات',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: user.status == SubUserStatus.active
                      ? () => _issueQr(context, ref)
                      : null,
                  icon: const FaIcon(
                    FontAwesomeIcons.qrcode,
                    size: 14,
                    color: AppColors.positive,
                  ),
                  tooltip: 'إصدار QR للدخول',
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
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _PermissionsSummary(permissions: user.permissions),
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

  Future<void> _openPermissions(BuildContext context) async {
    final saved = await showGlassDialog<bool>(
      context: context,
      builder: (_) => EmployeePermissionsDialog(user: user),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ صلاحيات ${user.employeeName}')),
      );
    }
  }

  void _openActivity(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeActivityScreen(subUser: user),
      ),
    );
  }

  /// The employee got a new number: WhatsApp codes follow the registered one.
  Future<void> _editPhone(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: user.phoneNumber);
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('رقم ${user.employeeName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(hintText: '09XXXXXXXX'),
            ),
            const SizedBox(height: 8),
            const Text(
              'يجب أن يكون رقم واتساب. رمز التحقق يصل إلى هذا الرقم.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || phone == user.phoneNumber || !context.mounted) return;
    if (!RegExp(r'^09[0-9]{8}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الصيغة: 09XXXXXXXX (10 أرقام)')),
      );
      return;
    }
    try {
      await ref.read(subUsersRepositoryProvider).updatePhone(user.id, phone);
      ref.invalidate(subUsersListProvider);
    } catch (e, st) {
      AppLogger.error('subUsers.updatePhone', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _issueQr(BuildContext context, WidgetRef ref) async {
    var resetDevice = false;
    final bound = user.deviceId != null && user.deviceId!.isNotEmpty;
    if (bound) {
      // A bound employee can only sign in from the same phone. Let the admin
      // choose to move them to a new one in the same step.
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('إصدار QR'),
          content: Text(
            '${user.employeeName} مرتبط بجهاز حالياً. الـ QR يعمل من نفس '
            'الجهاز فقط، إلا إذا فككت الربط ليدخل من جهاز جديد '
            '(تُغلق جلسته الحالية).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('نفس الجهاز'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(context, 'reset'),
              child: const Text('جهاز جديد'),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      resetDevice = choice == 'reset';
    }
    try {
      final qr = await ref
          .read(subUsersRepositoryProvider)
          .createQr(user.id, resetDevice: resetDevice);
      if (!context.mounted) return;
      ref.invalidate(subUsersListProvider);
      await showGlassDialog<void>(
        context: context,
        builder: (_) => QrDisplayDialog(
          employeeName: user.employeeName,
          phoneNumber: user.phoneNumber,
          qr: qr,
        ),
      );
    } catch (e, st) {
      AppLogger.error('subUsers.issueQr', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
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

/// What the employee can do right now, at a glance. Orange when nothing is
/// granted: that employee opens an empty app.
class _PermissionsSummary extends StatelessWidget {
  const _PermissionsSummary({required this.permissions});
  final List<String> permissions;

  @override
  Widget build(BuildContext context) {
    final none = permissions.isEmpty;
    final color = none ? AppColors.warning : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        none
            ? 'بدون صلاحيات'
            : '${permissions.length} من ${kEmployeePermissions.length} صلاحيات',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
