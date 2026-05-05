import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../exchange_companies/domain/exchange_company.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../domain/company.dart';
import '../domain/exchange.dart';
import 'companies_providers.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final Set<String> _expanded = <String>{};

  static const _accentCycle = <Color>[
    AppColors.accent,
    AppColors.warning,
    AppColors.positive,
    AppColors.negative,
  ];

  static const _flagByCountry = <String, String>{
    'تركيا': '🇹🇷',
    'الامارات': '🇦🇪',
    'الإمارات': '🇦🇪',
    'مصر': '🇪🇬',
    'ليبيا': '🇱🇾',
  };

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(companiesListProvider);
    final exchangesAsync = ref.watch(allExchangesProvider);
    final exchangeCompaniesAsync =
        ref.watch(exchangeCompaniesListProvider);
    final archivedBuys = ref.watch(archivedBuysProvider).value ?? const [];
    final archivedTransfers =
        ref.watch(archivedTransfersProvider).value ?? const [];
    final hasArchive =
        archivedBuys.isNotEmpty || archivedTransfers.isNotEmpty;

    if (!hasArchive) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding:
              const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
          child: Center(
            child: GlassCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 28,
              ),
              child: const Text(
                'لا توجد إقفالات بعد',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textLow,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (companiesAsync.isLoading ||
        exchangesAsync.isLoading ||
        exchangeCompaniesAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: kToolbarHeight + 24),
        child: LinearProgressIndicator(),
      );
    }
    if (companiesAsync.hasError) return _errorBody(companiesAsync.error);
    if (exchangesAsync.hasError) return _errorBody(exchangesAsync.error);
    if (exchangeCompaniesAsync.hasError) {
      return _errorBody(exchangeCompaniesAsync.error);
    }

    final companies = companiesAsync.value ?? const <Company>[];
    final exchanges = exchangesAsync.value ?? const <Exchange>[];
    final exchangeCompanies =
        exchangeCompaniesAsync.value ?? const <ExchangeCompany>[];

    final companyNameById = <String, String>{
      for (final c in companies) c.id: c.name,
    };

    // Group exchanges by exchange-company name (Exchange.name == ExchangeCompany.name).
    final exchangesByEcName = <String, List<Exchange>>{};
    for (final ex in exchanges) {
      exchangesByEcName.putIfAbsent(ex.name, () => <Exchange>[]).add(ex);
    }

    // Cards: one per ExchangeCompany that has at least one matching exchange.
    final ecsWithAccounts = exchangeCompanies
        .where((ec) => (exchangesByEcName[ec.name]?.isNotEmpty ?? false))
        .toList();

    final totalBalance =
        exchanges.fold<double>(0, (s, e) => s + e.balance);
    final accountsCount = exchanges.length;
    final ecCount = ecsWithAccounts.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('قريبًا')),
            ),
            icon: const FaIcon(FontAwesomeIcons.filter, size: 12),
            label: const Text('تصفية'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textHigh,
              side: BorderSide(color: AppColors.glassBorder),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _TotalBalanceCard(
          total: totalBalance,
          accountsCount: accountsCount,
          companiesCount: ecCount,
        ),
        const SizedBox(height: 16),
        if (ecsWithAccounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'لا توجد حسابات حتى الآن',
                style: TextStyle(color: AppColors.textLow),
              ),
            ),
          )
        else
          for (var i = 0; i < ecsWithAccounts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExchangeCompanyCard(
                exchangeCompany: ecsWithAccounts[i],
                exchanges:
                    exchangesByEcName[ecsWithAccounts[i].name] ?? const [],
                companyNameById: companyNameById,
                accent: _accentCycle[i % _accentCycle.length],
                flag: _flagByCountry[ecsWithAccounts[i].country ?? ''],
                expanded: _expanded.contains(ecsWithAccounts[i].id),
                onToggle: () => setState(() {
                  final id = ecsWithAccounts[i].id;
                  if (_expanded.contains(id)) {
                    _expanded.remove(id);
                  } else {
                    _expanded.add(id);
                  }
                }),
              ),
            ),
      ],
    );
  }

  Widget _errorBody(Object? e) => Padding(
        padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 40, 16, 16),
        child: Center(
          child: Text(
            '$e',
            style: const TextStyle(color: AppColors.negative),
          ),
        ),
      );
}

class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({
    required this.total,
    required this.accountsCount,
    required this.companiesCount,
  });

  final double total;
  final int accountsCount;
  final int companiesCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إجمالي الأرصدة',
                  style: TextStyle(
                    color: AppColors.textMid,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${formatMoney(total)}',
                  style: const TextStyle(
                    color: AppColors.positive,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'إجمالي $accountsCount حسابات في $companiesCount شركات صرافة',
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.positive,
                width: 3,
              ),
              color: AppColors.positive.withValues(alpha: 0.10),
            ),
            child: const FaIcon(
              FontAwesomeIcons.arrowUp,
              size: 22,
              color: AppColors.positive,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExchangeCompanyCard extends StatelessWidget {
  const _ExchangeCompanyCard({
    required this.exchangeCompany,
    required this.exchanges,
    required this.companyNameById,
    required this.accent,
    required this.flag,
    required this.expanded,
    required this.onToggle,
  });

  final ExchangeCompany exchangeCompany;
  final List<Exchange> exchanges;
  final Map<String, String> companyNameById;
  final Color accent;
  final String? flag;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final total = exchanges.fold<double>(0, (s, e) => s + e.balance);
    final country = exchangeCompany.country;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: 0.18),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: FaIcon(
                    FontAwesomeIcons.building,
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exchangeCompany.name,
                      style: const TextStyle(
                        color: AppColors.textHigh,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (country != null && country.isNotEmpty)
                          Text(
                            'دولة $country',
                            style: const TextStyle(
                              color: AppColors.textMid,
                              fontSize: 11,
                            ),
                          ),
                        if (flag != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            flag!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'إجمالي الرصيد',
                        style: TextStyle(
                          color: AppColors.textLow,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${formatMoney(total)}',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FaIcon(
                  expanded
                      ? FontAwesomeIcons.chevronUp
                      : FontAwesomeIcons.chevronDown,
                  size: 14,
                  color: AppColors.textLow,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ExchangesTable(
                      exchanges: exchanges,
                      companyNameById: companyNameById,
                      accent: accent,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ExchangesTable extends StatelessWidget {
  const _ExchangesTable({
    required this.exchanges,
    required this.companyNameById,
    required this.accent,
  });

  final List<Exchange> exchanges;
  final Map<String, String> companyNameById;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    'اسم الحساب',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'رقم الحساب',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'الرصيد',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final ex in exchanges) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.glassBorder,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      companyNameById[ex.companyId] ?? '—',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textHigh,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      (ex.ourCode == null || ex.ourCode!.isEmpty)
                          ? '—'
                          : ex.ourCode!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textHigh,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '\$${formatMoney(ex.balance)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
