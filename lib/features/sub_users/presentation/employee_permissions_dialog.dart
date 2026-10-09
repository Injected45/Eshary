import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/sub_users_repository.dart';
import '../domain/employee_permissions.dart';
import '../domain/sub_user.dart';
import 'sub_users_providers.dart';
import '../../../shared/top_message.dart';

/// The admin's checklist of what one employee may do. Saving writes the list
/// through `admin_set_employee_permissions`; the database enforces it, and it
/// takes effect on the employee's phone within seconds. A new employee starts
/// with nothing ticked.
class EmployeePermissionsDialog extends ConsumerStatefulWidget {
  const EmployeePermissionsDialog({super.key, required this.user});

  final SubUser user;

  @override
  ConsumerState<EmployeePermissionsDialog> createState() =>
      _EmployeePermissionsDialogState();
}

class _EmployeePermissionsDialogState
    extends ConsumerState<EmployeePermissionsDialog> {
  // Keys that were retired (the old daily-close permissions) may still be
  // stored for this employee; they are neither shown nor sent back.
  late final Set<String> _selected = {
    for (final p in widget.user.permissions)
      if (kEmployeePermissions.any((d) => d.key == p)) p,
  };
  bool _busy = false;

  bool get _changed {
    final original = {
      for (final p in widget.user.permissions)
        if (kEmployeePermissions.any((d) => d.key == p)) p,
    };
    return original.length != _selected.length ||
        !original.containsAll(_selected);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(subUsersRepositoryProvider)
          .setPermissions(widget.user.id, _selected.toList());
      ref.invalidate(subUsersListProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      AppLogger.error('subUsers.setPermissions', e, st);
      if (!mounted) return;
      setState(() => _busy = false);
      showTopSnackBar(
        context,
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<EmployeePermission>>{};
    for (final p in kEmployeePermissions) {
      groups.putIfAbsent(p.group, () => []).add(p);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.userShield,
                    color: AppColors.accent,
                    size: 16,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'صلاحيات ${widget.user.employeeName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'ما لم تُمنح لا تظهر للموظف. تُحفظ فوراً ويمكنك سحبها في أي وقت.',
                style: TextStyle(
                  color: AppColors.textLow,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final p in entry.value)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _selected.contains(p.key),
                            onChanged: _busy
                                ? null
                                : (on) => setState(() {
                                      if (on) {
                                        _selected.add(p.key);
                                      } else {
                                        _selected.remove(p.key);
                                      }
                                    }),
                            title: Text(
                              p.label,
                              style: const TextStyle(
                                color: AppColors.textHigh,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              p.description,
                              style: const TextStyle(
                                color: AppColors.textLow,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              if (_selected.length ==
                                  kEmployeePermissions.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(
                                    kEmployeePermissions.map((p) => p.key),
                                  );
                              }
                            }),
                    child: Text(
                      _selected.length == kEmployeePermissions.length
                          ? 'إلغاء الكل'
                          : 'تحديد الكل',
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_busy || !_changed) ? null : _save,
                    child: Text(_busy ? '...' : 'حفظ'),
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
