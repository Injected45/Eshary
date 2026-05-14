import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import 'archive_filters.dart';
import 'diff_details_screen.dart';
import 'employees_operations_screen.dart';
import 'history_details_screen.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;

  bool get _rangeReady =>
      _from != null && _to != null && !_from!.isAfter(_to!);

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: _to ?? DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: _from ?? DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _to = picked);
  }

  @override
  Widget build(BuildContext context) {
    final archivedBuys =
        ref.watch(archivedBuysProvider).value ?? const <CurrencyBuy>[];
    final archivedTransfers =
        ref.watch(archivedTransfersProvider).value ?? const <Transfer>[];

    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    final filteredBuys = archivedBuys
        .where((b) => inDateRange(b.archivedAt, r.start, r.end))
        .toList();
    final filteredTransfers = archivedTransfers
        .where((t) => inDateRange(t.archivedAt, r.start, r.end))
        .toList();

    final incomeTotal =
        filteredBuys.fold<double>(0, (s, b) => s + b.usdAmount);
    final outgoingTotal =
        filteredTransfers.fold<double>(0, (s, t) => s + t.amount);
    final diff = incomeTotal - outgoingTotal;

    final showRangeSuffix =
        _mode == DateFilterMode.range && _rangeReady;
    final titleSuffix = showRangeSuffix
        ? ' — ${archiveFilterDateFmt.format(_from!)} → ${archiveFilterDateFmt.format(_to!)}'
        : '';

    final detailsRange = DateTimeRange(start: r.start, end: r.end);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        DateFilterBar(
          mode: _mode,
          from: _from,
          to: _to,
          onModeChanged: (m) => setState(() {
            _mode = m;
            if (m == DateFilterMode.today) {
              _from = null;
              _to = null;
            }
          }),
          onPickFrom: _pickFrom,
          onPickTo: _pickTo,
          showInvalidHint:
              _mode == DateFilterMode.range && !_rangeReady,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                income: true,
                total: incomeTotal,
                archivedCount: filteredBuys.length,
                titleSuffix: titleSuffix,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                income: false,
                total: outgoingTotal,
                archivedCount: filteredTransfers.length,
                titleSuffix: titleSuffix,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DiffNavTile(
          diff: diff,
          hasAny: filteredBuys.isNotEmpty || filteredTransfers.isNotEmpty,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DiffDetailsScreen(initialRange: detailsRange),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _DetailNavTile(
          income: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HistoryDetailsScreen(
                kind: HistoryKind.income,
                initialRange: detailsRange,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DetailNavTile(
          income: false,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HistoryDetailsScreen(
                kind: HistoryKind.outgoing,
                initialRange: detailsRange,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _EmployeesNavTile(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const EmployeesOperationsScreen(),
            ),
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
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.income,
    required this.total,
    required this.archivedCount,
    this.titleSuffix = '',
  });
  final bool income;
  final double total;
  final int archivedCount;
  final String titleSuffix;

  @override
  Widget build(BuildContext context) {
    final tint = income ? AppColors.positive : AppColors.negative;
    final hasArchive = archivedCount > 0;
    final baseTitle = income ? 'إجمالي الدخول' : 'إجمالي الخروج';
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tint, width: 1.5),
              color: tint.withValues(alpha: 0.08),
            ),
            child: FaIcon(
              income
                  ? FontAwesomeIcons.arrowTrendDown
                  : FontAwesomeIcons.arrowTrendUp,
              size: 22,
              color: tint,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$baseTitle$titleSuffix',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMid,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          if (hasArchive)
            Text(
              '\$${formatMoney(total)}',
              style: TextStyle(
                color: tint,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            )
          else
            const Text(
              'لا توجد إقفالات بعد',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textLow,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiffNavTile extends StatelessWidget {
  const _DiffNavTile({
    required this.diff,
    required this.hasAny,
    required this.onTap,
  });

  final double diff;
  final bool hasAny;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPositive = diff >= 0;
    final tint = !hasAny
        ? AppColors.textLow
        : (isPositive ? AppColors.positive : AppColors.negative);
    final sign = !hasAny ? '' : (isPositive ? '+' : '-');
    final magnitude = formatMoney(diff.abs());
    final caption = !hasAny
        ? 'لا توجد إقفالات بعد'
        : (diff == 0
            ? 'متوازن'
            : (isPositive
                ? 'الدخول أكثر من الخروج'
                : 'الخروج أكثر من الدخول'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFE0B341).withValues(alpha: 0.30),
                      const Color(0xFFCB8C13).withValues(alpha: 0.18),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFFE0B341).withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
                child: const FaIcon(
                  FontAwesomeIcons.scaleBalanced,
                  size: 24,
                  color: Color(0xFFE0B341),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'فرق الحركة',
                      style: TextStyle(
                        color: AppColors.textMid,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasAny ? '$sign\$$magnitude' : '—',
                      style: TextStyle(
                        color: tint,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: tint,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          caption,
                          style: const TextStyle(
                            color: AppColors.textLow,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 12,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeesNavTile extends StatelessWidget {
  const _EmployeesNavTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const tint = Color(0xFF7C8CF7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tint, width: 1.5),
                  color: tint.withValues(alpha: 0.10),
                ),
                child: const FaIcon(
                  FontAwesomeIcons.userGroup,
                  size: 14,
                  color: tint,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'عرض تفاصيل عمليات الموظفين',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 12,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailNavTile extends StatelessWidget {
  const _DetailNavTile({required this.income, required this.onTap});
  final bool income;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = income ? AppColors.positive : AppColors.negative;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tint, width: 1.5),
                  color: tint.withValues(alpha: 0.08),
                ),
                child: FaIcon(
                  income
                      ? FontAwesomeIcons.arrowTrendDown
                      : FontAwesomeIcons.arrowTrendUp,
                  size: 14,
                  color: tint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  income
                      ? 'عرض تفاصيل الدخول'
                      : 'عرض تفاصيل الخروج',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.glassFillStrong,
                  border: Border.all(color: AppColors.glassBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const FaIcon(
                  FontAwesomeIcons.filePdf,
                  size: 14,
                  color: AppColors.textMid,
                ),
              ),
              const SizedBox(width: 6),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 12,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
