import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/domain/exchange_company.dart';
import '../data/clients_repository.dart';
import '../domain/client.dart';
import 'clients_providers.dart';

/// Which customer company would go with [party]: its own, when no other saved
/// party uses it and it is in the customers' list. Null when none would.
String? companyThatGoesWith(
  Client party,
  List<Client> all,
  Iterable<String> clientCompanyNames, {
  Map<String, ExchangeCompanyUsage>? usage,
}) {
  final company = (party.company ?? '').trim();
  if (company.isEmpty) return null;
  final shared = all.any(
    (c) => c.id != party.id && (c.company ?? '').trim() == company,
  );
  if (shared) return null;
  // a company that operations were recorded on is never removed
  if ((usage?[company]?.operations ?? 0) > 0) return null;
  return clientCompanyNames.contains(company) ? company : null;
}

/// Deletes a saved party after telling what will go. A name is never deleted
/// from one place and left in another: the company that came with the party
/// goes with it when nothing else uses it (the database does both in one
/// transaction), and a party that has operations cannot be deleted at all.
Future<void> confirmAndDeleteParty(
  BuildContext context,
  WidgetRef ref,
  Client party,
) async {
  // The lists may not have been read yet: wait for them, so the sentence the
  // user confirms is exactly what will happen.
  var all = const <Client>[];
  var clientCompanies = const <String>[];
  Map<String, ExchangeCompanyUsage>? usage;
  try {
    all = await ref.read(clientsListProvider.future);
    clientCompanies = [
      for (final c in await ref.read(exchangeCompaniesListProvider.future))
        if (c.isClient) c.name,
    ];
    usage = await ref.read(exchangeCompanyUsageProvider.future);
  } catch (_) {
    // the database decides anyway; only the explanation is less specific
  }
  if (!context.mounted) return;
  final goes = companyThatGoesWith(party, all, clientCompanies, usage: usage);
  final company = (party.company ?? '').trim();
  final label = party.name.trim().isEmpty ? (party.code ?? '') : party.name;

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
                'حذف الجهة؟',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHigh,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'ستُحذف الجهة «$label».',
                key: const ValueKey('delete-party-what'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMid, height: 1.5),
              ),
              if (goes != null)
                Text(
                  'وتُحذف معها شركة «$goes» لأن لا جهة أخرى تستعملها، فلا يبقى '
                  'لها أثر في أي مكان.',
                  key: const ValueKey('delete-party-company'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    height: 1.5,
                  ),
                )
              else if (company.isNotEmpty)
                Text(
                  (usage?[company]?.operations ?? 0) > 0
                      ? 'تبقى شركة «$company» لأن عليها عمليات مالية.'
                      : 'تبقى شركة «$company» لأن جهات أخرى تستعملها.',
                  key: const ValueKey('delete-party-company-kept'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 18),
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
                      key: const ValueKey('delete-party-confirm'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.negative,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('حذف'),
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
  if (confirmed != true) return;

  try {
    final removed = await ref.read(clientsRepositoryProvider).delete(party.id);
    ref.invalidate(clientsListProvider);
    // the companies list changed too (the one that came with the party)
    ref.invalidate(exchangeCompaniesListProvider);
    if (!context.mounted) return;
    showTopSnackBar(
      context,
      SnackBar(
        content: Text(
          removed == null ? 'تم حذف الجهة' : 'تم حذف الجهة وشركتها «$removed»',
        ),
      ),
    );
  } catch (e, st) {
    AppLogger.error('clients.delete', e, st);
    if (!context.mounted) return;
    showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
  }
}
