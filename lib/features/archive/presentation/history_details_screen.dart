import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
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
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';

enum HistoryKind { income, outgoing }

class HistoryDetailsScreen extends ConsumerStatefulWidget {
  const HistoryDetailsScreen({super.key, required this.kind});
  final HistoryKind kind;

  @override
  ConsumerState<HistoryDetailsScreen> createState() =>
      _HistoryDetailsScreenState();
}

class _HistoryDetailsScreenState extends ConsumerState<HistoryDetailsScreen> {
  bool _newestFirst = true;
  DateTimeRange? _filterRange;

  bool get _isIncome => widget.kind == HistoryKind.income;
  Color get _tint => _isIncome ? AppColors.positive : AppColors.negative;
  String get _title => _isIncome ? 'تفاصيل الدخول' : 'تفاصيل الخروج';
  String get _totalLabel => _isIncome ? 'إجمالي الدخول' : 'إجمالي الخروج';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _filterRange,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) {
      setState(() => _filterRange = picked);
    }
  }

  void _clearFilter() => setState(() => _filterRange = null);

  bool _withinFilter(DateTime d) {
    final r = _filterRange;
    if (r == null) return true;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(r.start) && !day.isAfter(r.end);
  }

  @override
  Widget build(BuildContext context) {
    return _isIncome ? _buildIncome() : _buildOutgoing();
  }

  Widget _buildIncome() {
    final dailyAsync = ref.watch(dailyBuysProvider);
    final archivedAsync = ref.watch(archivedBuysProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: _renderIncome(dailyAsync, archivedAsync),
    );
  }

  Widget _renderIncome(
    AsyncValue<List<CurrencyBuy>> dailyAsync,
    AsyncValue<List<CurrencyBuy>> archivedAsync,
  ) {
    if (dailyAsync.isLoading || archivedAsync.isLoading) {
      return const LinearProgressIndicator();
    }
    if (dailyAsync.hasError) {
      return Center(
        child: Text('${dailyAsync.error}',
            style: const TextStyle(color: AppColors.negative)),
      );
    }
    if (archivedAsync.hasError) {
      return Center(
        child: Text('${archivedAsync.error}',
            style: const TextStyle(color: AppColors.negative)),
      );
    }
    final all = <CurrencyBuy>[
      ...(dailyAsync.value ?? const <CurrencyBuy>[]),
      ...(archivedAsync.value ?? const <CurrencyBuy>[]),
    ];
    final filtered = all
        .where((b) => _withinFilter(b.archivedAt ?? b.createdAt))
        .toList()
      ..sort((a, b) {
        final ad = a.archivedAt ?? a.createdAt;
        final bd = b.archivedAt ?? b.createdAt;
        return _newestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
      });
    final total = filtered.fold<double>(0, (s, b) => s + b.usdAmount);
    return _buildBody<CurrencyBuy>(
      rows: filtered,
      total: total,
      getDate: (b) => b.archivedAt ?? b.createdAt,
      getAmount: (b) => b.usdAmount,
      onExport: () => _exportPdf(filtered, total),
      onRowTap: (b) => showGlassDialog<void>(
        context: context,
        builder: (_) => _BuyDetailDialog(row: b),
      ),
      onRowDownload: _exportSingle,
    );
  }

  Widget _buildOutgoing() {
    final dailyAsync = ref.watch(dailyTransfersProvider);
    final archivedAsync = ref.watch(archivedTransfersProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: _renderOutgoing(dailyAsync, archivedAsync),
    );
  }

  Widget _renderOutgoing(
    AsyncValue<List<Transfer>> dailyAsync,
    AsyncValue<List<Transfer>> archivedAsync,
  ) {
    if (dailyAsync.isLoading || archivedAsync.isLoading) {
      return const LinearProgressIndicator();
    }
    if (dailyAsync.hasError) {
      return Center(
        child: Text('${dailyAsync.error}',
            style: const TextStyle(color: AppColors.negative)),
      );
    }
    if (archivedAsync.hasError) {
      return Center(
        child: Text('${archivedAsync.error}',
            style: const TextStyle(color: AppColors.negative)),
      );
    }
    final all = <Transfer>[
      ...(dailyAsync.value ?? const <Transfer>[]),
      ...(archivedAsync.value ?? const <Transfer>[]),
    ];
    final filtered = all
        .where((t) => _withinFilter(t.archivedAt ?? t.createdAt))
        .toList()
      ..sort((a, b) {
        final ad = a.archivedAt ?? a.createdAt;
        final bd = b.archivedAt ?? b.createdAt;
        return _newestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
      });
    final total = filtered.fold<double>(0, (s, t) => s + t.amount);
    return _buildBody<Transfer>(
      rows: filtered,
      total: total,
      getDate: (t) => t.archivedAt ?? t.createdAt,
      getAmount: (t) => t.amount,
      onExport: () => _exportPdf(filtered, total),
      onRowTap: (t) => showGlassDialog<void>(
        context: context,
        builder: (_) => _TransferDetailDialog(row: t),
      ),
      onRowDownload: _exportSingle,
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        title: Text(_title),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      );

  Widget _buildBody<T>({
    required List<T> rows,
    required double total,
    required DateTime Function(T) getDate,
    required double Function(T) getAmount,
    required VoidCallback onExport,
    required void Function(T) onRowTap,
    required void Function(T) onRowDownload,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SummaryCard(
          label: _totalLabel,
          total: total,
          count: rows.length,
          tint: _tint,
        ),
        const SizedBox(height: 12),
        _FilterSortRow(
          rangeActive: _filterRange != null,
          onTapFilter: _pickRange,
          onClearFilter: _clearFilter,
          newestFirst: _newestFirst,
          onSortChanged: (v) => setState(() => _newestFirst = v),
          onTapExport: rows.isEmpty ? null : onExport,
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'لا توجد سجلات',
                style: TextStyle(color: AppColors.textLow),
              ),
            ),
          )
        else ...[
          const _ColumnHeader(),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecordRow(
                index: i + 1,
                date: getDate(rows[i]),
                amount: getAmount(rows[i]),
                tint: _tint,
                onTap: () => onRowTap(rows[i]),
                onDownload: () => onRowDownload(rows[i]),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _exportPdf(List<dynamic> rows, double total) async {
    if (rows.isEmpty) return;
    try {
      final pdf = await PdfExport.load();
      final headers = const ['#', 'التاريخ والوقت', 'القيمة \$'];
      final rowsData = <List<String>>[];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        DateTime d;
        double amt;
        if (r is CurrencyBuy) {
          d = r.archivedAt ?? r.createdAt;
          amt = r.usdAmount;
        } else if (r is Transfer) {
          d = r.archivedAt ?? r.createdAt;
          amt = r.amount;
        } else {
          continue;
        }
        rowsData.add([
          '${i + 1}',
          dateTime.format(d),
          '${_isIncome ? '+' : '-'}${formatMoney(amt)}',
        ]);
      }
      final bytes = await pdf.buildTable(
        title: _title,
        headers: headers,
        rows: rowsData,
        totalLabel: 'الإجمالي',
        totalValue: '${_isIncome ? '+' : '-'}${formatMoney(total)}',
      );
      await PdfExport.sharePdf(
        bytes,
        _isIncome ? 'income_details.pdf' : 'outgoing_details.pdf',
      );
    } catch (e, st) {
      AppLogger.error('historyDetails.exportPdf', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _exportSingle(dynamic row) async {
    try {
      final pdf = await PdfExport.load();
      final companies =
          ref.read(companiesListProvider).value ?? const <Company>[];
      final exchanges =
          ref.read(allExchangesProvider).value ?? const <Exchange>[];
      final clients =
          ref.read(clientsListProvider).value ?? const <Client>[];

      String resolveCompany(String? id) =>
          companies.where((c) => c.id == id).map((c) => c.name).firstOrNull ??
          '—';
      String resolveExchange(String? id) =>
          exchanges.where((e) => e.id == id).map((e) => e.name).firstOrNull ??
          '—';
      String resolveClient(String? id) =>
          clients.where((c) => c.id == id).map((c) => c.name).firstOrNull ??
          '—';

      late final String title;
      late final String filename;
      late final List<List<String>> rowsData;
      if (row is CurrencyBuy) {
        title = 'تفاصيل الدخول — سجل واحد';
        filename = 'income_record_${row.id}.pdf';
        rowsData = [
          ['التاريخ', dateTime.format(row.archivedAt ?? row.createdAt)],
          [
            'الحالة',
            row.status == CurrencyBuyStatus.archived
                ? 'مرحّلة'
                : (row.status == CurrencyBuyStatus.pending
                    ? 'معلّقة'
                    : 'يومية'),
          ],
          ['شركتي', resolveCompany(row.myCompanyId)],
          ['شركة الصرافة', resolveExchange(row.exchangeId)],
          [
            'العميل',
            row.clientId != null
                ? resolveClient(row.clientId)
                : (row.clientFromAccount ?? '—'),
          ],
          ['القيمة بالدولار', '${formatMoney(row.usdAmount)} \$'],
          ['سعر الصرف', formatMoney(row.rate)],
          ['القيمة بالدينار', formatMoney(row.lydAmount)],
        ];
      } else if (row is Transfer) {
        title = 'تفاصيل الخروج — سجل واحد';
        filename = 'outgoing_record_${row.id}.pdf';
        rowsData = [
          ['التاريخ', dateTime.format(row.archivedAt ?? row.createdAt)],
          [
            'الحالة',
            row.status == TransferStatus.archived ? 'مرحّلة' : 'يومية',
          ],
          ['الرقم الإشاري', row.reference],
          ['شركتي', resolveCompany(row.companyId)],
          ['شركة الصرافة', resolveExchange(row.exchangeId)],
          ['المستفيد', row.beneficiaryName],
          [
            'حساب المستفيد',
            (row.beneficiaryAccountCompany?.isEmpty ?? true)
                ? '—'
                : row.beneficiaryAccountCompany!,
          ],
          [
            'كود حساب المستفيد',
            (row.beneficiaryCode?.isEmpty ?? true)
                ? '—'
                : row.beneficiaryCode!,
          ],
          ['القيمة بالدولار', '${formatMoney(row.amount)} \$'],
        ];
      } else {
        return;
      }

      final bytes = await pdf.buildTable(
        title: title,
        headers: const ['الحقل', 'القيمة'],
        rows: rowsData,
      );
      await PdfExport.sharePdf(bytes, filename);
    } catch (e, st) {
      AppLogger.error('historyDetails.exportSingle', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.total,
    required this.count,
    required this.tint,
  });
  final String label;
  final double total;
  final int count;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\$${formatMoney(total)}',
                    style: TextStyle(
                      color: tint,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(
              color: AppColors.glassBorder,
              width: 1,
              thickness: 1,
            ),
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'عدد العمليات',
                    style: TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.textHigh,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      children: [
                        TextSpan(text: '$count '),
                        const TextSpan(
                          text: 'عملية',
                          style: TextStyle(
                            color: AppColors.textMid,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSortRow extends StatelessWidget {
  const _FilterSortRow({
    required this.rangeActive,
    required this.onTapFilter,
    required this.onClearFilter,
    required this.newestFirst,
    required this.onSortChanged,
    required this.onTapExport,
  });
  final bool rangeActive;
  final VoidCallback onTapFilter;
  final VoidCallback onClearFilter;
  final bool newestFirst;
  final ValueChanged<bool> onSortChanged;
  final VoidCallback? onTapExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: rangeActive ? onClearFilter : onTapFilter,
          icon: FaIcon(
            rangeActive
                ? FontAwesomeIcons.filterCircleXmark
                : FontAwesomeIcons.filter,
            size: 12,
          ),
          label: Text(rangeActive ? 'إزالة التصفية' : 'تصفية'),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                rangeActive ? AppColors.accent : AppColors.textHigh,
            side: BorderSide(
              color: rangeActive
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.glassBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const Spacer(),
        if (onTapExport != null)
          IconButton(
            tooltip: 'تصدير PDF',
            onPressed: onTapExport,
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 16),
            color: AppColors.textMid,
          ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSortChanged(!newestFirst),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              Text(
                newestFirst ? 'الأحدث أولاً' : 'الأقدم أولاً',
                style: const TextStyle(
                  color: AppColors.textHigh,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              FaIcon(
                newestFirst
                    ? FontAwesomeIcons.arrowDownWideShort
                    : FontAwesomeIcons.arrowUpWideShort,
                size: 12,
                color: AppColors.textMid,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: const [
          SizedBox(width: 36),
          SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              'القيمة',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textLow,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'التاريخ والوقت',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textLow,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '#',
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
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.index,
    required this.date,
    required this.amount,
    required this.tint,
    required this.onTap,
    required this.onDownload,
  });
  final int index;
  final DateTime date;
  final double amount;
  final Color tint;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final tf = DateFormat('hh:mm a');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            border: Border.all(color: AppColors.glassBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onDownload,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: tint.withValues(alpha: 0.6),
                      ),
                      color: tint.withValues(alpha: 0.08),
                    ),
                    child: FaIcon(
                      FontAwesomeIcons.circleDown,
                      size: 14,
                      color: tint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Text(
                  formatMoney(amount),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  'USD',
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Text(
                  df.format(date),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 13,
                  ),
                ),
                Text(
                  tf.format(date),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.glassFillStrong,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AppColors.textHigh,
                fontWeight: FontWeight.w700,
                fontSize: 14,
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

class _DetailKv extends StatelessWidget {
  const _DetailKv({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textLow,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyDetailDialog extends ConsumerWidget {
  const _BuyDetailDialog({required this.row});
  final CurrencyBuy row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies =
        ref.watch(companiesListProvider).value ?? const <Company>[];
    final exchanges =
        ref.watch(allExchangesProvider).value ?? const <Exchange>[];
    final clients =
        ref.watch(clientsListProvider).value ?? const <Client>[];

    final companyName = companies
            .where((c) => c.id == row.myCompanyId)
            .map((c) => c.name)
            .firstOrNull ??
        '—';
    final exchangeName = exchanges
            .where((e) => e.id == row.exchangeId)
            .map((e) => e.name)
            .firstOrNull ??
        '—';
    final resolvedClient = row.clientId == null
        ? (row.clientFromAccount ?? '—')
        : (clients
                .where((c) => c.id == row.clientId)
                .map((c) => c.name)
                .firstOrNull ??
            (row.clientFromAccount ?? '—'));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'تفاصيل عملية الشراء',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DetailKv(
                label: 'التاريخ',
                value: dateTime.format(row.archivedAt ?? row.createdAt),
              ),
              _DetailKv(
                label: 'الحالة',
                value: row.status == CurrencyBuyStatus.archived
                    ? 'مرحّلة'
                    : (row.status == CurrencyBuyStatus.pending
                        ? 'معلّقة'
                        : 'يومية'),
              ),
              _DetailKv(label: 'شركتي', value: companyName),
              _DetailKv(label: 'شركة الصرافة', value: exchangeName),
              _DetailKv(label: 'العميل', value: resolvedClient),
              _DetailKv(
                label: 'القيمة بالدولار',
                value: '${formatMoney(row.usdAmount)} \$',
              ),
              _DetailKv(
                label: 'سعر الصرف',
                value: formatMoney(row.rate),
              ),
              _DetailKv(
                label: 'القيمة بالدينار',
                value: formatMoney(row.lydAmount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferDetailDialog extends ConsumerWidget {
  const _TransferDetailDialog({required this.row});
  final Transfer row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies =
        ref.watch(companiesListProvider).value ?? const <Company>[];
    final exchanges =
        ref.watch(allExchangesProvider).value ?? const <Exchange>[];

    final companyName = companies
            .where((c) => c.id == row.companyId)
            .map((c) => c.name)
            .firstOrNull ??
        '—';
    final exchangeName = exchanges
            .where((e) => e.id == row.exchangeId)
            .map((e) => e.name)
            .firstOrNull ??
        '—';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'تفاصيل الحوالة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DetailKv(
                label: 'التاريخ',
                value: dateTime.format(row.archivedAt ?? row.createdAt),
              ),
              _DetailKv(
                label: 'الحالة',
                value: row.status == TransferStatus.archived
                    ? 'مرحّلة'
                    : 'يومية',
              ),
              _DetailKv(
                label: 'الرقم الإشاري',
                value: row.reference,
              ),
              _DetailKv(label: 'شركتي', value: companyName),
              _DetailKv(label: 'شركة الصرافة', value: exchangeName),
              _DetailKv(
                label: 'المستفيد',
                value: row.beneficiaryName,
              ),
              _DetailKv(
                label: 'حساب المستفيد',
                value: (row.beneficiaryAccountCompany?.isEmpty ?? true)
                    ? '—'
                    : row.beneficiaryAccountCompany!,
              ),
              _DetailKv(
                label: 'كود حساب المستفيد',
                value: (row.beneficiaryCode?.isEmpty ?? true)
                    ? '—'
                    : row.beneficiaryCode!,
              ),
              _DetailKv(
                label: 'القيمة بالدولار',
                value: '${formatMoney(row.amount)} \$',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
