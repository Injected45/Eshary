import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/logger.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger.dart';

/// «مطابقة الكشف» (migration 0092): the balance the exchange company's
/// statement shows for [exchangeId] at a moment, against ours at that same
/// moment; the difference and the earlier reconciliations.
Future<void> showReconcileDialog(
  BuildContext context, {
  required String exchangeId,
  required String accountName,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          _ReconcileDialog(exchangeId: exchangeId, accountName: accountName),
    );

class _ReconcileDialog extends ConsumerStatefulWidget {
  const _ReconcileDialog({required this.exchangeId, required this.accountName});
  final String exchangeId;
  final String accountName;

  @override
  ConsumerState<_ReconcileDialog> createState() => _ReconcileDialogState();
}

class _ReconcileDialogState extends ConsumerState<_ReconcileDialog> {
  final _theirs = TextEditingController();
  final _note = TextEditingController();
  DateTime _at = DateTime.now();
  bool _busy = false;
  String? _error;
  Reconciliation? _result;
  List<Reconciliation>? _history;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _theirs.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final h = await ref
          .read(ledgerRepositoryProvider)
          .reconciliations(widget.exchangeId);
      if (mounted) setState(() => _history = h);
    } catch (e, st) {
      AppLogger.error('reconcile.history', e, st);
      if (mounted) setState(() => _history = const []);
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked == null) return;
    // the end of that Libya day, or now for today
    final end = libyaDayStart(picked)
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    setState(() => _at = end.isAfter(DateTime.now()) ? DateTime.now() : end);
  }

  Future<void> _save() async {
    final text = _theirs.text.trim();
    final theirs = tryParseMoney(text, negative: true);
    if (theirs == null) {
      // an unreadable entry used to be saved as 0, with a false difference
      setState(() => _error = 'اكتب الرصيد كما في كشف الشركة (أرقام).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      final r = await ref.read(ledgerRepositoryProvider).reconcile(
            exchangeId: widget.exchangeId,
            at: _at,
            theirBalance: theirs,
            note: note.isEmpty ? null : note,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = r;
      });
      _loadHistory();
    } catch (e, st) {
      AppLogger.error('reconcile.save', e, st);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = LibyaDateFormat('yyyy/MM/dd HH:mm');
    final r = _result;
    return AlertDialog(
      title: Text('مطابقة كشف ${widget.accountName}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                key: const ValueKey('reconcile-day'),
                onPressed: _busy ? null : _pickDay,
                child: Text('الكشف حتى: ${when.format(_at)}'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('reconcile-theirs'),
                controller: _theirs,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الرصيد في كشف الشركة (\$)',
                  errorText: _error,
                ),
              ),
              TextField(
                controller: _note,
                maxLength: 300,
                decoration:
                    const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
              if (r != null) ...[
                const SizedBox(height: 6),
                Text(
                  'رصيدنا في نفس الوقت: \$${formatMoney(r.ourBalance)}',
                  key: const ValueKey('reconcile-ours'),
                ),
                Text(
                  r.matches
                      ? 'مطابق ✓'
                      : 'الفرق: \$${formatMoney(r.difference)} '
                          '(${r.difference > 0 ? 'كشفهم أكثر' : 'كشفهم أقل'})',
                  key: const ValueKey('reconcile-diff'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: r.matches ? AppColors.positive : AppColors.negative,
                  ),
                ),
                if (!r.matches)
                  const Text(
                    'راجع العمليات بين الكشفين. إن ثبت الفرق صحّحه من '
                    '«تسوية الرصيد» مع ذكر السبب.',
                    style: TextStyle(fontSize: 11, color: AppColors.textLow),
                  ),
              ],
              if ((_history ?? const []).isNotEmpty) ...[
                const Divider(height: 20),
                const Text(
                  'المطابقات السابقة',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final h in _history!.take(10))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${when.format(h.at)} · '
                      '${h.matches ? 'مطابق' : 'فرق \$${formatMoney(h.difference)}'}',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            h.matches ? AppColors.positive : AppColors.warning,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
        FilledButton(
          key: const ValueKey('reconcile-save'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '...' : 'طابق'),
        ),
      ],
    );
  }
}
