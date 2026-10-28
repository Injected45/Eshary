import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../data/adjustments_repository.dart';
import '../domain/balance_adjustment.dart';

/// The administrator corrects an account's balance (to match the exchange
/// company's statement): the new balance, a reason and the password. True when
/// it was saved.
Future<bool> showAdjustBalanceDialog(
  BuildContext context, {
  required String exchangeId,
  required String accountName,
  required double balance,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AdjustBalanceDialog(
      exchangeId: exchangeId,
      accountName: accountName,
      balance: balance,
    ),
  );
  return res ?? false;
}

class AdjustBalanceDialog extends ConsumerStatefulWidget {
  const AdjustBalanceDialog({
    super.key,
    required this.exchangeId,
    required this.accountName,
    required this.balance,
  });

  final String exchangeId;
  final String accountName;
  final double balance;

  @override
  ConsumerState<AdjustBalanceDialog> createState() =>
      _AdjustBalanceDialogState();
}

class _AdjustBalanceDialogState extends ConsumerState<AdjustBalanceDialog> {
  final _newBalance = TextEditingController();
  final _reason = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _newBalance.dispose();
    _reason.dispose();
    _password.dispose();
    super.dispose();
  }

  double get _typed => (parseMoney(_newBalance.text) * 100).round() / 100;

  Future<void> _submit() async {
    final newBalance = _typed;
    final reason = _reason.text.trim();
    if (_newBalance.text.trim().isEmpty || newBalance < 0) {
      setState(() => _error = 'اكتب الرصيد الصحيح للحساب.');
      return;
    }
    if (newBalance == widget.balance) {
      setState(() => _error = 'الرصيد الجديد مثل الحالي، لا يوجد ما يُسوّى.');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'اكتب سبب التسوية (3 أحرف على الأقل).');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'اكتب كلمة مرور حسابك لتأكيد التسوية.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(adjustmentsRepositoryProvider).adjust(
            exchangeId: widget.exchangeId,
            newBalance: newBalance,
            reason: reason,
            password: _password.text,
          );
      if (!mounted) return;
      switch (result) {
        case AdjustDone(:final balanceAfter):
          Navigator.of(context).pop(true);
          showTopSnackBar(
            context,
            SnackBar(
              content: Text(
                'تمت التسوية. رصيد ${widget.accountName} الآن '
                '\$${formatMoney(balanceAfter)}',
              ),
            ),
          );
        case AdjustWrongPassword(:final remaining):
          _password.clear();
          setState(() {
            _busy = false;
            _error = remaining > 0
                ? 'كلمة المرور غير صحيحة. بقي $remaining محاولات.'
                : 'كلمة المرور غير صحيحة. تم الإيقاف 15 دقيقة.';
          });
        case AdjustLocked():
          setState(() {
            _busy = false;
            _error = 'تم الإيقاف مؤقتاً بسبب محاولات خاطئة. حاول بعد 15 دقيقة.';
          });
        case AdjustPasswordNotSet():
          setState(() {
            _busy = false;
            _error = 'حسابك بلا كلمة مرور (الدخول بجوجل). '
                'عيّن كلمة مرور من الإعدادات أولاً.';
          });
      }
    } catch (e, st) {
      AppLogger.error('adjustments.submit', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = _newBalance.text.trim().isEmpty ? null : _typed;
    final delta = typed == null ? null : typed - widget.balance;
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
                  'تسوية رصيد ${widget.accountName}',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'الرصيد الحالي \$${formatMoney(widget.balance)}',
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'اكتب الرصيد الصحيح كما في كشف الشركة. يُحفظ الفرق مع السبب '
                  'واسمك ويظهر في كشف الحساب، ولا يغيّر سعر التكلفة.',
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('adjust-new-balance'),
                  controller: _newBalance,
                  enabled: !_busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'الرصيد الصحيح (\$)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    delta > 0
                        ? 'زيادة \$${formatMoney(delta)}'
                        : 'نقص \$${formatMoney(-delta)}',
                    key: const ValueKey('adjust-delta'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          delta > 0 ? AppColors.positive : AppColors.negative,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('adjust-reason'),
                  controller: _reason,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'سبب التسوية'),
                ),
                TextField(
                  key: const ValueKey('adjust-password'),
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
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const ValueKey('adjust-error'),
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
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('رجوع'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('adjust-save'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('تأكيد التسوية'),
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
