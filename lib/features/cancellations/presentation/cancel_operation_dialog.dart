import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../data/cancellations_repository.dart';
import '../domain/cancellation.dart';
import 'cancellations_providers.dart';

/// Re-reads everything a cancellation changes: the operation lists, the
/// balances and the requests.
void invalidateAfterCancel(WidgetRef ref) {
  ref.invalidate(todayTransfersProvider);
  ref.invalidate(todayBuysProvider);
  ref.invalidate(archivedTransfersProvider);
  ref.invalidate(archivedBuysProvider);
  ref.invalidate(allExchangesProvider);
  ref.invalidate(cancelRequestsProvider);
  ref.invalidate(cancellationsBetweenProvider);
}

/// Admin: cancel an operation (reason + account password). Returns true when
/// it was cancelled. [requestId] approves an employee's request.
Future<bool> showAdminCancelDialog(
  BuildContext context, {
  required OperationKind kind,
  required String operationId,
  required double amount,
  String? partyName,
  String? requestId,
  String? initialReason,
}) async {
  final done = await showGlassDialog<bool>(
    context: context,
    builder: (_) => CancelOperationDialog(
      kind: kind,
      operationId: operationId,
      amount: amount,
      partyName: partyName,
      requestId: requestId,
      initialReason: initialReason,
      asEmployee: false,
    ),
  );
  return done ?? false;
}

/// Employee: ask the admin to cancel an operation (reason only).
Future<bool> showCancelRequestDialog(
  BuildContext context, {
  required OperationKind kind,
  required String operationId,
  required double amount,
  String? partyName,
}) async {
  final done = await showGlassDialog<bool>(
    context: context,
    builder: (_) => CancelOperationDialog(
      kind: kind,
      operationId: operationId,
      amount: amount,
      partyName: partyName,
      asEmployee: true,
    ),
  );
  return done ?? false;
}

class CancelOperationDialog extends ConsumerStatefulWidget {
  const CancelOperationDialog({
    super.key,
    required this.kind,
    required this.operationId,
    required this.amount,
    required this.asEmployee,
    this.partyName,
    this.requestId,
    this.initialReason,
  });

  final OperationKind kind;
  final String operationId;
  final double amount;
  final String? partyName;
  final String? requestId;
  final String? initialReason;

  /// true: send a request; false: the admin cancels with the password.
  final bool asEmployee;

  @override
  ConsumerState<CancelOperationDialog> createState() =>
      _CancelOperationDialogState();
}

class _CancelOperationDialogState extends ConsumerState<CancelOperationDialog> {
  late final _reason = TextEditingController(text: widget.initialReason);
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'اكتب سبب الإلغاء (3 أحرف على الأقل).');
      return;
    }
    if (!widget.asEmployee && _password.text.isEmpty) {
      setState(() => _error = 'اكتب كلمة مرور حسابك لتأكيد الإلغاء.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(cancellationsRepositoryProvider);
    try {
      if (widget.asEmployee) {
        await repo.request(
          kind: widget.kind,
          operationId: widget.operationId,
          reason: reason,
        );
        ref.invalidate(cancelRequestsProvider);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الإلغاء إلى المدير.')),
        );
        return;
      }
      final result = await repo.cancel(
        kind: widget.kind,
        operationId: widget.operationId,
        reason: reason,
        password: _password.text,
        requestId: widget.requestId,
      );
      if (!mounted) return;
      switch (result) {
        case CancelDone():
          invalidateAfterCancel(ref);
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم إلغاء العملية. الرصيد الآن \$${formatMoney(result.balanceAfter)}',
              ),
            ),
          );
        case CancelWrongPassword(:final remaining):
          _password.clear();
          setState(() {
            _busy = false;
            _error = remaining > 0
                ? 'كلمة المرور غير صحيحة. بقي $remaining محاولات.'
                : 'كلمة المرور غير صحيحة. تم إيقاف الإلغاء 15 دقيقة.';
          });
        case CancelLocked():
          setState(() {
            _busy = false;
            _error = 'تم إيقاف الإلغاء مؤقتاً بسبب محاولات خاطئة. '
                'حاول بعد 15 دقيقة.';
          });
        case CancelPasswordNotSet():
          setState(() {
            _busy = false;
            _error = 'حسابك بلا كلمة مرور (الدخول بجوجل). '
                'عيّن كلمة مرور من الإعدادات أولاً.';
          });
      }
    } catch (e, st) {
      AppLogger.error('cancellations.submit', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final party = (widget.partyName ?? '').trim();
    final isOut = widget.kind == OperationKind.transfer;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.asEmployee ? 'طلب إلغاء عملية' : 'إلغاء عملية',
                  style: const TextStyle(
                    color: AppColors.cancelled,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cancelled.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.cancelled.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    '${operationKindLabel(widget.kind)} بقيمة '
                    '\$${formatMoney(widget.amount)}'
                    '${party.isEmpty ? '' : '\n${isOut ? 'المستفيد' : 'العميل'}: $party'}',
                    style: const TextStyle(
                      color: AppColors.textHigh,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.asEmployee
                      ? 'يصل الطلب إلى المدير، وهو من يقرّر الإلغاء. '
                          'يمكن الإلغاء في يوم العملية فقط.'
                      : 'لن تُحذف العملية؛ يُسجَّل قيد عكسي يعيد الرصيد كما كان، '
                          'ويُحفظ الإلغاء في كشف الإلغاءات باسمك والسبب. '
                          'لا يمكن التراجع عن الإلغاء.',
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
                ),
                if (!widget.asEmployee) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _hidePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور حسابك',
                      suffixIcon: IconButton(
                        tooltip: _hidePassword ? 'إظهار' : 'إخفاء',
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                      ),
                    ),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.negative,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(false),
                        child: const Text('رجوع'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.cancelled,
                        ),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                widget.asEmployee
                                    ? 'إرسال الطلب'
                                    : 'تأكيد الإلغاء',
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
