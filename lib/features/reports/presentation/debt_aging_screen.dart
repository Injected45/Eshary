import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../customers/presentation/customer_statement_screen.dart';
import '../data/reports_repository.dart';
import '../domain/reports.dart';
import 'report_pdf.dart';
import 'report_widgets.dart';

/// «أعمار الديون»: what each customer owes us and since when (the oldest
/// debts are taken as paid first), who is over his limit, and whom we owe.
/// A tap opens the customer's statement.
class DebtAgingScreen extends ConsumerWidget {
  const DebtAgingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(debtAgingProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('أعمار الديون'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
            onPressed: async.valueOrNull == null
                ? null
                : () => exportDebtAgingPdf(context, ref, aging: async.value!),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(debtAgingProvider),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const LinearProgressIndicator(),
        error: (e, _) =>
            ReportMessage(friendlyError(e), color: AppColors.negative),
        data: (a) => ListView(
          padding:
              EdgeInsets.fromLTRB(16, 12, 16, contentBottomPadding(context)),
          children: [
            ReportTileRow([
              ReportTile(
                label: 'لنا على العملاء',
                value: lydText(a.owedToUs),
                sub: '${a.debtors.length} عميل',
              ),
              ReportTile(
                label: 'علينا للدائنين',
                value: lydText(a.weOwe),
                sub: '${a.creditors.length} جهة',
              ),
            ]),
            ReportTileRow([
              ReportTile(label: 'حتى 7 أيام', value: lydText(a.d7)),
              ReportTile(label: '8 إلى 30 يومًا', value: lydText(a.d30)),
            ]),
            ReportTileRow([
              ReportTile(
                label: '31 إلى 90 يومًا',
                value: lydText(a.d90),
                color: a.d90 > 0 ? AppColors.warning : null,
              ),
              ReportTile(
                label: 'أكثر من 90 يومًا',
                value: lydText(a.older),
                color: a.older > 0 ? AppColors.negative : null,
              ),
            ]),
            if (a.overLimit > 0)
              Text(
                '${a.overLimit} عميل تجاوز حد الدين.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.negative),
              ),
            const ReportSectionTitle('العملاء المدينون'),
            if (a.debtors.isEmpty)
              const ReportMessage('لا يوجد عميل مدين.')
            else
              for (final d in a.debtors) _DebtorCard(d: d),
            if (a.creditors.isNotEmpty) ...[
              const ReportSectionTitle('الدائنون (علينا)'),
              ReportCard(children: [
                for (final c in a.creditors)
                  ReportLine(
                    c.company == null || c.company!.isEmpty
                        ? c.name
                        : '${c.name} — ${c.company}',
                    lydText(c.owed),
                  ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _DebtorCard extends StatelessWidget {
  const _DebtorCard({required this.d});
  final Debtor d;

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('yyyy/MM/dd');
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CustomerStatementScreen(
            clientId: d.clientId,
            title: d.name,
            creditLimit: d.limit,
          ),
        ),
      ),
      child: ReportCard(children: [
        Row(
          children: [
            Expanded(
              child: Text(
                d.company == null || d.company!.isEmpty
                    ? d.name
                    : '${d.name} — ${d.company}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              lydText(d.owed),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: d.overLimit ? AppColors.negative : AppColors.textHigh,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (d.d7 > 0) ReportLine('حتى 7 أيام', lydText(d.d7)),
        if (d.d30 > 0) ReportLine('8 إلى 30 يومًا', lydText(d.d30)),
        if (d.d90 > 0)
          ReportLine('31 إلى 90 يومًا', lydText(d.d90),
              color: AppColors.warning),
        if (d.older > 0)
          ReportLine('أكثر من 90 يومًا', lydText(d.older),
              color: AppColors.negative),
        if (d.oldest != null)
          ReportLine('أقدم دين غير مسدد', f.format(d.oldest!)),
        ReportLine(
          'آخر تحصيل',
          d.lastCollect == null ? 'لا يوجد' : f.format(d.lastCollect!),
        ),
        if (d.overLimit)
          ReportLine(
            'تجاوز حد الدين',
            d.limit == null || d.limit == 0
                ? 'لا حد له'
                : 'الحد ${lydText(d.limit!)}',
            color: AppColors.negative,
          ),
      ]),
    );
  }
}
