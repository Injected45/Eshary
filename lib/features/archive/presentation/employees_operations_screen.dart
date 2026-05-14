import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/creator_filter.dart' show kCreatorAdmin;
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../sub_users/domain/sub_user.dart';
import '../../sub_users/presentation/sub_users_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import 'archive_filters.dart';
import 'diff_details_screen.dart';

/// Admin-only browse screen that lists every author (admin + active
/// employees) who has at least one archived operation, with per-author
/// counts/totals. Tapping a row opens the existing DiffDetailsScreen
/// scoped to that author's data — same chart, same totals, same PDF.
class EmployeesOperationsScreen extends ConsumerStatefulWidget {
  const EmployeesOperationsScreen({super.key});

  @override
  ConsumerState<EmployeesOperationsScreen> createState() =>
      _EmployeesOperationsScreenState();
}

class _EmployeesOperationsScreenState
    extends ConsumerState<EmployeesOperationsScreen> {
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
    if (picked != null) {
      setState(() => _from = picked);
      if (!mounted) return;
      await _pickTo();
    }
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
    final archBuys =
        ref.watch(archivedBuysProvider).value ?? const <CurrencyBuy>[];
    final archTransfers =
        ref.watch(archivedTransfersProvider).value ?? const <Transfer>[];
    final employees =
        ref.watch(subUsersListProvider).value ?? const <SubUser>[];

    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);

    final visibleBuys = archBuys
        .where((b) => inDateRange(b.archivedAt, r.start, r.end))
        .toList();
    final visibleTransfers = archTransfers
        .where((t) => inDateRange(t.archivedAt, r.start, r.end))
        .toList();

    // Aggregate per-author. Key: null = admin, otherwise sub_user.id.
    final incomeByCreator = <String?, double>{};
    final outgoingByCreator = <String?, double>{};
    final countByCreator = <String?, int>{};

    for (final b in visibleBuys) {
      incomeByCreator[b.createdByEmployeeId] =
          (incomeByCreator[b.createdByEmployeeId] ?? 0) + b.usdAmount;
      countByCreator[b.createdByEmployeeId] =
          (countByCreator[b.createdByEmployeeId] ?? 0) + 1;
    }
    for (final t in visibleTransfers) {
      outgoingByCreator[t.createdByEmployeeId] =
          (outgoingByCreator[t.createdByEmployeeId] ?? 0) + t.amount;
      countByCreator[t.createdByEmployeeId] =
          (countByCreator[t.createdByEmployeeId] ?? 0) + 1;
    }

    // Stable ordering: admin first, then employees sorted by total
    // activity desc so the most active employees are easiest to find.
    final keys = countByCreator.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return countByCreator[b]!.compareTo(countByCreator[a]!);
      });

    final detailsRange = DateTimeRange(start: r.start, end: r.end);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('عمليات الموظفين'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
          const SizedBox(height: 14),
          if (keys.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'لا توجد عمليات في الفترة المحددة',
                  style: TextStyle(color: AppColors.textLow, fontSize: 13),
                ),
              ),
            )
          else
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CreatorRow(
                  isAdmin: k == null,
                  label: k == null
                      ? 'أنا (المدير)'
                      : employees
                              .where((e) => e.id == k)
                              .map((e) => e.employeeName)
                              .firstOrNull ??
                          'موظف محذوف',
                  count: countByCreator[k]!,
                  income: incomeByCreator[k] ?? 0,
                  outgoing: outgoingByCreator[k] ?? 0,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DiffDetailsScreen(
                        initialRange: detailsRange,
                        creatorFilter: k ?? kCreatorAdmin,
                        title: k == null
                            ? 'فرق حركة المدير'
                            : 'فرق حركة: ${employees.where((e) => e.id == k).map((e) => e.employeeName).firstOrNull ?? 'موظف محذوف'}',
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CreatorRow extends StatelessWidget {
  const _CreatorRow({
    required this.isAdmin,
    required this.label,
    required this.count,
    required this.income,
    required this.outgoing,
    required this.onTap,
  });

  final bool isAdmin;
  final String label;
  final int count;
  final double income;
  final double outgoing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final diff = income - outgoing;
    final diffColor =
        diff >= 0 ? AppColors.positive : AppColors.negative;
    final avatarColor = isAdmin ? AppColors.accent : AppColors.warning;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: avatarColor.withValues(alpha: 0.45),
                      ),
                    ),
                    child: FaIcon(
                      isAdmin
                          ? FontAwesomeIcons.userShield
                          : FontAwesomeIcons.userTie,
                      size: 16,
                      color: avatarColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHigh,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count عملية',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textLow,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const FaIcon(
                    FontAwesomeIcons.chevronLeft,
                    size: 12,
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: AppColors.glassBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'الدخول',
                      value: '+\$${formatMoney(income)}',
                      color: AppColors.positive,
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 32,
                    color: AppColors.glassBorder,
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'الخروج',
                      value: '-\$${formatMoney(outgoing)}',
                      color: AppColors.negative,
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 32,
                    color: AppColors.glassBorder,
                  ),
                  Expanded(
                    child: _MiniStat(
                      label: 'الفرق',
                      value:
                          '${diff >= 0 ? '+' : '-'}\$${formatMoney(diff.abs())}',
                      color: diffColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textLow,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
