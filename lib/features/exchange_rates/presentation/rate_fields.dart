import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../domain/exchange_rates.dart';
import 'exchange_rates_providers.dart';

/// The rate an operation is saved with: the typed one, or — for an employee
/// who may not edit it — the administrator's last rate of that kind ([sell]
/// for an exit, buy for an entry). 0 when there is none.
double effectiveRate(
  TextEditingController controller,
  ExchangeRates? rates, {
  required bool sell,
}) {
  if (rates != null && !rates.canEditFor(sell: sell)) {
    return (sell ? rates.sell : rates.buy) ?? 0;
  }
  return parseRate(controller.text);
}

/// "سعر الصرف" and "الإجمالي بالدينار" side by side, under the dollar amount of
/// the exit and the entry screens (migration 0081). The dinars are a preview
/// computed like the database computes them; the stored figure comes from it.
class RateFields extends StatelessWidget {
  const RateFields({
    super.key,
    required this.controller,
    required this.usd,
    required this.rates,
    required this.sell,
    required this.enabled,
    required this.onDisabledTap,
    required this.height,
    required this.textStyle,
    this.accountCost,
    this.accountBalance,
  });

  final TextEditingController controller;
  final double usd;
  final ExchangeRates? rates;

  /// True on the exit screen (sell rate), false on the entry screen (buy).
  final bool sell;

  /// The same condition as the dollar field: the account is chosen.
  final bool enabled;
  final VoidCallback onDisabledTap;
  final double height;
  final TextStyle textStyle;

  /// The administrator only (an employee never gets it): the account's cost
  /// price (migration 0082). On an exit it is the break-even rate; on an entry
  /// the new cost after it is shown, from [accountBalance].
  final double? accountCost;
  final double? accountBalance;

  double? get _last => sell ? rates?.sell : rates?.buy;
  bool get _locked => rates != null && !rates!.canEditFor(sell: sell);

  @override
  Widget build(BuildContext context) {
    final rate = effectiveRate(controller, rates, sell: sell);
    final lyd = usd > 0 && rate > 0 ? lydFor(usd, rate) : null;
    final last = _last;
    final warn = !_locked && rate > 0 && rateLooksWrong(rate, last);

    String? note;
    Color noteColor = AppColors.textLow;
    if (_locked && last == null) {
      note = sell
          ? 'لم يحدد المدير سعر البيع بعد. تواصل مع المدير.'
          : 'لم يحدد المدير سعر الشراء بعد. تواصل مع المدير.';
      noteColor = AppColors.negative;
    } else if (_locked) {
      note = 'سعر المدير، لا يمكن تعديله.';
    } else if (rate > 0 && !rateInRange(rate)) {
      note = 'سعر غير معقول: يجب أن يكون بين 1 و 100 دينار للدولار.';
      noteColor = AppColors.negative;
    } else if (warn) {
      note = 'يختلف كثيرًا عن آخر سعر (${formatRate(last!)}). تأكد منه.';
      noteColor = AppColors.warning;
    }

    final rateBox = !enabled
        ? _disabled('اختر الحساب أولاً')
        : _locked
            ? _readOnly(last == null ? '—' : formatRate(last))
            : TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.center,
                textAlign: TextAlign.center,
                style: textStyle.copyWith(fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: last == null
                      ? 'مثال 7.25'
                      : 'آخر سعر ${formatRate(last)}',
                  enabledBorder: warn
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: AppColors.warning),
                        )
                      : null,
                ),
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labeled(
                sell ? 'سعر البيع (د.ل لكل \$)' : 'سعر الشراء (د.ل لكل \$)',
                rateBox,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labeled(
                'الإجمالي بالدينار (LYD)',
                enabled
                    ? _readOnly(
                        lyd == null ? '' : formatMoney(lyd),
                        hint: 'يظهر تلقائياً',
                      )
                    : _disabled('يظهر تلقائياً'),
              ),
            ),
          ],
        ),
        if (enabled && note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: TextStyle(fontSize: 12, color: noteColor)),
          ),
        if (enabled && _costNote(rate) != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _costNote(rate)!.$1,
              key: const ValueKey('cost-note'),
              style: TextStyle(fontSize: 12, color: _costNote(rate)!.$2),
            ),
          ),
      ],
    );
  }

  /// The administrator's line about the cost: on an exit the break-even and,
  /// below it, the loss; on an entry the cost after this buy.
  (String, Color)? _costNote(double rate) {
    final cost = accountCost;
    if (cost == null || rate <= 0 || usd <= 0) return null;
    if (sell) {
      if (rate < cost) {
        final loss = lydFor(usd, cost) - lydFor(usd, rate);
        return (
          'أقل من سعر التكلفة ${cost.toStringAsFixed(4)}: خسارة '
              '${formatMoney(loss)} د.ل',
          AppColors.negative,
        );
      }
      return (
        'سعر التكلفة (التعادل) ${cost.toStringAsFixed(4)}',
        AppColors.textLow,
      );
    }
    final next = costAfterBuy(
      balance: accountBalance ?? 0,
      cost: cost,
      usd: usd,
      rate: rate,
    );
    return (
      'التكلفة بعد هذا الشراء: ${cost.toStringAsFixed(4)} ← '
          '${next.toStringAsFixed(4)}',
      AppColors.textLow,
    );
  }

  Widget _labeled(String label, Widget box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: height, child: box),
        ],
      );

  /// A box that looks like the other fields but takes no typing.
  Widget _readOnly(String text, {String? hint, bool enabled = true}) =>
      InputDecorator(
        expands: true,
        isEmpty: text.isEmpty,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(hintText: hint, enabled: enabled),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: textStyle.copyWith(fontWeight: FontWeight.w700),
        ),
      );

  Widget _disabled(String hint) => GestureDetector(
        onTap: onDisabledTap,
        child: Opacity(
          opacity: 0.55,
          child: _readOnly('', hint: hint, enabled: false),
        ),
      );
}

/// The account's cost after buying [usd] at [rate], as the database averages
/// it (migration 0082): (B × C + q × r) ÷ (B + q); an empty account starts at
/// the rate. A preview: the stored cost comes from the database.
double costAfterBuy({
  required double balance,
  required double cost,
  required double usd,
  required double rate,
}) {
  final q = (usd * 100).round() / 100;
  if (balance <= 0) return rate;
  return (balance * cost + q * rate) / (balance + q);
}

/// Asks before selling below the account's cost. True = sell anyway.
Future<bool> confirmBelowCost(
  BuildContext context, {
  required double rate,
  required double cost,
  required double loss,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('بيع بخسارة'),
      content: Text(
        'سعر البيع ${formatRate(rate)} أقل من سعر تكلفة الدولار في هذا الحساب '
        '(${cost.toStringAsFixed(4)}). الخسارة ${formatMoney(loss)} د.ل. '
        'هل تريد المتابعة؟',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('تعديل السعر'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('نعم، بع بخسارة'),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Asks before saving at a rate far from the last one. True = save.
Future<bool> confirmUnusualRate(
  BuildContext context, {
  required double rate,
  required double last,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تأكيد سعر الصرف'),
      content: Text(
        'السعر ${formatRate(rate)} يختلف كثيرًا عن آخر سعر '
        '(${formatRate(last)}). هل هو صحيح؟',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('تعديل السعر'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('نعم، صحيح'),
        ),
      ],
    ),
  );
  return res ?? false;
}
