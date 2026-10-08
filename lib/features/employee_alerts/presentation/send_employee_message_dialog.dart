import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../sub_users/domain/sub_user.dart';
import '../../sub_users/presentation/sub_users_providers.dart';
import '../data/employee_alerts_repository.dart';
import 'employee_alerts_providers.dart';

Future<void> showSendEmployeeMessageDialog(BuildContext context) {
  return showGlassDialog<void>(
    context: context,
    builder: (_) => const SendEmployeeMessageDialog(),
  );
}

/// Compose a message to chosen employees, or to all active ones.
class SendEmployeeMessageDialog extends ConsumerStatefulWidget {
  const SendEmployeeMessageDialog({super.key});

  @override
  ConsumerState<SendEmployeeMessageDialog> createState() =>
      _SendEmployeeMessageDialogState();
}

class _SendEmployeeMessageDialogState
    extends ConsumerState<SendEmployeeMessageDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final Set<String> _picked = {};
  bool _toAll = true;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send(List<SubUser> active) async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      _snack('اكتب نص الرسالة أولاً.');
      return;
    }
    if (!_toAll && _picked.isEmpty) {
      _snack('اختر موظفاً واحداً على الأقل.');
      return;
    }
    setState(() => _busy = true);
    try {
      final count = await ref.read(employeeAlertsRepositoryProvider).sendMessage(
            subUserIds: _toAll ? null : _picked.toList(),
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            body: body,
          );
      ref.invalidate(sentMessagesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال الرسالة إلى $count موظف.')),
      );
    } catch (e, st) {
      AppLogger.error('alerts.sendMessage', e, st);
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(friendlyError(e));
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(subUsersListProvider).valueOrNull ?? const [];
    final active = employees
        .where((e) => e.status == SubUserStatus.active)
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إرسال رسالة للموظفين',
                style: TextStyle(
                  color: AppColors.textHigh,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('كل الموظفين')),
                  ButtonSegment(value: false, label: Text('موظفون محددون')),
                ],
                selected: {_toAll},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _toAll = s.first),
              ),
              if (!_toAll) ...[
                const SizedBox(height: 8),
                Flexible(
                  child: active.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'لا يوجد موظفون فعّالون.',
                            style: TextStyle(color: AppColors.textLow),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final e in active)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: _picked.contains(e.id),
                                title: Text(e.employeeName),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() {
                                          if (v ?? false) {
                                            _picked.add(e.id);
                                          } else {
                                            _picked.remove(e.id);
                                          }
                                        }),
                              ),
                          ],
                        ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'ستصل إلى ${active.length} موظف فعّال.',
                    style: const TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                enabled: !_busy,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياري)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _body,
                enabled: !_busy,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'نص الرسالة'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : () => _send(active),
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('إرسال'),
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
