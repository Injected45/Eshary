import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import 'archive_providers.dart';

class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soldAsync = ref.watch(archivedTransfersProvider);
    final boughtAsync = ref.watch(archivedBuysProvider);
    final soldTotalAsync = ref.watch(archivedSoldTotalProvider);
    final boughtTotalAsync = ref.watch(archivedBoughtTotalProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        _SummaryRow(
          sold: soldTotalAsync.value ?? 0,
          bought: boughtTotalAsync.value ?? 0,
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(
                icon: FontAwesomeIcons.arrowTrendDown,
                color: AppColors.negative,
                text: '1- إجمالي خروج قيم \$ من الحسابات',
                onExport: () => _exportSold(
                  context,
                  soldAsync.value ?? const [],
                  soldTotalAsync.value ?? 0,
                ),
              ),
              soldAsync.when(
                data: (rows) => _SoldTable(
                  rows: rows,
                  total: soldTotalAsync.value ?? 0,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(
                icon: FontAwesomeIcons.arrowTrendUp,
                color: AppColors.positive,
                text: '2- إجمالي قيم \$ المشتراة (المرحلة)',
                onExport: () => _exportBought(
                  context,
                  boughtAsync.value ?? const [],
                  boughtTotalAsync.value ?? 0,
                ),
              ),
              boughtAsync.when(
                data: (rows) => _BoughtTable(
                  rows: rows,
                  total: boughtTotalAsync.value ?? 0,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
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
    );
  }

  Future<void> _exportSold(
    BuildContext context,
    List<Transfer> rows,
    double total,
  ) async {
    if (rows.isEmpty) return;
    try {
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildTable(
        title: 'الأرشيف العام — المباعة',
        headers: const ['التاريخ', 'الإشاري', 'القيمة \$'],
        rows: rows
            .map((t) => [
                  dateOnly.format(t.archivedAt ?? t.createdAt),
                  t.reference,
                  '-${formatMoney(t.amount)}',
                ])
            .toList(),
        totalLabel: 'الإجمالي',
        totalValue: formatMoney(total),
      );
      await PdfExport.sharePdf(bytes, 'archive_sold.pdf');
    } catch (e, st) {
      AppLogger.error('archive.exportSold', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _exportBought(
    BuildContext context,
    List<CurrencyBuy> rows,
    double total,
  ) async {
    if (rows.isEmpty) return;
    try {
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildTable(
        title: 'الأرشيف العام — المشتراة',
        headers: const ['التاريخ', 'القيمة \$', 'الحساب المستلم'],
        rows: rows
            .map((b) => [
                  dateOnly.format(b.archivedAt ?? b.createdAt),
                  '+${formatMoney(b.usdAmount)}',
                  b.clientFromAccount ?? '-',
                ])
            .toList(),
        totalLabel: 'الإجمالي',
        totalValue: formatMoney(total),
      );
      await PdfExport.sharePdf(bytes, 'archive_bought.pdf');
    } catch (e, st) {
      AppLogger.error('archive.exportBought', e, st);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.sold, required this.bought});
  final double sold;
  final double bought;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: FontAwesomeIcons.arrowTrendDown,
            label: 'مباع',
            value: formatMoney(sold),
            tint: AppColors.negative,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: FontAwesomeIcons.arrowTrendUp,
            label: 'مشتراة',
            value: formatMoney(bought),
            tint: AppColors.positive,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.15),
              border: Border.all(color: tint.withValues(alpha: 0.4)),
            ),
            child: FaIcon(icon, size: 16, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      color: AppColors.textLow, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  '\$$value',
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.text,
    required this.onExport,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          FaIcon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color,
              ),
            ),
          ),
          IconButton(
            tooltip: 'تصدير PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 16),
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

class _SoldTable extends StatelessWidget {
  const _SoldTable({required this.rows, required this.total});
  final List<Transfer> rows;
  final double total;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد سجلات',
            style: TextStyle(color: AppColors.textLow)),
      );
    }

    // Group rows by date string of archivedAt ?? createdAt.
    final grouped = <String, List<Transfer>>{};
    for (final t in rows) {
      final key = dateOnly.format(t.archivedAt ?? t.createdAt);
      grouped.putIfAbsent(key, () => <Transfer>[]).add(t);
    }
    final sortedDates = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // newest-first

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final date in sortedDates) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.calendar,
                  size: 12,
                  color: AppColors.textLow,
                ),
                const SizedBox(width: 6),
                Text(
                  date,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('اسم الشركة')),
                DataColumn(label: Text('الإشاري')),
                DataColumn(label: Text('القيمة \$')),
              ],
              rows: grouped[date]!
                  .map((t) => DataRow(
                        onSelectChanged: (_) =>
                            _openSoldDetail(context, t),
                        cells: [
                          DataCell(Text(t.beneficiaryName)),
                          DataCell(Text(t.reference)),
                          DataCell(Text(
                            '-${formatMoney(t.amount)}',
                            style:
                                const TextStyle(color: AppColors.negative),
                          )),
                        ],
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('')),
              DataColumn(label: Text('')),
              DataColumn(label: Text('')),
            ],
            headingRowHeight: 0,
            rows: [
              DataRow(
                color: WidgetStateProperty.all(
                  AppColors.negative.withValues(alpha: 0.08),
                ),
                cells: [
                  const DataCell(
                    Text('الإجمالي',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const DataCell(Text('-')),
                  DataCell(Text(
                    formatMoney(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.negative,
                    ),
                  )),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoughtTable extends StatelessWidget {
  const _BoughtTable({required this.rows, required this.total});
  final List<CurrencyBuy> rows;
  final double total;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد سجلات',
            style: TextStyle(color: AppColors.textLow)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('القيمة \$')),
        ],
        rows: [
          ...rows.map(
            (b) => DataRow(
              onSelectChanged: (_) => _openBoughtDetail(context, b),
              cells: [
                DataCell(
                    Text(dateOnly.format(b.archivedAt ?? b.createdAt))),
                DataCell(Text(
                  '+${formatMoney(b.usdAmount)}',
                  style: const TextStyle(color: AppColors.positive),
                )),
              ],
            ),
          ),
          DataRow(
            color: WidgetStateProperty.all(
              AppColors.positive.withValues(alpha: 0.08),
            ),
            cells: [
              const DataCell(
                Text('الإجمالي',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              DataCell(Text(
                formatMoney(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.positive,
                ),
              )),
            ],
          ),
        ],
      ),
    );
  }
}

void _openSoldDetail(BuildContext context, Transfer t) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _TransferArchiveDetailScreen(t: t),
    ),
  );
}

