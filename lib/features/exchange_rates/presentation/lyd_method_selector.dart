import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../clients/domain/client.dart';

/// How the dinars of an operation move (migration 0086): through the cash box
/// or the bank. The dinar treasury adds or takes them from that pocket. Since
/// 0091 an operation may also be on credit, wholly or in part: what was not
/// paid becomes the customer's debt (a sale) or ours (a purchase).
const String kLydCash = 'cash';
const String kLydBank = 'bank';
const String kLydCredit = 'credit';
const String kLydPartial = 'partial';

String lydMethodLabel(String? method) => switch (method) {
      kLydBank => 'مصرفي',
      kLydCash => 'نقدًا',
      kLydCredit => 'آجل',
      kLydPartial => 'جزئي',
      _ => '—',
    };

/// What is sent with a save for the payment chosen on the screen.
typedef LydPaymentArgs = ({String? method, double? paid});

/// [choice] cash / bank: paid in full through that pocket ([paid] null tells
/// the database "all of it"). credit: nothing paid now. partial: [partialPaid]
/// paid now through [pocket], the rest on credit.
LydPaymentArgs lydPaymentArgs(
  String choice, {
  double partialPaid = 0,
  String pocket = kLydCash,
}) =>
    switch (choice) {
      kLydCredit => (method: null, paid: 0),
      kLydPartial => (method: pocket, paid: partialPaid),
      _ => (method: choice, paid: null),
    };

/// Whether [choice] leaves part of the dinars on credit.
bool lydOnCredit(String choice) =>
    choice == kLydCredit || choice == kLydPartial;

/// "الدينار: نقدًا | مصرفي | آجل | جزئي" under the rate fields of the sale and
/// purchase screens. [sell]: on a sale the customer pays us, on a purchase we
/// pay. With [allowCredit] the two credit choices appear; for «جزئي» the paid
/// amount ([paidController]) and its pocket ([pocket]) are asked below.
class LydMethodSelector extends StatelessWidget {
  const LydMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.sell,
    this.enabled = true,
    this.allowCredit = false,
    this.paidController,
    this.pocket = kLydCash,
    this.onPocketChanged,
    this.onPaidChanged,
    this.total,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool sell;
  final bool enabled;
  final bool allowCredit;
  final TextEditingController? paidController;
  final String pocket;
  final ValueChanged<String>? onPocketChanged;
  final VoidCallback? onPaidChanged;

  /// The operation's dinars, to show what stays on credit.
  final double? total;

  @override
  Widget build(BuildContext context) {
    final partial = allowCredit && value == kLydPartial;
    final paid = parseMoney(paidController?.text ?? '');
    final rest = total == null
        ? null
        : value == kLydCredit
            ? total!
            : partial
                ? total! - paid
                : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              sell ? 'استلام الدينار' : 'دفع الدينار',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMid,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: SegmentedButton<String>(
                  key: const ValueKey('lyd-method'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                      value: kLydCash,
                      label: Text('نقدًا'),
                      icon: FaIcon(FontAwesomeIcons.moneyBill1, size: 12),
                    ),
                    const ButtonSegment(
                      value: kLydBank,
                      label: Text('مصرفي'),
                      icon: FaIcon(FontAwesomeIcons.buildingColumns, size: 12),
                    ),
                    if (allowCredit) ...const [
                      ButtonSegment(
                        value: kLydCredit,
                        label: Text('آجل'),
                        icon: FaIcon(FontAwesomeIcons.handshake, size: 12),
                      ),
                      ButtonSegment(
                        value: kLydPartial,
                        label: Text('جزئي'),
                        icon:
                            FaIcon(FontAwesomeIcons.circleHalfStroke, size: 12),
                      ),
                    ],
                  ],
                  selected: {value},
                  onSelectionChanged:
                      enabled ? (s) => onChanged(s.first) : null,
                ),
              ),
            ),
          ],
        ),
        if (partial) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('lyd-paid'),
                  controller: paidController,
                  enabled: enabled,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onPaidChanged?.call(),
                  decoration: InputDecoration(
                    labelText:
                        sell ? 'المدفوع الآن (د.ل)' : 'دفعناه الآن (د.ل)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                key: const ValueKey('lyd-paid-pocket'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: kLydCash, label: Text('نقدًا')),
                  ButtonSegment(value: kLydBank, label: Text('مصرفي')),
                ],
                selected: {pocket},
                onSelectionChanged: enabled && onPocketChanged != null
                    ? (s) => onPocketChanged!(s.first)
                    : null,
              ),
            ],
          ),
        ],
        if (rest != null && rest > 0) ...[
          const SizedBox(height: 6),
          Text(
            sell
                ? 'يبقى على العميل: ${formatMoney(rest)} د.ل'
                : 'يبقى علينا للبائع: ${formatMoney(rest)} د.ل',
            key: const ValueKey('lyd-on-credit'),
            style: const TextStyle(fontSize: 12, color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}

/// "العميل": who owes the dinars left on credit (a sale), or whom we owe (a
/// purchase). Tapping it opens the saved customers.
class CreditCustomerField extends StatelessWidget {
  const CreditCustomerField({
    super.key,
    required this.customer,
    required this.sell,
    required this.onPick,
  });

  final Client? customer;
  final bool sell;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final name = c == null
        ? null
        : [c.name, if ((c.company ?? '').trim().isNotEmpty) c.company!.trim()]
            .join(' / ');
    return InkWell(
      key: const ValueKey('credit-customer'),
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: sell ? 'العميل المدين بالدينار' : 'البائع الدائن بالدينار',
          isDense: true,
          suffixIcon: const Icon(Icons.person_search, size: 18),
        ),
        child: Text(
          name ?? 'اختر العميل',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: name == null ? AppColors.textLow : AppColors.textHigh,
          ),
        ),
      ),
    );
  }
}

/// The administrator's choice when a sale on credit takes the customer over
/// his limit (an employee is refused by the database).
Future<bool> confirmOverCreditLimit(
  BuildContext context, {
  required String customer,
  double? limit,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تجاوز حد الدين'),
      content: Text(
        limit == null || limit == 0
            ? 'لم تحدد حدًّا للدين لـ«$customer». هل تريد البيع له بالآجل؟'
            : 'سيتجاوز دين «$customer» الحد المسموح '
                '(${formatMoney(limit)} د.ل). هل تريد المتابعة؟',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('over-limit-ok'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('متابعة'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
