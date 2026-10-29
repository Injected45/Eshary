import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/pdf_file_name.dart';
import '../../../shared/top_message.dart';
import '../domain/reports.dart';
import 'report_period_picker.dart';

/// The administrator's name for the export line of a report.
String _exportedBy(WidgetRef ref) {
  final user = ref.read(supabaseClientProvider).auth.currentUser;
  final meta = user?.userMetadata ?? const <String, dynamic>{};
  for (final k in ['full_name', 'name']) {
    final v = (meta[k] as String?)?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return user?.email ?? 'المدير';
}

Future<void> _share(
  BuildContext context,
  String where,
  Future<void> Function() build,
) async {
  try {
    await build();
  } catch (e, st) {
    AppLogger.error(where, e, st);
    if (context.mounted) {
      showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
    }
  }
}

Future<void> exportPeriodPdf(
  BuildContext context,
  WidgetRef ref, {
  required PeriodReport report,
  required ReportPeriod period,
}) =>
    _share(context, 'reports.periodPdf', () async {
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildPeriodReport(
        report: report,
        first: period.first,
        last: period.last,
        exportedBy: _exportedBy(ref),
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName('تقرير الفترة', start: period.first, end: period.last),
      );
    });

Future<void> exportEmployeesPdf(
  BuildContext context,
  WidgetRef ref, {
  required PeriodReport report,
  required ReportPeriod period,
}) =>
    _share(context, 'reports.employeesPdf', () async {
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildEmployeesReport(
        report: report,
        first: period.first,
        last: period.last,
        exportedBy: _exportedBy(ref),
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName('أداء الموظفين', start: period.first, end: period.last),
      );
    });

Future<void> exportDebtAgingPdf(
  BuildContext context,
  WidgetRef ref, {
  required DebtAging aging,
}) =>
    _share(context, 'reports.debtAgingPdf', () async {
      final now = DateTime.now();
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildDebtAgingReport(
        aging: aging,
        exportedBy: _exportedBy(ref),
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName('أعمار الديون', start: now, end: now),
      );
    });
