import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/companies_repository.dart';
import '../domain/company.dart';
import 'account_details_screen.dart';
import 'add_company_dialog.dart';
import 'companies_providers.dart';

class CompaniesScreen extends ConsumerWidget {
  const CompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(companiesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('حساباتي'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
            tooltip: 'إضافة حساب جديد',
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddCompanyDialog(
                  onSaved: () {
                    ref.invalidate(companiesListProvider);
                    ref.invalidate(allExchangesProvider);
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: asyncList.when(
        data: (companies) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (companies.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'لا توجد شركات حتى الآن',
                    style: TextStyle(color: AppColors.textLow),
                  ),
                ),
              ),
            for (final c in companies)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CompanyTile(company: c),
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

class _CompanyTile extends ConsumerWidget {
  const _CompanyTile({required this.company});
  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exchangesAsync = ref.watch(exchangesByCompanyProvider(company.id));
    final exchangeName =
        exchangesAsync.value?.isNotEmpty == true
            ? exchangesAsync.value!.first.name
            : '—';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetails(context),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const FaIcon(FontAwesomeIcons.building,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exchangeName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textLow,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'عرض التفاصيل',
                icon: const FaIcon(FontAwesomeIcons.eye, size: 14),
                onPressed: () => _openDetails(context),
              ),
              IconButton(
                tooltip: 'تعديل',
                icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
                onPressed: () {
                  showGlassDialog<void>(
                    context: context,
                    builder: (_) => AddCompanyDialog(
                      existing: company,
                      onSaved: () {
                        ref.invalidate(companiesListProvider);
                        ref.invalidate(allExchangesProvider);
                        ref.invalidate(
                            exchangesByCompanyProvider(company.id));
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
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountDetailsScreen(company: company),
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
                  'حذف الشركة؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سيُحذف كافة الحسابات والصرافات المرتبطة بها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textLow, fontSize: 13),
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
        await ref.read(companiesRepositoryProvider).delete(company.id);
        ref.invalidate(companiesListProvider);
        ref.invalidate(allExchangesProvider);
      } catch (e, st) {
        AppLogger.error('companies.delete', e, st);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}
