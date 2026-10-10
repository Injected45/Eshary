import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/admin_repository.dart';
import 'deleted_accounts_screen.dart';
import '../../../shared/top_message.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(adminUsersListProvider);
    // Wait for the next emission so RefreshIndicator collapses cleanly.
    await ref.read(adminUsersListProvider.future);
  }

  Future<void> _runAction({
    required AdminUserRow row,
    required String confirmTitle,
    required String confirmBody,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    final ok = await _confirm(confirmTitle, confirmBody);
    if (ok != true) return;
    try {
      await action();
      // Force the list to refetch; the watching widgets rebuild on next emit.
      ref.invalidate(adminUsersListProvider);
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(content: Text(successMessage)),
      );
    } catch (e, st) {
      AppLogger.error('admin.action', e, st);
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(
          backgroundColor: AppColors.negative.withValues(alpha: 0.85),
          content: Text(
            friendlyError(e),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<bool?> _confirm(String title, String body) {
    return showGlassDialog<bool>(
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
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('تأكيد'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selfUid = Supabase.instance.client.auth.currentUser?.id;
    final query = _search.text.trim().toLowerCase();
    final asyncRows = ref.watch(adminUsersListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('إدارة الحسابات'),
        actions: [
          IconButton(
            key: const ValueKey('deleted-accounts-log'),
            tooltip: 'سجل الحسابات المحذوفة',
            icon: const FaIcon(FontAwesomeIcons.trashCanArrowUp, size: 15),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DeletedAccountsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'بحث بالبريد الإلكتروني أو رقم الهاتف',
                  prefixIcon: Icon(Icons.search, color: AppColors.textLow),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: asyncRows.when(
                  skipLoadingOnReload: true,
                  skipError: true,
                  loading: () => const Center(
                    child: SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.triangleExclamation,
                              color: AppColors.negative,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              friendlyError(e),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textHigh,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _reload,
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  data: (all) {
                    final rows = query.isEmpty
                        ? all
                        : all
                            .where(
                              (r) =>
                                  r.email.toLowerCase().contains(query) ||
                                  (r.phone ?? '').contains(query),
                            )
                            .toList();
                    if (rows.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [
                          SizedBox(height: 32),
                          Center(
                            child: Text(
                              'لا توجد نتائج',
                              style: TextStyle(color: AppColors.textLow),
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                          16, 4, 16, contentBottomPadding(context)),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => AdminUserCard(
                        // Key on userId+status+isAdmin so the card rebuilds
                        // its chips immediately when those change.
                        key: ValueKey(
                          '${rows[i].userId}'
                          ':${rows[i].status}'
                          ':${rows[i].isAdmin}'
                          ':${rows[i].licenseType}',
                        ),
                        row: rows[i],
                        isSelf: rows[i].userId == selfUid,
                        onActivateTrial: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'تفعيل تجريبي 3 أيام',
                          confirmBody:
                              'سيتم منح ${rows[i].email} فترة تجريبية لمدة 3 أيام.',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .activateTrial(rows[i].email),
                          successMessage: 'تم تفعيل الفترة التجريبية',
                        ),
                        onActivateLifetime: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'تفعيل دائم',
                          confirmBody:
                              'سيتم تفعيل ${rows[i].email} بخطة دائمة بدون انتهاء.',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .activateLifetime(rows[i].email),
                          successMessage: 'تم التفعيل الدائم',
                        ),
                        onBlock: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'حظر المستخدم',
                          confirmBody:
                              'سيتم حظر ${rows[i].email} وتسجيل خروجه من جلسته الحالية خلال 30 ثانية.',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .block(rows[i].email),
                          successMessage: 'تم حظر المستخدم',
                        ),
                        onSetPending: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'إعادة لبانتظار التفعيل',
                          confirmBody:
                              'سيتم إرجاع ${rows[i].email} إلى حالة "بانتظار التفعيل".',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .setPending(rows[i].email),
                          successMessage: 'تم تحديث الحالة',
                        ),
                        onGrantAdmin: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'تعيين كمشرف',
                          confirmBody:
                              'سيحصل ${rows[i].email} على صلاحيات المشرف الكاملة.',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .grantAdmin(rows[i].email),
                          successMessage: 'تم تعيين المشرف',
                        ),
                        onDelete: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'حذف الحساب نهائياً',
                          confirmBody: 'البريد: ${rows[i].email}\n'
                              'الهاتف: ${(rows[i].phone ?? '').isEmpty ? '—' : rows[i].phone}\n\n'
                              'سيُحذف الحساب مع بيانات إعداده، ولا يمكن التراجع. '
                              'لا يُحذف حساب له عمليات مالية؛ استخدم الحظر بدلاً منه.',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .deleteUser(rows[i].userId),
                          successMessage: 'تم حذف الحساب',
                        ),
                        onRevokeAdmin: () => _runAction(
                          row: rows[i],
                          confirmTitle: 'إزالة صلاحيات المشرف',
                          confirmBody:
                              'سيتم سحب صلاحيات المشرف من ${rows[i].email}.',
                          action: () => ref
                              .read(adminRepositoryProvider)
                              .revokeAdmin(rows[i].email),
                          successMessage: 'تمت إزالة الصلاحيات',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum AdminAction {
  trial,
  lifetime,
  block,
  pending,
  grantAdmin,
  revokeAdmin,
  delete,
}

class AdminUserCard extends StatelessWidget {
  const AdminUserCard({
    super.key,
    required this.row,
    required this.isSelf,
    required this.onActivateTrial,
    required this.onActivateLifetime,
    required this.onBlock,
    required this.onSetPending,
    required this.onGrantAdmin,
    required this.onRevokeAdmin,
    required this.onDelete,
  });

  final AdminUserRow row;
  final bool isSelf;
  final VoidCallback onActivateTrial;
  final VoidCallback onActivateLifetime;
  final VoidCallback onBlock;
  final VoidCallback onSetPending;
  final VoidCallback onGrantAdmin;
  final VoidCallback onRevokeAdmin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _statusStyle(row);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // An administrator's account is permanent: no menu, nothing to
              // change, block, delete or re-activate (the database refuses it too).
              if (row.isAdmin)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: FaIcon(
                    FontAwesomeIcons.lock,
                    key: ValueKey('admin-locked'),
                    size: 15,
                    color: AppColors.textLow,
                  ),
                )
              else
                PopupMenuButton<AdminAction>(
                  icon: const FaIcon(
                    FontAwesomeIcons.ellipsisVertical,
                    size: 16,
                    color: AppColors.textLow,
                  ),
                  onSelected: (a) {
                    switch (a) {
                      case AdminAction.trial:
                        onActivateTrial();
                      case AdminAction.lifetime:
                        onActivateLifetime();
                      case AdminAction.block:
                        onBlock();
                      case AdminAction.pending:
                        onSetPending();
                      case AdminAction.grantAdmin:
                        onGrantAdmin();
                      case AdminAction.revokeAdmin:
                        onRevokeAdmin();
                      case AdminAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: AdminAction.trial,
                      child: Text('تفعيل تجريبي 3 أيام'),
                    ),
                    const PopupMenuItem(
                      value: AdminAction.lifetime,
                      child: Text('تفعيل دائم'),
                    ),
                    const PopupMenuItem(
                      value: AdminAction.pending,
                      child: Text('إعادة لبانتظار التفعيل'),
                    ),
                    if (!row.isAdmin)
                      const PopupMenuItem(
                        value: AdminAction.grantAdmin,
                        child: Text(
                          'تعيين كمشرف',
                          style: TextStyle(color: AppColors.accent),
                        ),
                      ),
                    if (!isSelf && !row.isAdmin)
                      const PopupMenuItem(
                        value: AdminAction.delete,
                        child: Text(
                          'حذف الحساب',
                          style: TextStyle(color: AppColors.negative),
                        ),
                      ),
                    if (!isSelf && !row.isAdmin)
                      const PopupMenuItem(
                        value: AdminAction.block,
                        child: Text(
                          'حظر',
                          style: TextStyle(color: AppColors.negative),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if ((row.phone ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  size: 13,
                  color: AppColors.positive,
                ),
                const SizedBox(width: 6),
                Text(
                  row.phone!,
                  key: const ValueKey('user-phone'),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: AppColors.textMid,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(label: statusLabel, color: statusColor),
              if (row.isAdmin)
                const _Chip(label: 'مشرف', color: AppColors.accent),
              if (row.licenseType == 'lifetime')
                const _Chip(label: 'دائمة', color: AppColors.positive),
              if (row.trialEndsAt != null && row.status == 'trial')
                _Chip(
                  label: 'حتى ${dateOnly.format(row.trialEndsAt!.toLocal())}',
                  color: AppColors.textMid,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'انضم: ${dateOnly.format(row.createdAt.toLocal())}',
            style: const TextStyle(color: AppColors.textLow, fontSize: 11),
          ),
        ],
      ),
    );
  }

  (String, Color) _statusStyle(AdminUserRow r) {
    switch (r.status) {
      case 'active':
        return ('مفعّل', AppColors.positive);
      case 'trial':
        return r.isValid
            ? ('فترة تجريبية', AppColors.warning)
            : ('انتهت التجريبية', AppColors.negative);
      case 'expired':
        return ('انتهت التجريبية', AppColors.negative);
      case 'blocked':
        return ('محظور', AppColors.negative);
      case 'pending':
      default:
        return ('بانتظار التفعيل', AppColors.warning);
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
