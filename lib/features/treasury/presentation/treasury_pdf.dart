import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/pdf_file_name.dart';
import '../../../shared/top_message.dart';
import '../data/treasury_repository.dart';
import '../domain/lyd_treasury.dart';
import '../domain/profit_report.dart';

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

/// "تقرير الأرباح" of [start]..[end] as a shared PDF.
Future<void> exportProfitPdf(
  BuildContext context,
  WidgetRef ref, {
  required List<ProfitRow> rows,
  required DateTime start,
  required DateTime end,
}) async {
  try {
    final pdf = await PdfExport.load();
    final bytes = await pdf.buildProfitReport(
      rows: rows,
      start: start,
      end: end,
      exportedBy: _exportedBy(ref),
    );
    await PdfExport.sharePdf(
      bytes,
      pdfFileName('تقرير الأرباح', start: start, end: end),
    );
  } catch (e, st) {
    AppLogger.error('treasury.profitPdf', e, st);
    if (context.mounted) {
      showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
    }
  }
}

/// "تقرير الخزينة" as it is now, with the dinar treasury when it is open.
Future<void> exportTreasuryPdf(BuildContext context, WidgetRef ref) async {
  try {
    final repo = ref.read(treasuryRepositoryProvider);
    final positions = await repo.positions();
    final now = DateTime.now();
    LydSummary? dinars;
    try {
      dinars = await repo.lydSummary(
        DateTime(now.year, now.month, now.day),
        now,
      );
    } catch (_) {
      dinars = null; // a database before 0086: the dollars only
    }
    final pdf = await PdfExport.load();
    final bytes = await pdf.buildTreasuryReport(
      positions: positions,
      dinars: dinars,
      exportedBy: _exportedBy(ref),
    );
    await PdfExport.sharePdf(
      bytes,
      pdfFileName('تقرير الخزينة', start: now, end: now),
    );
  } catch (e, st) {
    AppLogger.error('treasury.treasuryPdf', e, st);
    if (context.mounted) {
      showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
    }
  }
}
