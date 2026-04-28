import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/cache.dart';
import '../../../shared/glass.dart';
import '../../archive/presentation/archive_providers.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../clients/presentation/clients_screen.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../companies/presentation/companies_screen.dart';
import '../../countries/presentation/countries_providers.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart';
import '../../profile/presentation/profile_details_screen.dart';
import '../../transfers/presentation/beneficiaries_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
        children: [
          _SettingsRow(
            icon: FontAwesomeIcons.user,
            title: 'الملف الشخصي',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.building,
            title: 'حساباتي',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CompaniesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.buildingColumns,
            title: 'شركات الصرافة',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ExchangeCompaniesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.users,
            title: 'العملاء',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClientsScreen()),
            ),
          ),
          const SizedBox(height: 24),
          _DestructiveSettingsRow(
            icon: FontAwesomeIcons.triangleExclamation,
            title: 'حذف بيانات الاختبار',
            subtitle: 'لإعادة الاختبار من الصفر — لا يحذف الحساب',
            onTap: () => _confirmAndWipe(context, ref),
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
    );
  }
}

Future<void> _confirmAndWipe(BuildContext context, WidgetRef ref) async {
  final confirmed = await showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'حذف كل البيانات؟',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHigh,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'ستُحذف جميع: الحسابات + شركات الصرافة + العملاء + المستفيدين + الدول + الحوالات + المشتريات. لا يمكن التراجع.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textLow, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
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
                    onPressed: () => Navigator.of(dialogContext).pop(true),
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

  if (confirmed != true) return;

  final uid = ref.read(currentUserIdProvider);
  if (uid == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('لم يتم تسجيل الدخول')),
    );
    return;
  }

  final client = ref.read(supabaseClientProvider);
  final errors = <String>[];
  const tables = [
    'transfers',
    'currency_buys',
    'beneficiaries',
    'exchange_companies',
    'countries',
    'clients',
    'companies',
  ];
  for (final table in tables) {
    try {
      await client.from(table).delete().eq('owner_id', uid);
    } catch (e) {
      errors.add('$table: $e');
    }
  }

  await ref.read(jsonCacheProvider).clear();

  ref.invalidate(companiesListProvider);
  ref.invalidate(allExchangesProvider);
  ref.invalidate(exchangeCompaniesListProvider);
  ref.invalidate(countriesListProvider);
  ref.invalidate(clientsListProvider);
  ref.invalidate(beneficiariesListProvider);
  ref.invalidate(dailyTransfersProvider);
  ref.invalidate(archivedTransfersProvider);
  ref.invalidate(dailyBuysProvider);
  ref.invalidate(pendingBuysProvider);
  ref.invalidate(archivedBuysProvider);
  ref.invalidate(archivedSoldTotalProvider);
  ref.invalidate(archivedBoughtTotalProvider);

  playAlert();

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        errors.isEmpty
            ? 'تم حذف جميع البيانات'
            : 'حُذفت جزئيًا. أخطاء: ${errors.length}',
      ),
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
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
                child: FaIcon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 14,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestructiveSettingsRow extends StatelessWidget {
  const _DestructiveSettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.negative.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.negative.withValues(alpha: 0.4),
                  ),
                ),
                child: FaIcon(icon, size: 16, color: AppColors.negative),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.negative,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 14,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
