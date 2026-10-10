import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// Country calling codes offered in the phone field (the first is the default).
const kCountryCodes = <(String, String)>[
  ('+218', 'ليبيا'),
  ('+20', 'مصر'),
  ('+216', 'تونس'),
  ('+213', 'الجزائر'),
  ('+212', 'المغرب'),
  ('+249', 'السودان'),
  ('+966', 'السعودية'),
  ('+971', 'الإمارات'),
  ('+974', 'قطر'),
  ('+965', 'الكويت'),
  ('+962', 'الأردن'),
  ('+90', 'تركيا'),
];

/// Builds the international number from a calling code and what was typed:
/// spaces and a leading zero are dropped ("0912345678" with +218 gives
/// "+218912345678"). The database checks the result (E.164) again.
String composePhone(String code, String typed) {
  final digits =
      typed.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');
  return digits.isEmpty ? '' : '$code$digits';
}

/// Country code + number, always shown left-to-right. [onChanged] reports the
/// composed international number ('' while nothing is typed).
class PhoneInput extends StatefulWidget {
  const PhoneInput({
    super.key,
    required this.onChanged,
    this.enabled = true,
    this.label = 'رقم الهاتف (واتساب)',
  });

  final ValueChanged<String> onChanged;
  final bool enabled;
  final String label;

  @override
  State<PhoneInput> createState() => _PhoneInputState();
}

class _PhoneInputState extends State<PhoneInput> {
  String _code = kCountryCodes.first.$1;
  final _number = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(composePhone(_code, _number.text));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: DropdownButtonFormField<String>(
              key: const ValueKey('country-code'),
              initialValue: _code,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الدولة'),
              items: [
                for (final (code, name) in kCountryCodes)
                  DropdownMenuItem(
                    value: code,
                    child: Text(
                      '$code $name',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: widget.enabled
                  ? (v) {
                      setState(() => _code = v ?? _code);
                      _emit();
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey('phone-number'),
              controller: _number,
              enabled: widget.enabled,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: InputDecoration(
                labelText: widget.label,
                prefixIcon: const Icon(Icons.phone, color: AppColors.textLow),
              ),
              onChanged: (_) => _emit(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The six-digit WhatsApp code field.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.onComplete,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onComplete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('code-field'),
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: 8,
        fontFamily: 'monospace',
      ),
      decoration: const InputDecoration(
        labelText: 'رمز واتساب (6 أرقام)',
        counterText: '',
      ),
      onChanged: (v) {
        if (v.trim().length == 6) onComplete();
      },
      onSubmitted: (_) => onComplete(),
    );
  }
}
