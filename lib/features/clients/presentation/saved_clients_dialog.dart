import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../data/clients_repository.dart';
import '../domain/client.dart';
import 'add_client_dialog.dart';
import 'delete_party.dart';
import 'clients_providers.dart';
import '../../../shared/top_message.dart';

class SavedEntitiesConfig {
  const SavedEntitiesConfig({
    this.listTitle = 'العملاء المحفوظون',
    this.addTitle = 'إضافة عميل جديد',
    this.editTitle = 'تعديل عميل',
    this.nameLabel = 'اسم العميل',
    this.emptyMessage = 'ابدأ بإضافة جهة جديدة لبدء عمليات التحويل',
    this.addTooltip = 'إضافة عميل جديد',
  });

  final String listTitle;
  final String addTitle;
  final String editTitle;
  final String nameLabel;

  final String emptyMessage;
  final String addTooltip;

  static const beneficiaries = SavedEntitiesConfig(
    listTitle: 'المستفيدون',
    addTitle: 'إضافة جهة جديدة',
    editTitle: 'تعديل جهة',
    nameLabel: 'اسم الجهة',
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
  ConsumerState<SavedClientsDialog> createState() => _SavedClientsDialogState();
}

class _SavedClientsDialogState extends ConsumerState<SavedClientsDialog> {
  /// What the user typed to find a party: a code first, or a name / company.
  String _query = '';
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
    final isEmployee = ref.watch(isEmployeeProvider);

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
                      border: Border.all(color: AppColors.glassBorderStrong),
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
                  if (!isEmployee)
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
              TextField(
                key: const ValueKey('party-search'),
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث بالكود أو الاسم أو الشركة',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              listAsync.when(
                skipLoadingOnReload: true,
                skipError: true,
                data: (all) {
                  final items = filterParties(all, _query);
                  if (all.isNotEmpty && items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          'لا توجد جهة بهذا الكود أو الاسم',
                          style: TextStyle(
                            color: AppColors.textLow,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
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
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                                          partySubtitle(item),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isEmployee)
                                    IconButton(
                                      key: ValueKey('party-edit-${item.id}'),
                                      tooltip: 'تعديل الجهة وحروف الإشاري',
                                      icon: const FaIcon(
                                        FontAwesomeIcons.penToSquare,
                                        size: 14,
                                        color: AppColors.accent,
                                      ),
                                      onPressed: () => showGlassDialog<void>(
                                        context: context,
                                        builder: (_) => AddClientDialog(
                                          existing: item,
                                          config: widget.config,
                                          onSaved: () => ref
                                              .invalidate(clientsListProvider),
                                        ),
                                      ),
                                    ),
                                  if (!isEmployee)
                                    IconButton(
                                      icon: const FaIcon(
                                        FontAwesomeIcons.trash,
                                        size: 14,
                                        color: AppColors.negative,
                                      ),
                                      onPressed: () => confirmAndDeleteParty(
                                          context, ref, item),
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

/// The saved parties matching what was typed. A code is matched without case,
/// spaces or digit shape (٥٥٢١ = 5521); a name or a company by what it contains.
List<Client> filterParties(List<Client> all, String query) {
  final key = partyKey(query);
  if (key.isEmpty) return all;
  final text = query.trim().toLowerCase();
  return [
    for (final c in all)
      if (partyKey(c.code).contains(key) ||
          partyKey(c.company).contains(key) ||
          c.name.toLowerCase().contains(text))
        c,
  ];
}

/// "بهار روز · كود 5521": the company and the code a merchant is known by.
String partySubtitle(Client c) {
  // whatever the merchant gave, in one line: company · code · reference letters
  final company = (c.company ?? '').trim();
  final code = (c.code ?? '').trim();
  final letters = (c.refPrefix ?? '').trim();
  final parts = [
    if (company.isNotEmpty) company,
    if (code.isNotEmpty) 'كود $code',
    if (letters.isNotEmpty) 'إشاري $letters',
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}
