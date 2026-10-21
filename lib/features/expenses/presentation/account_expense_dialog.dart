import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/logger.dart';
import '../../../shared/password_field.dart';
import '../../../shared/top_message.dart';
import '../../cancellations/domain/cancellation.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/account_statement_providers.dart';
import '../../companies/presentation/companies_providers.dart';
import '../data/account_expenses_repository.dart';
import '../domain/account_expense.dart';

/// What the note starts as: the usual reason. The administrator rewrites it.
const kDefaultExpenseNote = 'عمولة';

/// "خصم عمولة": a one-sided deduction from [exchange]'s balance. The amount,
/// the code and what it is for are typed by hand. Below the form, today's
/// commissions of this account, each with a button to cancel a mistake.
Future<void> showAccountExpenseDialog(
  BuildContext context, {
  required Exchange exchange,
  required String accountName,
}) {
  return showGlassDialog<void>(
    context: context,
    builder: (_) => AccountExpenseDialog(
      exchange: exchange,
      accountName: accountName,
    ),
  );
}

class AccountExpenseDialog extends ConsumerStatefulWidget {
  const AccountExpenseDialog({
    super.key,
    required this.exchange,
    required this.accountName,
  });

  final Exchange exchange;

  /// "<my company> — <exchange company>", to show whose account it is.
  final String accountName;

  @override
  ConsumerState<AccountExpenseDialog> createState() =>
      _AccountExpenseDialogState();
}

class _AccountExpenseDialogState extends ConsumerState<AccountExpenseDialog> {
  final _code = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController(text: kDefaultExpenseNote);
  bool _busy = false;
  String? _error;

  static final _timeFmt = LibyaDateFormat('HH:mm');

