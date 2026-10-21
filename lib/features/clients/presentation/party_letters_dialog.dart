import 'package:flutter/material.dart';

import '../../../shared/glass.dart';

/// A small dialog for an employee who was granted "party_letters": only the
/// letters a sender's reference numbers start with (TRC ...). Returns the new
/// letters (empty = remove them), or null when cancelled.
Future<String?> showPartyLettersDialog(
  BuildContext context, {
  required String initial,
  required String party,
}) {
  final controller = TextEditingController(text: initial);
  return showGlassDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('حروف الرقم الإشاري الثابتة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(party, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('letters-field'),
            controller: controller,
            autofocus: true,
            maxLength: 20,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'مثال: TRC',
              helperText: 'تبقى ثابتة في خانة الإشاري ويُكتب الرقم فقط',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('letters-save'),
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}
