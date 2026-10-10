import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../data/trial_admin_repository.dart';
import 'subscription_screen.dart' show formatTripoli;

final _changesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(trialAdminRepositoryProvider).phoneChanges();
});

/// Phone-change requests whose new number was already proven by a WhatsApp
/// code. Approving moves the account to the new number.
class PhoneChangesAdminScreen extends ConsumerWidget {
  const PhoneChangesAdminScreen({super.key});

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool approve,
  ) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('سبب الرفض'),
            content: TextField(controller: c, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('رفض'),
              ),
            ],
          ),
        ),
      );
      if (note == null || note.isEmpty) return;
    }
    try {
      await ref
          .read(trialAdminRepositoryProvider)
          .decidePhoneChange(id, approve, note: note);
      ref.invalidate(_changesProvider);
      if (context.mounted) {
        showTopSnackBar(context, const SnackBar(content: Text('تم التنفيذ')));
      }
    } catch (e, st) {
      AppLogger.error('admin.phoneChange', e, st);
      if (context.mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_changesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: const Text('طلبات تغيير الرقم')),
      body: SafeArea(
        child: async.when(
          skipLoadingOnReload: true,
          skipError: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(friendlyError(e))),
          data: (rows) => rows.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد طلبات',
                    style: TextStyle(color: AppColors.textLow),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final waiting = r['status'] == 'pending_admin';
                    return GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['business_name']} — ${r['manager_name']}',
                            style: const TextStyle(
                              color: AppColors.textHigh,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${r['old_phone']}  ←  ${r['new_phone']}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(color: AppColors.textMid),
                          ),
                          Text(
                            '${_label(r['status'] as String)} — ${formatTripoli(DateTime.parse(r['created_at'] as String))}',
                            style: const TextStyle(
                              color: AppColors.textLow,
                              fontSize: 12,
                            ),
                          ),
                          if (waiting)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton(
                                    key: const ValueKey('change-approve'),
                                    onPressed: () => _decide(
                                      context,
                                      ref,
                                      r['id'] as String,
                                      true,
                                    ),
                                    child: const Text('اعتماد'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _decide(
                                      context,
                                      ref,
                                      r['id'] as String,
                                      false,
                                    ),
                                    child: const Text('رفض'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _label(String s) => switch (s) {
        'pending_verify' => 'بانتظار تأكيد الرقم الجديد',
        'pending_admin' => 'بانتظار الإدارة',
        'approved' => 'معتمد',
        'rejected' => 'مرفوض',
        _ => 'ملغى',
      };
}
