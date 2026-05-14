import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/creator_filter.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../../../core/supabase_provider.dart';
import 'archive_filters.dart';

class DiffDetailsScreen extends ConsumerStatefulWidget {
  const DiffDetailsScreen({
    super.key,
    this.initialRange,
    this.includeDaily = false,
    this.title,
    this.creatorFilter,
  });

  final DateTimeRange? initialRange;

  /// When true, daily / pending rows are merged with the archived rows
  /// so the screen reflects everything the caller has authored — used by
  /// the employee app, where pre-close rows still belong to the running
  /// jurd. Admin's default is archived-only.
  final bool includeDaily;

  /// Optional override for the AppBar title (default: "تفاصيل فرق الحركة").
  final String? title;

  /// Optional row scoping by creator. `null` shows every row; a sub_user
  /// id shows only that employee's rows; a sentinel value (handled by
  /// `creatorPasses` below) shows only the admin's own rows.
  final String? creatorFilter;

  @override
  ConsumerState<DiffDetailsScreen> createState() =>
      _DiffDetailsScreenState();
}

class _DiffDetailsScreenState extends ConsumerState<DiffDetailsScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;
  bool _tableExpanded = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRange;
    if (r != null) {
      final today = DateTime.now();
      final isToday = r.start.year == today.year &&
          r.start.month == today.month &&
          r.start.day == today.day &&
          r.end.day == today.day;
      if (!isToday) {
        _mode = DateFilterMode.range;
        _from = r.start;
        _to = r.end;
      }
    }
  }

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
    final archivedBuys =
        ref.watch(archivedBuysProvider).value ?? const <CurrencyBuy>[];
    final archivedTransfers =
        ref.watch(archivedTransfersProvider).value ?? const <Transfer>[];

    // Employee mode pulls in daily / pending rows alongside the archived
    // ones so the jurd reflects everything the caller has authored, not
    // just what the admin has closed.
    final dailyBuys = widget.includeDaily
        ? (ref.watch(dailyBuysProvider).value ?? const <CurrencyBuy>[])
        : const <CurrencyBuy>[];
    final pendingBuys = widget.includeDaily
        ? (ref.watch(pendingBuysProvider).value ?? const <CurrencyBuy>[])
        : const <CurrencyBuy>[];
    final dailyTransfers = widget.includeDaily
        ? (ref.watch(dailyTransfersProvider).value ?? const <Transfer>[])
        : const <Transfer>[];

    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);

    DateTime _stampForBuy(CurrencyBuy b) => b.archivedAt ?? b.createdAt;
    DateTime _stampForTransfer(Transfer t) => t.archivedAt ?? t.createdAt;

    // Optional per-creator filter: passes either when no filter is set,
    // or when the row's `created_by_employee_id` matches via the shared
    // `creatorPasses` helper (which also understands the admin sentinel).
    bool creatorOk(String? createdByEmployeeId) {
      final f = widget.creatorFilter;
      if (f == null) return true;
      return creatorPasses(f, createdByEmployeeId);
    }

    final filteredBuys = [
      ...archivedBuys,
      ...dailyBuys,
      ...pendingBuys,
    ]
        .where((b) => inDateRange(_stampForBuy(b), r.start, r.end))
        .where((b) => creatorOk(b.createdByEmployeeId))
        .toList()
      ..sort((a, b) => _stampForBuy(a).compareTo(_stampForBuy(b)));

    final filteredTransfers = [
      ...archivedTransfers,
      ...dailyTransfers,
    ]
        .where((t) => inDateRange(_stampForTransfer(t), r.start, r.end))
        .where((t) => creatorOk(t.createdByEmployeeId))
        .toList()
      ..sort(
        (a, b) => _stampForTransfer(a).compareTo(_stampForTransfer(b)),
      );

    final incomeTotal =
        filteredBuys.fold<double>(0, (s, b) => s + b.usdAmount);
    final outgoingTotal =
        filteredTransfers.fold<double>(0, (s, t) => s + t.amount);
    final diff = incomeTotal - outgoingTotal;
    final hasAny =
        filteredBuys.isNotEmpty || filteredTransfers.isNotEmpty;

    final buckets = _bucketize(
      buys: filteredBuys,
      transfers: filteredTransfers,
      mode: _mode,
      start: r.start,
      end: r.end,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.title ?? 'تفاصيل فرق الحركة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تصدير PDF',
            onPressed: hasAny
                ? () => _exportPdf(
                      buys: filteredBuys,
                      transfers: filteredTransfers,
                      start: r.start,
                      end: r.end,
                    )
                : null,
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 16),
          ),
        ],
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
          _BigDiffCard(diff: diff, hasAny: hasAny),
          const SizedBox(height: 14),
          _ChartCard(buckets: buckets, hasAny: hasAny),
          const SizedBox(height: 14),
          _SummaryRow(
            incomeTotal: incomeTotal,
            outgoingTotal: outgoingTotal,
            diff: diff,
          ),
          const SizedBox(height: 14),
          _OperationsTable(
            buys: filteredBuys,
            transfers: filteredTransfers,
            expanded: _tableExpanded,
            onToggle: () =>
                setState(() => _tableExpanded = !_tableExpanded),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _exportPdf({
    required List<CurrencyBuy> buys,
    required List<Transfer> transfers,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final companies =
          ref.read(companiesListProvider).value ?? const <Company>[];
      final exchanges =
          ref.read(allExchangesProvider).value ?? const <Exchange>[];
      final clients =
          ref.read(clientsListProvider).value ?? const <Client>[];

      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      final exportedBy =
          (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? meta['full_name'] as String
              : (meta['name'] as String?)?.trim().isNotEmpty == true
                  ? meta['name'] as String
                  : (user?.email ?? 'admin');

      final pdf = await PdfExport.load();
      String? notif;
      try {
        final n = await ref.read(latestNotificationProvider.future);
        notif = n?.body;
      } catch (_) {
        notif = null;
      }
      // Employee → their name; admin → null (the PDF renders "ADMIN").
      final employeeName =
          ref.read(currentEmployeeProvider).value?.employeeName;
      final bytes = await pdf.buildDetailedTransfersReport(
        buys: buys,
        transfers: transfers,
        companyById: {for (final c in companies) c.id: c},
        exchangeById: {for (final e in exchanges) e.id: e},
        clientById: {for (final c in clients) c.id: c},
        start: start,
        end: end,
        exportedBy: exportedBy,
        notificationText: notif,
        employeeName: employeeName,
      );
      final filename = 'movement_'
          '${DateFormat('yyyyMMdd').format(start)}_'
          '${DateFormat('yyyyMMdd').format(end)}.pdf';
      await PdfExport.sharePdf(bytes, filename);
    } catch (e, st) {
      AppLogger.error('diffDetails.exportPdf', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

class _Bucket {
  _Bucket(this.label, this.t, this.income, this.outgoing);
  final String label;
  final DateTime t;
  double income;
  double outgoing;
}

List<_Bucket> _bucketize({
  required List<CurrencyBuy> buys,
  required List<Transfer> transfers,
  required DateFilterMode mode,
  required DateTime start,
  required DateTime end,
}) {
  final spanDays = end.difference(start).inDays + 1;

  final List<_Bucket> buckets = [];
  if (mode == DateFilterMode.today || spanDays <= 1) {
    final base = DateTime(start.year, start.month, start.day);
    final hourFmt = DateFormat('HH:mm');
    for (var h = 0; h < 24; h += 2) {
      final t = base.add(Duration(hours: h));
      buckets.add(_Bucket(hourFmt.format(t), t, 0, 0));
    }
  } else if (spanDays <= 14) {
    final dayFmt = DateFormat('MM/dd');
    for (var d = 0; d < spanDays; d++) {
      final t = DateTime(start.year, start.month, start.day + d);
      buckets.add(_Bucket(dayFmt.format(t), t, 0, 0));
    }
  } else {
    final dayFmt = DateFormat('MM/dd');
    var cursor = DateTime(start.year, start.month, start.day);
    while (!cursor.isAfter(end)) {
      buckets.add(_Bucket(dayFmt.format(cursor), cursor, 0, 0));
      cursor = cursor.add(const Duration(days: 7));
    }
  }

  if (buckets.isEmpty) return buckets;

  int bucketIndex(DateTime ts) {
    if (mode == DateFilterMode.today || spanDays <= 1) {
      final base = DateTime(start.year, start.month, start.day);
      final hours = ts.difference(base).inMinutes ~/ 60;
      final idx = (hours ~/ 2).clamp(0, buckets.length - 1);
      return idx;
    } else if (spanDays <= 14) {
      final base = DateTime(start.year, start.month, start.day);
      final tBase = DateTime(ts.year, ts.month, ts.day);
      final idx =
          tBase.difference(base).inDays.clamp(0, buckets.length - 1);
      return idx;
    } else {
      final base = DateTime(start.year, start.month, start.day);
      final tBase = DateTime(ts.year, ts.month, ts.day);
      final weeks = tBase.difference(base).inDays ~/ 7;
      return weeks.clamp(0, buckets.length - 1);
    }
  }

  for (final b in buys) {
    final ts = b.archivedAt ?? b.createdAt;
    buckets[bucketIndex(ts)].income += b.usdAmount;
  }
  for (final t in transfers) {
    final ts = t.archivedAt ?? t.createdAt;
    buckets[bucketIndex(ts)].outgoing += t.amount;
  }
  return buckets;
}

class _BigDiffCard extends StatelessWidget {
  const _BigDiffCard({required this.diff, required this.hasAny});

  final double diff;
  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    final isPositive = diff >= 0;
    final tint = !hasAny
        ? AppColors.textLow
        : (isPositive ? AppColors.positive : AppColors.negative);
    final sign = !hasAny ? '' : (isPositive ? '+' : '-');
    final caption = !hasAny
        ? 'لا توجد إقفالات بعد'
        : (diff == 0
            ? 'متوازن'
            : (isPositive
                ? 'الدخول أكثر من الخروج'
                : 'الخروج أكثر من الدخول'));

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
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
              size: 32,
              color: Color(0xFFE0B341),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'فرق الحركة',
                  style: TextStyle(
                    color: AppColors.textMid,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasAny ? '$sign\$${formatMoney(diff.abs())}' : '—',
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      caption,
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.buckets, required this.hasAny});

  final List<_Bucket> buckets;
  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, right: 8, bottom: 6),
            child: Text(
              'حركة الدخول والخروج',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textHigh,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _LegendDot(label: 'الدخول', color: AppColors.positive),
              SizedBox(width: 16),
              _LegendDot(label: 'الخروج', color: AppColors.negative),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: hasAny && buckets.isNotEmpty
                ? _LineChart(buckets: buckets)
                : const Center(
                    child: Text(
                      'لا توجد بيانات لعرضها',
                      style: TextStyle(
                        color: AppColors.textLow,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12, width: 1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMid,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.buckets});
  final List<_Bucket> buckets;

  @override
  Widget build(BuildContext context) {
    double maxVal = 0;
    for (final b in buckets) {
      if (b.income > maxVal) maxVal = b.income;
      if (b.outgoing > maxVal) maxVal = b.outgoing;
    }
    if (maxVal <= 0) maxVal = 1;
    final yInterval = _niceInterval(maxVal);
    final yMax = (maxVal / yInterval).ceil() * yInterval;

    final incomeSpots = <FlSpot>[
      for (var i = 0; i < buckets.length; i++)
        FlSpot(i.toDouble(), buckets[i].income),
    ];
    final outgoingSpots = <FlSpot>[
      for (var i = 0; i < buckets.length; i++)
        FlSpot(i.toDouble(), buckets[i].outgoing),
    ];

    final labelEvery = (buckets.length / 6).ceil().clamp(1, 99);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (buckets.length - 1).toDouble(),
        minY: 0,
        maxY: yMax.toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: Color(0x22FFFFFF),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yInterval,
              getTitlesWidget: (v, meta) {
                if (v == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text(
                      '0',
                      style: TextStyle(
                        color: AppColors.textLow,
                        fontSize: 10,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    _shortMoney(v),
                    style: const TextStyle(
                      color: AppColors.textLow,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= buckets.length) {
                  return const SizedBox.shrink();
                }
                if (i % labelEvery != 0 && i != buckets.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    buckets[i].label,
                    style: const TextStyle(
                      color: AppColors.textLow,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                AppColors.bgDeep.withValues(alpha: 0.92),
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            getTooltipItems: (touched) {
              if (touched.isEmpty) return const [];
              final i = touched.first.x.toInt();
              if (i < 0 || i >= buckets.length) return const [];
              final b = buckets[i];
              return [
                LineTooltipItem(
                  '${b.label}\n',
                  const TextStyle(
                    color: AppColors.textHigh,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  children: [
                    TextSpan(
                      text: 'الدخول  \$${formatMoney(b.income)}\n',
                      style: const TextStyle(
                        color: AppColors.positive,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    TextSpan(
                      text: 'الخروج  \$${formatMoney(b.outgoing)}',
                      style: const TextStyle(
                        color: AppColors.negative,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const LineTooltipItem('', TextStyle()),
              ];
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: incomeSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.positive,
            barWidth: 2.4,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.positive,
                strokeWidth: 1.4,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.positive.withValues(alpha: 0.08),
            ),
          ),
          LineChartBarData(
            spots: outgoingSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.negative,
            barWidth: 2.4,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.negative,
                strokeWidth: 1.4,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.negative.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

double _niceInterval(double maxVal) {
  if (maxVal <= 100) return 20;
  if (maxVal <= 500) return 100;
  if (maxVal <= 1000) return 200;
  if (maxVal <= 5000) return 1000;
  if (maxVal <= 10000) return 2000;
  if (maxVal <= 50000) return 10000;
  if (maxVal <= 100000) return 20000;
  if (maxVal <= 500000) return 100000;
  if (maxVal <= 1000000) return 200000;
  return (maxVal / 5).ceilToDouble();
}

String _shortMoney(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.incomeTotal,
    required this.outgoingTotal,
    required this.diff,
  });

  final double incomeTotal;
  final double outgoingTotal;
  final double diff;

  @override
  Widget build(BuildContext context) {
    final isPositive = diff >= 0;
    final diffTint = isPositive ? AppColors.positive : AppColors.negative;
    final diffSign = isPositive ? '+' : '-';
    return IntrinsicHeight(
      child: Row(
        children: [
          // RTL order: rightmost = إجمالي الدخول
          Expanded(
            child: _SummaryTile(
              label: 'إجمالي الدخول',
              value: '\$${formatMoney(incomeTotal)}',
              tint: AppColors.positive,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryTile(
              label: 'إجمالي الخروج',
              value: '\$${formatMoney(outgoingTotal)}',
              tint: AppColors.negative,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SummaryTile(
              label: 'فرق الحركة',
              value: '$diffSign\$${formatMoney(diff.abs())}',
              tint: diffTint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textLow,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tint,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationRow {
  _OperationRow({
    required this.t,
    required this.kind,
    required this.amountSigned,
    required this.account,
    required this.party,
    required this.status,
    required this.reference,
    this.runningDiff = 0,
  });
  final DateTime t;
  final String kind;
  final double amountSigned;
  final String account;
  final String party;
  final String status;
  /// Outgoing → transfer's own reference. Incoming → the buy's reference
  /// (which is what arrived from the sender).
  final String reference;
  double runningDiff;
}

class _OperationsTable extends ConsumerWidget {
  const _OperationsTable({
    required this.buys,
    required this.transfers,
    required this.expanded,
    required this.onToggle,
  });

  final List<CurrencyBuy> buys;
  final List<Transfer> transfers;
  final bool expanded;
  final VoidCallback onToggle;

  String _statusLabel(dynamic status) {
    final s = status.toString();
    if (s.contains('archived')) return 'مرحّلة';
    if (s.contains('pending')) return 'معلّقة';
    return 'يومية';
  }

  List<_OperationRow> _buildRows(WidgetRef ref) {
    final companies =
        ref.read(companiesListProvider).value ?? const <Company>[];
    final exchanges =
        ref.read(allExchangesProvider).value ?? const <Exchange>[];
    final clients =
        ref.read(clientsListProvider).value ?? const <Client>[];

    final companyName = <String, String>{
      for (final c in companies) c.id: c.name,
    };
    final exchangeName = <String, String>{
      for (final e in exchanges) e.id: e.name,
    };
    final clientName = <String, String>{
      for (final c in clients) c.id: c.name,
    };

    final all = <_OperationRow>[];
    for (final b in buys) {
      all.add(_OperationRow(
        t: b.archivedAt ?? b.createdAt,
        kind: 'دخول',
        amountSigned: b.usdAmount,
        account: companyName[b.myCompanyId] ?? '—',
        party: b.clientId != null
            ? (clientName[b.clientId!] ?? b.clientFromAccount ?? '—')
            : (b.clientFromAccount ?? '—'),
        status: _statusLabel(b.status),
        reference: b.reference.isEmpty ? '—' : b.reference,
      ));
    }
    for (final t in transfers) {
      all.add(_OperationRow(
        t: t.archivedAt ?? t.createdAt,
        kind: 'خروج',
        amountSigned: -t.amount,
        account: '${exchangeName[t.exchangeId] ?? '—'} / '
            '${companyName[t.companyId] ?? '—'}',
        party: t.beneficiaryName.isEmpty ? '—' : t.beneficiaryName,
        status: _statusLabel(t.status),
        reference: t.reference.isEmpty ? '—' : t.reference,
      ));
    }
    all.sort((a, b) => a.t.compareTo(b.t));

    var run = 0.0;
    for (final r in all) {
      run += r.amountSigned;
      r.runningDiff = run;
    }
    return all;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = _buildRows(ref);
    final tf = DateFormat('hh:mm a');
    final df = DateFormat('yyyy/MM/dd');
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: (_) => onToggle(),
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          title: const Text(
            'كل العمليات',
            style: TextStyle(
              color: AppColors.textHigh,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          trailing: FaIcon(
            expanded
                ? FontAwesomeIcons.chevronUp
                : FontAwesomeIcons.chevronDown,
            size: 14,
            color: AppColors.textLow,
          ),
          children: [
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'لا توجد عمليات في هذه الفترة',
                    style: TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 44,
                  columnSpacing: 18,
                  columns: const [
                    DataColumn(label: Text('الوقت')),
                    DataColumn(label: Text('القيمة')),
                    DataColumn(label: Text('الحساب')),
                    DataColumn(label: Text('الجهة')),
                    DataColumn(label: Text('إشاري')),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(cells: [
                        DataCell(Text(
                          '${tf.format(r.t)}\n${df.format(r.t)}',
                          style: const TextStyle(fontSize: 11),
                        )),
                        DataCell(Text(
                          '${r.amountSigned >= 0 ? '+' : '-'}\$${formatMoney(r.amountSigned.abs())}',
                          style: TextStyle(
                            color: r.amountSigned >= 0
                                ? AppColors.positive
                                : AppColors.negative,
                            fontWeight: FontWeight.w700,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 140,
                          child: Text(
                            r.account,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 120,
                          child: Text(
                            r.party,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        )),
                        DataCell(Text(
                          r.reference,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: AppColors.textHigh,
                          ),
                        )),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
