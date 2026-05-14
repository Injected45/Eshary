import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../sub_users/presentation/sub_users_providers.dart';
import '../data/branches_repository.dart';
import '../domain/branch.dart';
import 'add_branch_dialog.dart';
import 'branches_providers.dart';

class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(branchesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الفروع'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
            tooltip: 'إضافة فرع جديد',
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddBranchDialog(
                  onSaved: () {
                    ref.invalidate(branchesListProvider);
                    ref.invalidate(subUsersListProvider);
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: asyncList.when(
        data: (branches) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (branches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'لا توجد فروع حتى الآن',
                    style: TextStyle(color: AppColors.textLow),
                  ),
                ),
              ),
            for (final b in branches)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BranchTile(branch: b),
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
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class _BranchTile extends ConsumerWidget {
  const _BranchTile({required this.branch});
  final Branch branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.codeBranch,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              branch.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textHigh,
              ),
            ),
          ),
          IconButton(
            tooltip: 'تعديل',
            icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddBranchDialog(
                  existing: branch,
                  onSaved: () {
                    ref.invalidate(branchesListProvider);
                    ref.invalidate(subUsersListProvider);
                  },
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const FaIcon(
              FontAwesomeIcons.trash,
              size: 14,
              color: AppColors.negative,
            ),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'حذف الفرع؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سيتم فصل الفرع عن أي موظف مرتبط به (دون حذف الموظف).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textLow,
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.negative,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(true),
                      child: const Text('حذف'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(branchesRepositoryProvider).delete(branch.id);
        ref.invalidate(branchesListProvider);
        ref.invalidate(subUsersListProvider);
      } catch (e, st) {
        AppLogger.error('branches.delete', e, st);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}
