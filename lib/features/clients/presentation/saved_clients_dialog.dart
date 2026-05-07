import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/clients_repository.dart';
import 'add_client_dialog.dart';
import 'clients_providers.dart';

class SavedEntitiesConfig {
  const SavedEntitiesConfig({
    this.listTitle = 'العملاء المحفوظون',
    this.addTitle = 'إضافة عميل جديد',
    this.editTitle = 'تعديل عميل',
    this.nameLabel = 'اسم العميل',
    this.companyFieldFirst = false,
    this.emptyMessage = 'ابدأ بإضافة جهة جديدة لبدء عمليات التحويل',
    this.addTooltip = 'إضافة عميل جديد',
  });

  final String listTitle;
  final String addTitle;
  final String editTitle;
  final String nameLabel;
  final bool companyFieldFirst;
  final String emptyMessage;
  final String addTooltip;

  static const beneficiaries = SavedEntitiesConfig(
    listTitle: 'المستفيدون',
    addTitle: 'إضافة جهة جديدة',
    editTitle: 'تعديل جهة',
    nameLabel: 'اسم الجهة',
    companyFieldFirst: true,
    addTooltip: 'إضافة جهة جديدة',
  );
}

class SavedClientsDialog extends ConsumerStatefulWidget {
  const SavedClientsDialog({
    super.key,
    this.config = const SavedEntitiesConfig(),
  });

  final SavedEntitiesConfig config;

  @override
  ConsumerState<SavedClientsDialog> createState() =>
      _SavedClientsDialogState();
}

class _SavedClientsDialogState extends ConsumerState<SavedClientsDialog> {
  Future<void> _openAddSheet() async {
    await showGlassDialog<void>(
      context: context,
      builder: (_) => AddClientDialog(
        onSaved: () => ref.invalidate(clientsListProvider),
        config: widget.config,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(clientsListProvider);
    final cfg = widget.config;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.30),
                          AppColors.positive.withValues(alpha: 0.20),
                        ],
                      ),
                      border:
                          Border.all(color: AppColors.glassBorderStrong),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.bookmark,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cfg.listTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: cfg.addTooltip,
                    onPressed: _openAddSheet,
                    icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                    color: AppColors.accent,
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              listAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 18,
                      ),
                      child: Center(
                        child: Text(
                          cfg.emptyMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textLow,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.of(context).pop(item),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.glassFill,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.glassBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const FaIcon(
                                    FontAwesomeIcons.user,
                                    size: 14,
                                    color: AppColors.accent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textHigh,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (item.company?.isEmpty ?? true)
                                              ? '—'
                                              : item.company!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const FaIcon(
                                      FontAwesomeIcons.trash,
                                      size: 14,
                                      color: AppColors.negative,
                                    ),
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(
                                              clientsRepositoryProvider,
                                            )
                                            .delete(item.id);
                                        ref.invalidate(
                                          clientsListProvider,
                                        );
                                      } catch (e, st) {
                                        AppLogger.error(
                                          'savedClients.delete',
                                          e,
                                          st,
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text(friendlyError(e)),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text(
                  '$e',
                  style: const TextStyle(color: AppColors.negative),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