void _openBoughtDetail(BuildContext context, CurrencyBuy b) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _BuyArchiveDetailScreen(b: b),
    ),
  );
}

class _TransferArchiveDetailScreen extends StatelessWidget {
  const _TransferArchiveDetailScreen({required this.t});
  final Transfer t;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('تفاصيل الحوالة'),
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
                _DetailKv(
                  label: 'التاريخ',
                  value: dateTime.format(t.archivedAt ?? t.createdAt),
                ),
                _DetailKv(label: 'الرقم الإشاري', value: t.reference),
                _DetailKv(label: 'المستفيد', value: t.beneficiaryName),
                _DetailKv(
                  label: 'حساب المستفيد',
                  value: (t.beneficiaryAccountCompany?.isEmpty ?? true)
                      ? '—'
                      : t.beneficiaryAccountCompany!,
                ),
                _DetailKv(
                  label: 'كود حساب المستفيد',
                  value: (t.beneficiaryCode?.isEmpty ?? true)
                      ? '—'
                      : t.beneficiaryCode!,
                ),
                _DetailKv(
                  label: 'المبلغ',
                  value: '${formatMoney(t.amount)} \$',
                ),
                _DetailKv(
                  label: 'الحالة',
                  value: t.status == TransferStatus.archived
                      ? 'مرحّلة'
                      : 'يومية',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyArchiveDetailScreen extends StatelessWidget {
  const _BuyArchiveDetailScreen({required this.b});
  final CurrencyBuy b;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('تفاصيل عملية الشراء'),
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
                _DetailKv(
                  label: 'التاريخ',
                  value: dateTime.format(b.archivedAt ?? b.createdAt),
                ),
                _DetailKv(
                  label: 'الحساب المستلم',
                  value: b.clientFromAccount ?? '—',
                ),
                _DetailKv(
                  label: 'القيمة بالدولار',
                  value: '${formatMoney(b.usdAmount)} \$',
                ),
                _DetailKv(
                  label: 'سعر الصرف',
                  value: formatMoney(b.rate),
                ),
                _DetailKv(
                  label: 'القيمة بالدينار',
                  value: formatMoney(b.lydAmount),
                ),
                _DetailKv(
                  label: 'الحالة',
                  value: b.status == CurrencyBuyStatus.archived
                      ? 'مرحّلة'
                      : (b.status == CurrencyBuyStatus.pending
                          ? 'معلّقة'
                          : 'يومية'),
                ),
              ],
            ),
          ),
        ],
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
