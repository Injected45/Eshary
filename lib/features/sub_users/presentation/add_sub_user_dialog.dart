import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../branches/presentation/add_branch_dialog.dart';
import '../../branches/presentation/branches_providers.dart';
import '../data/sub_users_repository.dart';
import '../domain/sub_user.dart';

/// Returned from [AddSubUserDialog] on success — bundles the new row id,
/// the one-time plain code, and the labels needed to render the
/// [CodeDisplayDialog] right after.
class AddSubUserResult {
  const AddSubUserResult({
    required this.id,
    required this.plainCode,
    required this.name,
    required this.phone,
  });
  final String id;
  final String plainCode;
  final String name;
  final String phone;
}

class AddSubUserDialog extends ConsumerStatefulWidget {
  const AddSubUserDialog({super.key});

  @override
  ConsumerState<AddSubUserDialog> createState() => _AddSubUserDialogState();
}

class _AddSubUserDialogState extends ConsumerState<AddSubUserDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _branchId;
  SubUserRole _role = SubUserRole.both;
  bool _busy = false;
  String? _phoneError;
  String? _nameError;

  // Libyan mobile: exactly 10 digits starting with 09 (matches the DB
  // check constraint in 0019_sub_users.sql).
  static final _libyanPhoneRegex = RegExp(r'^09[0-9]{8}$');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'اسم الموظف مطلوب' : null;
      _phoneError = _libyanPhoneRegex.hasMatch(phone)
          ? null
          : 'الصيغة: 09XXXXXXXX (10 أرقام)';
    });
    if (_nameError != null || _phoneError != null) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(subUsersRepositoryProvider).create(
            employeeName: name,
            phoneNumber: phone,
            role: _role,
            branchId: _branchId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(
        AddSubUserResult(
          id: result.id,
          plainCode: result.plainCode,
          name: name,
          phone: phone,
        ),
      );
    } catch (e, st) {
      AppLogger.error('subUsers.create', e, st);
      if (!mounted) return;
      await _showErrorDialog(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Surfaces both the friendly Arabic message and the raw server error so
  /// the admin can copy the technical detail when reporting a problem.
  Future<void> _showErrorDialog(Object e) async {
    final raw = e.toString();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('فشل حفظ الموظف'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                friendlyError(e),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 14),
              const Text(
                'تفاصيل تقنية:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                raw,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: raw));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ الخطأ'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const FaIcon(FontAwesomeIcons.copy, size: 12),
            label: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.userPlus,
                      color: AppColors.accent,
                      size: 16,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'إضافة موظف جديد',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Label('اسم الموظف'),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    hintText: 'الاسم الكامل',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 12),
                const _Label('رقم الهاتف'),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '09XXXXXXXX',
                    errorText: _phoneError,
                  ),
                ),
                const SizedBox(height: 12),
                const _Label('الفرع (اختياري)'),
                _BranchPicker(
                  selected: _branchId,
                  onChanged: (id) => setState(() => _branchId = id),
                ),
                const SizedBox(height: 16),
                const _Label('نوع الصلاحية'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: SubUserRole.values
                      .map(
                        (r) => ChoiceChip(
                          label: Text(subUserRoleLabel(r)),
                          selected: _role == r,
                          onSelected: (_) => setState(() => _role = r),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? '...' : 'حفظ'),
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textMid,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Branch dropdown. Resolves the live branches list and re-renders on
/// every invalidation so newly-created branches appear immediately.
/// Shows an inline "إضافة فرع جديد" CTA when the user has no branches yet.
class _BranchPicker extends ConsumerWidget {
  const _BranchPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(branchesListProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
      data: (branches) {
        if (branches.isEmpty) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                showGlassDialog<void>(
                  context: context,
                  builder: (_) => AddBranchDialog(
                    onSaved: () => ref.invalidate(branchesListProvider),
                  ),
                );
              },
              icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
              label: const Text('إضافة فرع جديد'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          );
        }
        // Reset selected if the branch was deleted out from under us.
        final liveValue =
            branches.any((b) => b.id == selected) ? selected : null;
        if (liveValue == null && selected != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onChanged(null);
          });
        }
        return DropdownButtonFormField<String>(
          value: liveValue,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'اختر الفرع',
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('بدون فرع'),
            ),
            for (final b in branches)
              DropdownMenuItem<String>(
                value: b.id,
                child: Text(b.name),
              ),
          ],
          onChanged: onChanged,
        );
      },
    );
  }
}
