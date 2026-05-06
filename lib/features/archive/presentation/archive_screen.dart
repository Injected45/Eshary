import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import 'history_details_screen.dart';

enum _DateFilterMode { today, range }

final DateFormat _filterDateFmt = DateFormat('yyyy/MM/dd');

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  _DateFilterMode _mode = _DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;

  bool get _rangeReady =>
      _from != null && _to != null && !_from!.isAfter(_to!);

  bool _inRange(DateTime? dt, DateTime start, DateTime end) =>
      dt != null && !dt.isBefore(start) && !dt.isAfter(end);

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

    final now = DateTime.now();
    DateTime start;
    DateTime end;
    if (_mode == _DateFilterMode.today || !_rangeReady) {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else {
      start = DateTime(_from!.year, _from!.month, _from!.day);
      end = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
    }

    final filteredBuys =
        archivedBuys.where((b) => _inRange(b.archivedAt, start, end)).toList();
    final filteredTransfers = archivedTransfers
        .where((t) => _inRange(t.archivedAt, start, end))
        .toList();

    final incomeTotal =
        filteredBuys.fold<double>(0, (s, b) => s + b.usdAmount);
    final outgoingTotal =
        filteredTransfers.fold<double>(0, (s, t) => s + t.amount);

    final showRangeSuffix = _mode == _DateFilterMode.range && _rangeReady;
    final titleSuffix = showRangeSuffix
        ? ' — ${_filterDateFmt.format(_from!)} → ${_filterDateFmt.format(_to!)}'
        : '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        _DateFilterBar(
          mode: _mode,
          from: _from,
          to: _to,
          onModeChanged: (m) => setState(() {
            _mode = m;
            if (m == _DateFilterMode.today) {
              _from = null;
              _to = null;
            }
          }),
          onPickFrom: _pickFrom,
          onPickTo: _pickTo,
          showInvalidHint:
              _mode == _DateFilterMode.range && !_rangeReady,
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
        _DetailNavTile(
          income: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const HistoryDetailsScreen(kind: HistoryKind.income),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DetailNavTile(
          income: false,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const HistoryDetailsScreen(kind: HistoryKind.outgoing),
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

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.mode,
    required this.from,
    required this.to,
    required this.onModeChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.showInvalidHint,
  });

  final _DateFilterMode mode;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<_DateFilterMode> onModeChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final bool showInvalidHint;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: 'اليوم',
                  selected: mode == _DateFilterMode.today,
                  onTap: () => onModeChanged(_DateFilterMode.today),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeChip(
                  label: 'من — إلى',
                  selected: mode == _DateFilterMode.range,
                  onTap: () => onModeChanged(_DateFilterMode.range),
                ),
              ),
            ],
          ),
          if (mode == _DateFilterMode.range) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'من',
                    value: from,
                    onTap: onPickFrom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateField(
                    label: 'إلى',
                    value: to,
                    onTap: onPickTo,
                  ),
                ),
              ],
            ),
            if (showInvalidHint) ...[
              const SizedBox(height: 6),
              const Text(
                'حدّد تاريخ البداية والنهاية',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.glassFill,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.glassBorder,
              width: selected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.accent : AppColors.textMid,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final display =
        value == null ? '—' : _filterDateFmt.format(value!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            border: Border.all(color: AppColors.glassBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.calendar,
                size: 13,
                color: AppColors.textLow,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textLow,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  display,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
