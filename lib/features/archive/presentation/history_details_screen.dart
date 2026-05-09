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
import '../../../core/supabase_provider.dart';

enum HistoryKind { income, outgoing }

class HistoryDetailsScreen extends ConsumerStatefulWidget {
  const HistoryDetailsScreen({
    super.key,
    required this.kind,
    this.initialRange,
  });
  final HistoryKind kind;
  final DateTimeRange? initialRange;

  @override
  ConsumerState<HistoryDetailsScreen> createState() =>
      _HistoryDetailsScreenState();
}

class _HistoryDetailsScreenState extends ConsumerState<HistoryDetailsScreen> {
  bool _newestFirst = true;
  DateTimeRange? _filterRange;

  @override
  void initState() {
    super.initState();
    _filterRange = widget.initialRange;
  }

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
    final archivedAsync = ref.watch(archivedBuysProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: _renderIncome(archivedAsync),
    );
  }

  Widget _renderIncome(
    AsyncValue<List<CurrencyBuy>> archivedAsync,
  ) {
    if (archivedAsync.isLoading) {
      return const LinearProgressIndicator();
    }
    if (archivedAsync.hasError) {
      return Center(
        child: Text('${archivedAsync.error}',
            style: const TextStyle(color: AppColors.negative)),
      );
    }
    final all = archivedAsync.value ?? const <CurrencyBuy>[];
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

      if (_isIncome) {
        final buys = rows.whereType<CurrencyBuy>().toList();
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

        DateTime start;
        DateTime end;
        if (_filterRange != null) {
          start = _filterRange!.start;
          end = _filterRange!.end;
        } else if (buys.isNotEmpty) {
          final dates = buys
              .map((b) => b.archivedAt ?? b.createdAt)
              .toList()
            ..sort();
          start = dates.first;
          end = dates.last;
        } else {
          final now = DateTime.now();
          start = now;
          end = now;
        }

        final bytes = await pdf.buildIncomeDetailsReport(
          buys: buys,
          companyById: {for (final c in companies) c.id: c},
          exchangeById: {for (final e in exchanges) e.id: e},
          clientById: {for (final c in clients) c.id: c},
          start: start,
          end: end,
          title: _title,
          exportedBy: exportedBy,
        );
        await PdfExport.sharePdf(bytes, 'income_details.pdf');
        return;
      }

      final outTransfers = rows.whereType<Transfer>().toList();
      final companies =
          ref.read(companiesListProvider).value ?? const <Company>[];
      final exchanges =
          ref.read(allExchangesProvider).value ?? const <Exchange>[];

      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      final exportedBy =
          (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? meta['full_name'] as String
              : (meta['name'] as String?)?.trim().isNotEmpty == true
                  ? meta['name'] as String
                  : (user?.email ?? 'admin');

      DateTime start;
      DateTime end;
      if (_filterRange != null) {
        start = _filterRange!.start;
        end = _filterRange!.end;
      } else if (outTransfers.isNotEmpty) {
        final dates = outTransfers
            .map((t) => t.archivedAt ?? t.createdAt)
            .toList()
          ..sort();
        start = dates.first;
        end = dates.last;
      } else {
        final now = DateTime.now();
        start = now;
        end = now;
      }

      final bytes = await pdf.buildOutgoingDetailsReport(
        transfers: outTransfers,
        companyById: {for (final c in companies) c.id: c},
        exchangeById: {for (final e in exchanges) e.id: e},
        start: start,
        end: end,
        exportedBy: exportedBy,
      );
      await PdfExport.sharePdf(bytes, 'outgoing_details.pdf');
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
          SizedBox(width: 12),
          SizedBox(width: 36),
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
              Expanded(
                flex: 3,
                child: Text(
                  '\$${formatMoney(amount)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
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
              const SizedBox(width: 12),
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
            ],
          ),
        ),
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

    final myCompanyName = companies
            .where((c) => c.id == row.myCompanyId)
            .map((c) => c.name)
            .firstOrNull ??
        '—';
    Exchange? exchange;
    for (final e in exchanges) {
      if (e.id == row.exchangeId) {
        exchange = e;
        break;
      }
    }
    final exchangeName = exchange?.name ?? '—';
    final myAccountCode = (exchange?.ourCode?.isEmpty ?? true)
        ? '—'
        : exchange!.ourCode!;

    Client? client;
    if (row.clientId != null) {
      for (final c in clients) {
        if (c.id == row.clientId) {
          client = c;
          break;
        }
      }
    }
    final senderCompany = client?.company ??
        (row.clientFromAccount?.isNotEmpty ?? false
            ? row.clientFromAccount!
            : '—');
    final senderAccount = client?.name ?? '—';
    final senderCode = (client?.code?.isEmpty ?? true) ? '—' : client!.code!;

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
              _DetailDialogHeader(
                title: 'تفاصيل عملية دخول',
                accent: AppColors.positive,
                icon: FontAwesomeIcons.chevronDown,
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'التاريخ والوقت : ${dateTime.format(row.archivedAt ?? row.createdAt)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMid,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _DetailDialogSection(
                title: 'وجهة الدخول',
                accent: AppColors.accent,
                icon: FontAwesomeIcons.user,
                rows: [
                  _DetailKvData('اسم الشركة', exchangeName),
                  _DetailKvData('اسم حسابي', myCompanyName),
                  _DetailKvData('رقم حسابي', myAccountCode),
                ],
              ),
              const SizedBox(height: 12),
              _DetailDialogSection(
                title: 'الجهة المرسلة',
                accent: AppColors.negative,
                icon: FontAwesomeIcons.paperPlane,
                rows: [
                  _DetailKvData('الشركة المرسلة', senderCompany),
                  _DetailKvData('حساب المرسل', senderAccount),
                  _DetailKvData('كود المرسل', senderCode),
                  _DetailKvData(
                    'الإشاري',
                    row.reference.isEmpty ? '—' : row.reference,
                  ),
                  _DetailKvData(
                    'القيمة',
                    '\$ ${formatMoney(row.usdAmount)}',
                    color: AppColors.positive,
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

class _TransferDetailDialog extends ConsumerWidget {
  const _TransferDetailDialog({required this.row});
  final Transfer row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companies =
        ref.watch(companiesListProvider).value ?? const <Company>[];
    final exchanges =
        ref.watch(allExchangesProvider).value ?? const <Exchange>[];

    final myCompanyName = companies
            .where((c) => c.id == row.companyId)
            .map((c) => c.name)
            .firstOrNull ??
        '—';
    Exchange? exchange;
    for (final e in exchanges) {
      if (e.id == row.exchangeId) {
        exchange = e;
        break;
      }
    }
    final exchangeName = exchange?.name ?? '—';
    final myAccountCode = (exchange?.ourCode?.isEmpty ?? true)
        ? '—'
        : exchange!.ourCode!;

    final beneficiaryCompany =
        (row.beneficiaryAccountCompany?.isEmpty ?? true)
            ? '—'
            : row.beneficiaryAccountCompany!;
    final beneficiaryName =
        row.beneficiaryName.isEmpty ? '—' : row.beneficiaryName;
    final beneficiaryCode = (row.beneficiaryCode?.isEmpty ?? true)
        ? '—'
        : row.beneficiaryCode!;

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
              _DetailDialogHeader(
                title: 'تفاصيل عملية خروج',
                accent: AppColors.negative,
                icon: FontAwesomeIcons.chevronUp,
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'التاريخ والوقت : ${dateTime.format(row.archivedAt ?? row.createdAt)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMid,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _DetailDialogSection(
                title: 'الجهة المنفذة',
                accent: AppColors.negative,
                icon: FontAwesomeIcons.shop,
                rows: [
                  _DetailKvData('اسم الشركة', exchangeName),
                  _DetailKvData('اسم حسابي', myCompanyName),
                  _DetailKvData('رقم حسابي', myAccountCode),
                  _DetailKvData(
                    'الإشاري',
                    row.reference.isEmpty ? '—' : row.reference,
                  ),
                  _DetailKvData(
                    'القيمة',
                    '\$ ${formatMoney(row.amount)}',
                    color: AppColors.negative,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DetailDialogSection(
                title: 'جهة الاستلام',
                accent: AppColors.positive,
                icon: FontAwesomeIcons.user,
                rows: [
                  _DetailKvData('الشركة المستفيدة', beneficiaryCompany),
                  _DetailKvData('حساب المستلم', beneficiaryName),
                  _DetailKvData('كود حساب المستلم', beneficiaryCode),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _DetailKvData {
  const _DetailKvData(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
}

class _DetailDialogHeader extends StatelessWidget {
  const _DetailDialogHeader({
    required this.title,
    required this.accent,
    required this.icon,
  });
  final String title;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 1.5),
            color: accent.withValues(alpha: 0.10),
          ),
          child: FaIcon(icon, size: 13, color: accent),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
          color: AppColors.textLow,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }
}

class _DetailDialogSection extends StatelessWidget {
  const _DetailDialogSection({
    required this.title,
    required this.accent,
    required this.icon,
    required this.rows,
  });
  final String title;
  final Color accent;
  final IconData icon;
  final List<_DetailKvData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                color: AppColors.glassBorder,
                height: 1,
                thickness: 1,
              ),
            _DetailDialogRow(
              label: rows[i].label,
              value: rows[i].value,
              color: rows[i].color,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailDialogRow extends StatelessWidget {
  const _DetailDialogRow({
    required this.label,
    required this.value,
    this.color,
  });
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final labelColor = color ?? AppColors.textMid;
    final valueColor = color ?? AppColors.textHigh;
    final separatorColor = color ?? AppColors.textLow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: labelColor,
                fontWeight:
                    color == null ? FontWeight.normal : FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              ':',
              style: TextStyle(
                fontSize: 13,
                color: separatorColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