  @override
  void dispose() {
    _code.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The account as it is now (the balance moves with every commission).
  Exchange get _exchange =>
      (ref.watch(allExchangesProvider).valueOrNull ?? const <Exchange>[])
          .where((e) => e.id == widget.exchange.id)
          .firstOrNull ??
      widget.exchange;

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    final note = _note.text.trim();
    if (amount <= 0) {
      setState(() => _error = 'اكتب قيمة العمولة.');
      return;
    }
    if (note.isEmpty) {
      setState(() => _error = 'اكتب ما تخصّ به العمولة.');
      return;
    }
    if (amount > _exchange.balance) {
      setState(
        () => _error = 'الرصيد لا يكفي: رصيد الحساب '
            '\$${formatMoney(_exchange.balance)} فقط.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountExpensesRepositoryProvider).record(
            exchangeId: widget.exchange.id,
            amount: amount,
            code: _code.text.trim().isEmpty ? null : _code.text.trim(),
            note: note,
          );
      _refreshAfterChange();
      if (!mounted) return;
      _code.clear();
      _amount.clear();
      _note.text = kDefaultExpenseNote;
      showTopSnackBar(
        context,
        SnackBar(content: Text('تم خصم \$${formatMoney(amount)} من الحساب')),
      );
    } catch (e, st) {
      AppLogger.error('expenses.record', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The balance and every statement follow the change.
  void _refreshAfterChange() {
    ref.invalidate(allExchangesProvider);
    ref.invalidate(todayExpensesProvider);
    ref.invalidate(statementDataProvider);
  }

  Future<void> _cancel(AccountExpense e) async {
    final done = await showGlassDialog<bool>(
      context: context,
      builder: (_) => _CancelExpenseDialog(expense: e),
    );
    if (done == true) {
      _refreshAfterChange();
      if (!mounted) return;
      showTopSnackBar(
        context,
        const SnackBar(content: Text('تم إلغاء العمولة وأُعيد المبلغ للحساب')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ex = _exchange;
    final today = (ref.watch(todayExpensesProvider).valueOrNull ??
            const <AccountExpense>[])
        .where((e) => e.exchangeId == widget.exchange.id)
        .toList()
        .reversed
        .toList();
    final code = (ex.ourCode ?? '').trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.fileInvoiceDollar,
                      size: 18,
                      color: AppColors.negative,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'خصم عمولة',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textHigh,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                      color: AppColors.textLow,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.accountName,
                  style: const TextStyle(color: AppColors.textMid),
                ),
                Text(
                  code.isEmpty
                      ? 'الرصيد: \$${formatMoney(ex.balance)}'
                      : 'كود حسابنا: $code · الرصيد: \$${formatMoney(ex.balance)}',
                  key: const ValueKey('expense-balance'),
                  style:
                      const TextStyle(color: AppColors.textLow, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('expense-code'),
                  controller: _code,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'رقم الكود الذي أبلغتك به الشركة',
                    hintText: 'تكتبه بنفسك مع كل عمولة (اختياري)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('expense-amount'),
                  controller: _amount,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'قيمة العمولة \$',
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('expense-note'),
                  controller: _note,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'العمولة خاصة بـ',
                    hintText: 'اكتب ما تخصّ به العمولة',
                    counterText: '',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const ValueKey('expense-error'),
                    style: const TextStyle(color: AppColors.negative),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('expense-save'),
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.negative,
                  ),
                  icon: const FaIcon(FontAwesomeIcons.minus, size: 14),
                  label: Text(_busy ? '...' : 'خصم من الرصيد'),
                ),
                if (today.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'عمولات اليوم على هذا الحساب',
                    style: TextStyle(
                      color: AppColors.textMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final e in today)
                    _ExpenseTile(
                      expense: e,
                      time: _timeFmt.format(e.createdAt),
                      onCancel: _busy ? null : () => _cancel(e),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.time,
    required this.onCancel,
  });

  final AccountExpense expense;
  final String time;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final color = e.isCancelled ? AppColors.cancelled : AppColors.negative;
    return Container(
      key: ValueKey('expense-${e.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.isCancelled
                      ? '\$${formatMoney(e.amount)} ملغاة'
                      : '\$${formatMoney(e.amount)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${e.label} · $time',
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!e.isCancelled)
            TextButton(
              key: ValueKey('expense-cancel-${e.id}'),
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.cancelled,
              ),
              child: const Text('إلغاء'),
            ),
        ],
      ),
    );
  }
}

/// The reason and the administrator's password, to cancel a commission of
/// today. Pops true when it was cancelled.
class _CancelExpenseDialog extends ConsumerStatefulWidget {
  const _CancelExpenseDialog({required this.expense});
  final AccountExpense expense;

  @override
  ConsumerState<_CancelExpenseDialog> createState() =>
      _CancelExpenseDialogState();
}

class _CancelExpenseDialogState extends ConsumerState<_CancelExpenseDialog> {
  final _reason = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().length < 3) {
      setState(() => _error = 'اكتب سبب الإلغاء (3 أحرف على الأقل).');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'اكتب كلمة مرور حسابك.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(accountExpensesRepositoryProvider).cancel(
            widget.expense.id,
            reason: _reason.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;
      switch (r) {
        case CancelDone():
          Navigator.pop(context, true);
        case CancelWrongPassword(:final remaining):
          setState(
            () => _error = 'كلمة المرور غير صحيحة. المحاولات المتبقية: '
                '$remaining',
          );
        case CancelLocked():
          setState(
            () => _error = 'تم قفل الإلغاء 15 دقيقة بعد محاولات خاطئة.',
          );
        case CancelPasswordNotSet():
          setState(
            () => _error = 'حسابك بلا كلمة مرور، اضبطها من الملف الشخصي.',
          );
      }
    } catch (e, st) {
      AppLogger.error('expenses.cancel', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إلغاء العمولة',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cancelled,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\$${formatMoney(e.amount)} — ${e.label}\n'
                'يعود المبلغ إلى رصيد الحساب.',
                style: const TextStyle(color: AppColors.textMid, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('cancel-expense-reason'),
                controller: _reason,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
              ),
              const SizedBox(height: 10),
              PasswordField(controller: _password),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('cancel-expense-error'),
                  style: const TextStyle(color: AppColors.negative),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('رجوع'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('cancel-expense-confirm'),
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.cancelled,
                      ),
                      child: Text(_busy ? '...' : 'إلغاء العمولة'),
                    ),
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
