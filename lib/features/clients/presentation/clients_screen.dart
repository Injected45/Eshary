import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/clients_repository.dart';
import '../domain/client.dart';
import 'add_client_dialog.dart';
import 'clients_providers.dart';

class ClientsScreen extends ConsumerWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(clientsListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('العملاء'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
            tooltip: 'إضافة عميل جديد',
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddClientDialog(
                  onSaved: () => ref.invalidate(clientsListProvider),
                ),
              );
            },
          ),
        ],
      ),
      body: asyncList.when(
        data: (clients) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (clients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'لا يوجد عملاء حتى الآن',
                    style: TextStyle(color: AppColors.textLow),
                  ),
                ),
              ),
            for (final c in clients)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ClientTile(client: c),
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

class _ClientTile extends ConsumerWidget {
  const _ClientTile({required this.client});
  final Client client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.user,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  client.company ?? '—',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLow,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تعديل',
            icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddClientDialog(
                  existing: client,
                  onSaved: () => ref.invalidate(clientsListProvider),
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
                  'حذف العميل؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
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
        await ref.read(clientsRepositoryProvider).delete(client.id);
        ref.invalidate(clientsListProvider);
      } catch (e, st) {
        AppLogger.error('clients.delete', e, st);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}
