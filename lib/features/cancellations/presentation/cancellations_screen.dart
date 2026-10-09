import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../archive/presentation/archive_filters.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../data/cancellations_repository.dart';
import '../domain/cancellation.dart';
import 'cancel_operation_dialog.dart';
import 'cancellations_providers.dart';

final _stampFmt = DateFormat('yyyy/MM/dd  HH:mm');

/// Admin → "الإلغاءات": the employees' requests waiting for a decision, and
/// كشف الإلغاءات for a period (with PDF).
class CancellationsScreen extends ConsumerStatefulWidget {
  const CancellationsScreen({super.key});

  @override
  ConsumerState<CancellationsScreen> createState() =>
      _CancellationsScreenState();
}

class _CancellationsScreenState extends ConsumerState<CancellationsScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;
  bool _exporting = false;

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

  Future<void> _export(
    List<OperationCancellation> rows,
    ({DateTime start, DateTime end}) r,
  ) async {
    setState(() => _exporting = true);
    try {
      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      final exportedBy =
          (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? meta['full_name'] as String
              : (meta['name'] as String?)?.trim().isNotEmpty == true
                  ? meta['name'] as String
                  : (user?.email ?? 'admin');
      String? notif;
      try {
        notif = (await ref.read(latestNotificationProvider.future))?.body;
      } catch (_) {
        notif = null;
      }
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildCancellationsReport(
        rows: rows,
        start: r.start,
        end: r.end,
        exportedBy: exportedBy,
        notificationText: notif,
      );
      await PdfExport.sharePdf(bytes, 'cancellations.pdf');
    } catch (e, st) {
      AppLogger.error('cancellations.export', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    final range = DateTimeRange(start: r.start, end: r.end);
    final listAsync = ref.watch(cancellationsBetweenProvider(range));
    final pending = ref.watch(pendingCancelRequestsProvider);
    final rows = listAsync.valueOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الإلغاءات'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تصدير كشف الإلغاءات PDF',
            onPressed: (rows == null || _exporting)
                ? null
                : () => _export(rows, r),
            icon: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FaIcon(FontAwesomeIcons.filePdf, size: 16),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () {
              ref.invalidate(cancellationsBetweenProvider(range));
              ref.invalidate(cancelRequestsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
        children: [
          _SectionTitle(
            text: 'طلبات الإلغاء من الموظفين',
            count: pending.length,
          ),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            const _Empty(text: 'لا توجد طلبات بانتظارك.')
          else
            for (final req in pending) ...[
              _RequestCard(request: req),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 16),
          const _SectionTitle(text: 'كشف الإلغاءات'),
          const SizedBox(height: 8),
          DateFilterBar(
            mode: _mode,
            from: _from,
            to: _to,
            onModeChanged: (m) => setState(() {
              _mode = m;
              if (m == DateFilterMode.today) {
                _from = null;
                _to = null;
              } else {
                _from ??= todayDate();
                _to ??= todayDate();
              }
            }),
            onPickFrom: _pickFrom,
            onPickTo: _pickTo,
            showInvalidHint: _mode == DateFilterMode.range && !_rangeReady,
          ),
          const SizedBox(height: 12),
          listAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _Empty(text: friendlyError(e)),
            data: (list) => list.isEmpty
                ? const _Empty(text: 'لا توجد عمليات ملغاة في هذه الفترة.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        _CancellationCard(number: i + 1, c: list[i]),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.count});
  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Text(
      count == null || count == 0 ? text : '$text ($count)',
      style: const TextStyle(
        color: AppColors.cancelled,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textLow, fontSize: 13),
      ),
    );
  }
}

/// One line of the card: label and value.
class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textLow, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? AppColors.textHigh,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request});
  final CancellationRequest request;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<void> _reject() async {
    final note = TextEditingController();
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفض طلب الإلغاء'),
        content: TextField(
          controller: note,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('رفض الطلب'),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(cancellationsRepositoryProvider)
          .reject(widget.request.id, note: text.isEmpty ? null : text);
      ref.invalidate(cancelRequestsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب وإبلاغ الموظف.')),
      );
    } catch (e, st) {
      AppLogger.error('cancellations.reject', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line('الموظف', req.employeeName),
          _Line(
            'العملية',
            '${req.kindLabel} بقيمة \$${formatMoney(req.amount)}',
            color: AppColors.cancelled,
          ),
          if ((req.partyName ?? '').trim().isNotEmpty)
            _Line(
              req.kind == OperationKind.transfer ? 'المستفيد' : 'العميل',
              req.partyName!.trim(),
            ),
          _Line('السبب', req.reason),
          _Line('وقت الطلب', _stampFmt.format(req.createdAt)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  child: const Text('رفض'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cancelled,
                  ),
                  onPressed: _busy
                      ? null
                      : () => showAdminCancelDialog(
                            context,
                            kind: req.kind,
                            operationId: req.operationId,
                            amount: req.amount,
                            partyName: req.partyName,
                            requestId: req.id,
                            initialReason: req.reason,
                          ),
                  child: const Text('موافقة وإلغاء'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CancellationCard extends StatelessWidget {
  const _CancellationCard({required this.number, required this.c});
  final int number;
  final OperationCancellation c;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '#$number  ${c.kindLabel} ملغى · \$${formatMoney(c.amount)}',
            style: const TextStyle(
              color: AppColors.cancelled,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          _Line('وقت الإلغاء', _stampFmt.format(c.cancelledAt)),
          _Line('الحساب', c.accountLabel),
          if ((c.reference ?? '').isNotEmpty) _Line('إشاري/كود', c.reference!),
          if ((c.partyName ?? '').isNotEmpty) _Line('الجهة', c.partyName!),
          _Line('وقت العملية', _stampFmt.format(c.operationCreatedAt)),
          _Line('المنفذ', c.operationEmployeeName),
          if (c.requestedByName != null)
            _Line('طلب الإلغاء', c.requestedByName!),
          _Line('ألغاها', c.cancelledByName),
          _Line('السبب', c.reason),
          _Line(
            'الرصيد',
            'قبل ${formatMoney(c.balanceBefore)} ← بعد ${formatMoney(c.balanceAfter)}',
          ),
        ],
      ),
    );
  }
}
