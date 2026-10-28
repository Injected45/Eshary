import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';

/// How the dinars of an operation move (migration 0086): through the cash box
/// or the bank. The dinar treasury adds or takes them from that pocket.
const String kLydCash = 'cash';
const String kLydBank = 'bank';

String lydMethodLabel(String? method) => switch (method) {
      kLydBank => 'مصرفي',
      kLydCash => 'نقدًا',
      _ => '—',
    };

/// "الدينار: نقدًا | مصرفي" under the rate fields of the exit and entry
/// screens. [sell]: on an exit the customer pays us, on an entry we pay.
class LydMethodSelector extends StatelessWidget {
  const LydMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.sell,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool sell;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          child: SegmentedButton<String>(
            key: const ValueKey('lyd-method'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: kLydCash,
                label: Text('نقدًا'),
                icon: FaIcon(FontAwesomeIcons.moneyBill1, size: 12),
              ),
              ButtonSegment(
                value: kLydBank,
                label: Text('مصرفي'),
                icon: FaIcon(FontAwesomeIcons.buildingColumns, size: 12),
              ),
            ],
            selected: {value},
            onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
          ),
        ),
      ],
    );
  }
}
