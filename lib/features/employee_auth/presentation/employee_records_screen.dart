import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/transaction_details.dart';
import '../../archive/presentation/diff_details_screen.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';

/// History screen shown to employees so they can review every transaction
/// they have ever authored — both today's still-daily rows AND archived
/// rows the admin has closed. Without this view the admin's daily close
/// would make the employee lose access to their own jurd (running totals).
class EmployeeRecordsScreen extends ConsumerStatefulWidget {
  const EmployeeRecordsScreen({super.key});

  @override
  ConsumerState<EmployeeRecordsScreen> createState() =>
      _EmployeeRecordsScreenState();
}

enum _OpenSection { outgoing, incoming }

class _EmployeeRecordsScreenState
    extends ConsumerState<EmployeeRecordsScreen> {
  // Mutually exclusive: only one section is open at a time. `null` means
  // both are closed.
  _OpenSection? _open = _OpenSection.outgoing;

  void _toggle(_OpenSection section) {
    setState(() {
      _open = _open == section ? null : section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dailyT = ref.watch(dailyTransfersProvider).value ?? const <Transfer>[];
    final archT =
        ref.watch(archivedTransfersProvider).value ?? const <Transfer>[];
    final dailyB =
        ref.watch(dailyBuysProvider).value ?? const <CurrencyBuy>[];
    final archB =
        ref.watch(archivedBuysProvider).value ?? const <CurrencyBuy>[];

    // Newest first. Daily rows are typically newest than archived ones,
    // but sort defensively so callers can rely on the order.
    final allOutgoing = [...dailyT, ...archT]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final allIncoming = [...dailyB, ...archB]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final outgoingTotal = allOutgoing.fold<double>(0, (s, t) => s + t.amount);
    final incomingTotal =
        allIncoming.fold<double>(0, (s, b) => s + b.usdAmount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        _SummaryRow(
          outgoingCount: allOutgoing.length,
          outgoingTotal: outgoingTotal,
          incomingCount: allIncoming.length,
          incomingTotal: incomingTotal,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DiffDetailsScreen(
                    includeDaily: true,
                    title: 'فرق حركة عملياتي',
                  ),
                ),
              );
            },
            icon: const FaIcon(FontAwesomeIcons.chartLine, size: 14),
            label: const Text('فرق الحركة (مع الرسم البياني والتفاصيل)'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'حوالات الخروج',
          count: allOutgoing.length,
          icon: FontAwesomeIcons.paperPlane,
          accent: AppColors.negative,
          expanded: _open == _OpenSection.outgoing,
          onToggle: () => _toggle(_OpenSection.outgoing),
          child: _TransferList(rows: allOutgoing),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'حوالات الدخول',
          count: allIncoming.length,
          icon: FontAwesomeIcons.moneyBillTransfer,
          accent: AppColors.positive,
          expanded: _open == _OpenSection.incoming,
          onToggle: () => _toggle(_OpenSection.incoming),
          child: _CurrencyBuyList(rows: allIncoming),
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
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.outgoingCount,
    required this.outgoingTotal,
    required this.incomingCount,
    required this.incomingTotal,
  });

  final int outgoingCount;
  final double outgoingTotal;
  final int incomingCount;
  final double incomingTotal;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'خروج',
            count: outgoingCount,
            total: outgoingTotal,
            icon: FontAwesomeIcons.paperPlane,
            accent: AppColors.negative,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            label: 'دخول',
            count: incomingCount,
            total: incomingTotal,
            icon: FontAwesomeIcons.moneyBillTransfer,
            accent: AppColors.positive,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.count,
    required this.total,
    required this.icon,
    required this.accent,
  });

  final String label;
  final int count;
  final double total;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.15),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: FaIcon(icon, size: 12, color: accent),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHigh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$count عملية',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textLow,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '\$${formatMoney(total)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.icon,
    required this.accent,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color accent;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
                FaIcon(icon, size: 14, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHigh,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FaIcon(
                  expanded
                      ? FontAwesomeIcons.chevronUp
                      : FontAwesomeIcons.chevronDown,
                  size: 12,
                  color: AppColors.textLow,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TransferList extends ConsumerWidget {
  const _TransferList({required this.rows});
  final List<Transfer> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            'لا توجد حوالات خروج بعد',
            style: TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
        ),
      );
    }
    final exchanges = ref.watch(allExchangesProvider).value ?? const <Exchange>[];
    final exchangeById = <String, Exchange>{
      for (final e in exchanges) e.id: e,
    };
    final exchangeNameById = <String, String>{
      for (final e in exchanges) e.id: e.name,
    };
    final fmt = DateFormat('yyyy-MM-dd  hh:mm a');
    final companies = ref.watch(companiesListProvider).value ?? const <Company>[];
    final companyNameById = <String, String>{
      for (final c in companies) c.id: c.name,
    };
    return Column(
      children: [
        for (final t in rows)
          _RecordTile(
            top: t.beneficiaryName.isEmpty ? '—' : t.beneficiaryName,
            middle: exchangeNameById[t.exchangeId] ?? '—',
            bottom: '${t.reference} • ${fmt.format(t.createdAt.toLocal())}',
            amount: t.amount,
            amountColor: AppColors.negative,
            archived: t.status == TransferStatus.archived,
            onTap: () => showTransferDetails(
              context,
              transfer: t,
              companyName: companyNameById[t.companyId],
              exchangeName: exchangeNameById[t.exchangeId],
              exchangeCode: exchangeById[t.exchangeId]?.ourCode,
            ),
          ),
      ],
    );
  }
}

class _CurrencyBuyList extends ConsumerWidget {
  const _CurrencyBuyList({required this.rows});
  final List<CurrencyBuy> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            'لا توجد حوالات دخول بعد',
            style: TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
        ),
      );
    }
    final clients = ref.watch(clientsListProvider).value ?? const [];
    final companies = ref.watch(companiesListProvider).value ?? const <Company>[];
    final clientById = {for (final c in clients) c.id: c};
    final companyNameById = <String, String>{
      for (final c in companies) c.id: c.name,
    };
    final fmt = DateFormat('yyyy-MM-dd  hh:mm a');
    return Column(
      children: [
        for (final b in rows)
          _RecordTile(
            top: clientById[b.clientId]?.name ??
                b.clientFromAccount ??
                '—',
            middle: companyNameById[b.myCompanyId] ?? '—',
            bottom:
                '${b.reference.isEmpty ? '—' : b.reference} • ${fmt.format(b.createdAt.toLocal())}',
            amount: b.usdAmount,
            amountColor: AppColors.positive,
            archived: b.status == CurrencyBuyStatus.archived,
            pending: b.status == CurrencyBuyStatus.pending,
            onTap: () => showCurrencyBuyDetails(context, ref, buy: b),
          ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.amount,
    required this.amountColor,
    required this.archived,
    this.pending = false,
    this.onTap,
  });

  final String top;
  final String middle;
  final String bottom;
  final double amount;
  final Color amountColor;
  final bool archived;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: _buildContent(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: body,
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        top,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHigh,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (archived)
                      _StatusPill(
                        label: 'مرحّلة',
                        color: AppColors.textLow,
                      ),
                    if (pending)
                      _StatusPill(
                        label: 'قيد التنفيذ',
                        color: AppColors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  middle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMid,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  bottom,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textLow,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${formatMoney(amount)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: amountColor,
            ),
          ),
        ],
      );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

