import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/reports_repository.dart';
import 'report_pdf.dart';
import 'report_period_picker.dart';
import 'report_widgets.dart';

/// «أداء الموظفين»: for each employee (and the administrator) of a period —
/// the operations, the dollars sold and bought, the profit of their sales,
/// what they sold on credit and how many of their operations were cancelled.
class EmployeesReportScreen extends ConsumerStatefulWidget {
  const EmployeesReportScreen({super.key});

  @override
  ConsumerState<EmployeesReportScreen> createState() =>
      _EmployeesReportScreenState();
}

class _EmployeesReportScreenState extends ConsumerState<EmployeesReportScreen> {
  ReportPeriod _period = ReportPeriod.today();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(periodReportProvider(_period.range));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('أداء الموظفين'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
            onPressed: async.valueOrNull == null
                ? null
                : () => exportEmployeesPdf(
                      context,
                      ref,
                      report: async.value!,
                      period: _period,
                    ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, contentBottomPadding(context)),
        children: [
          ReportPeriodPicker(
            onChanged: (p) => setState(() => _period = p),
          ),
          const SizedBox(height: 8),
          Text(
            _period.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMid),
          ),
          const SizedBox(height: 8),
          async.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) =>
                ReportMessage(friendlyError(e), color: AppColors.negative),
            data: (r) {
              if (r.byEmployee.isEmpty) {
                return const ReportMessage('لا توجد عمليات في هذه الفترة.');
              }
              final total = r.saleUsd + r.buyUsd;
              return Column(
                children: [
                  for (final e in r.byEmployee)
                    ReportCard(children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (total > 0)
                            Text(
                              '${((e.saleUsd + e.buyUsd) / total * 100).round()} % من الحجم',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMid,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ReportLine('العمليات', '${e.operations}'),
                      ReportLine(
                        'بيع ${e.saleN}',
                        '${usdText(e.saleUsd)} · ${lydText(e.saleLyd)}',
                      ),
                      ReportLine(
                        'شراء ${e.buyN}',
                        '${usdText(e.buyUsd)} · ${lydText(e.buyLyd)}',
                      ),
                      ReportLine('ربح مبيعاته', signedLydText(e.profit),
                          color: signedColor(e.profit), bold: true),
                      if (e.creditGiven > 0)
                        ReportLine('باع بالآجل', lydText(e.creditGiven)),
                      if (e.cancelledN > 0)
                        ReportLine('عمليات ملغاة', '${e.cancelledN}',
                            color: AppColors.warning),
                    ]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
