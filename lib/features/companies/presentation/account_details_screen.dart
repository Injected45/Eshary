import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../domain/company.dart';
import 'companies_providers.dart';

class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key, required this.company});
  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exchangesAsync = ref.watch(exchangesByCompanyProvider(company.id));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(company.name),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  icon: FontAwesomeIcons.building,
                  title: 'بيانات الحساب',
                ),
                const SizedBox(height: 12),
                _KvRow(label: 'اسم الحساب', value: company.name),
                const SizedBox(height: 8),
                _KvRow(label: 'إشاري الافتتاح', value: company.startRef),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  icon: FontAwesomeIcons.buildingColumns,
                  title: 'بيانات شركة الصرافة',
                ),
                const SizedBox(height: 12),
                exchangesAsync.when(
                  data: (exchanges) {
                    if (exchanges.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'لا توجد بيانات صرافة',
                          style: TextStyle(color: AppColors.textLow),
                        ),
                      );
                    }
                    final ex = exchanges.first;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _KvRow(label: 'شركة الصرافة', value: ex.name),
                        const SizedBox(height: 8),
                        _KvRow(label: 'الدولة', value: ex.country ?? '—'),
                        const SizedBox(height: 8),
                        _KvRow(
                          label: 'كود الحساب',
                          value: (ex.ourCode == null || ex.ourCode!.isEmpty)
                              ? '—'
                              : ex.ourCode!,
                        ),
                        const SizedBox(height: 8),
                        _KvRow(
                          label: 'الرصيد',
                          value: '${formatMoney(ex.balance)} USD',
                        ),
                      ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsetsDirectional.only(end: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.positive],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        FaIcon(icon, size: 14, color: AppColors.accent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: AppColors.textHigh,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textLow,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
