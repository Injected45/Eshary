import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../data/member_invites_repository.dart';
import '../domain/member_invite.dart';
import 'invite_qr_dialog.dart';

final _stamp = DateFormat('yyyy/MM/dd  HH:mm');

/// الإدارة → دعوات المشتركين: create an invitation (name, phone, what the
/// account gets), show / send its QR, and follow who came in. Platform
/// administrator only (the database refuses anyone else).
class MemberInvitesScreen extends ConsumerWidget {
  const MemberInvitesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final made = await showGlassDialog<_NewInvite>(
      context: context,
      builder: (_) => const _NewInviteDialog(),
    );
    if (made == null || !context.mounted) return;
    try {
      final invite = await ref.read(memberInvitesRepositoryProvider).create(
            name: made.name,
            phone: made.phone,
            license: made.license,
            hours: made.hours,
          );
      ref.invalidate(memberInvitesProvider);
      if (!context.mounted) return;
      await showGlassDialog<void>(
        context: context,
        builder: (_) => InviteQrDialog(
          name: made.name,
          phone: made.phone,
          license: made.license,
          invite: invite,
        ),
      );
    } catch (e, st) {
      AppLogger.error('invites.create', e, st);
      if (context.mounted) {
        showTopSnackBar(
          context,
          SnackBar(
            backgroundColor: AppColors.negative,
            content: Text(friendlyError(e)),
          ),
        );
      }
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, MemberInvite i) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء الدعوة؟'),
        content: Text('لن يستطيع ${i.label} الدخول بها بعد الآن.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إلغاء الدعوة'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(memberInvitesRepositoryProvider).revoke(i.id);
      ref.invalidate(memberInvitesProvider);
      if (context.mounted) {
        showTopSnackBar(context, const SnackBar(content: Text('أُلغيت الدعوة')));
      }
    } catch (e, st) {
      AppLogger.error('invites.revoke', e, st);
      if (context.mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memberInvitesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('دعوات المشتركين'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(memberInvitesProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FilledButton.icon(
                key: const ValueKey('new-invite'),
                onPressed: () => _create(context, ref),
                icon: const FaIcon(FontAwesomeIcons.qrcode, size: 15),
                label: const Text('دعوة جديدة'),
              ),
            ),
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                skipError: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      friendlyError(e),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textLow),
                    ),
                  ),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'لا توجد دعوات بعد. أنشئ دعوة، ثم أرسل الـ QR للمشترك '
                          'فيدخل برقم هاتفه ورمز واتساب.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textLow, height: 1.6),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      contentBottomPadding(context),
                    ),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _InviteCard(
                      invite: rows[i],
                      onRevoke: rows[i].status == InviteStatus.pending
                          ? () => _revoke(context, ref, rows[i])
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.invite, required this.onRevoke});

  final MemberInvite invite;
  final VoidCallback? onRevoke;

  Color get _color => switch (invite.status) {
        InviteStatus.pending => AppColors.warning,
        InviteStatus.used => AppColors.positive,
        InviteStatus.revoked => AppColors.textLow,
        InviteStatus.expired => AppColors.negative,
      };

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invite.label,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                key: ValueKey('invite-status-${invite.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  invite.status.label,
                  style: TextStyle(
                    color: _color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            invite.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: const TextStyle(color: AppColors.textMid, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'الصلاحية: ${invite.license.label}',
            style: const TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
          Text(
            invite.status == InviteStatus.used && invite.usedAt != null
                ? 'دخل: ${_stamp.format(invite.usedAt!)}'
                : 'أُنشئت: ${_stamp.format(invite.createdAt)} · '
                    'تنتهي: ${_stamp.format(invite.expiresAt)}',
            style: const TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
          if (onRevoke != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onRevoke,
                child: const Text(
                  'إلغاء الدعوة',
                  style: TextStyle(color: AppColors.negative),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewInvite {
  const _NewInvite(this.name, this.phone, this.license, this.hours);
  final String name;
  final String phone;
  final InviteLicense license;
  final int hours;
}

class _NewInviteDialog extends StatefulWidget {
  const _NewInviteDialog();

  @override
  State<_NewInviteDialog> createState() => _NewInviteDialogState();
}

class _NewInviteDialogState extends State<_NewInviteDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  InviteLicense _license = InviteLicense.trial;
  int _hours = 24;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسم المشترك.');
      return;
    }
    if (!RegExp(r'^09[0-9]{8}$').hasMatch(phone)) {
      setState(() => _error = 'رقم الهاتف بالصيغة 09XXXXXXXX (10 أرقام).');
      return;
    }
    Navigator.of(context).pop(_NewInvite(name, phone, _license, _hours));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'دعوة مشترك جديد',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('invite-name'),
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'اسم المشترك',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('invite-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رقم هاتفه (واتساب)',
                    hintText: '09XXXXXXXX',
                    helperText: 'يصله رمز التحقق على هذا الرقم',
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ماذا يحصل عليه عند الدخول؟',
                  style: TextStyle(color: AppColors.textMid, fontSize: 12),
                ),
                RadioGroup<InviteLicense>(
                  groupValue: _license,
                  onChanged: (v) => setState(() => _license = v ?? _license),
                  child: Column(
                    children: [
                      for (final l in InviteLicense.values)
                        RadioListTile<InviteLicense>(
                          key: ValueKey('invite-license-${l.name}'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: l,
                          title: Text(l.label),
                        ),
                    ],
                  ),
                ),
                DropdownButtonFormField<int>(
                  key: const ValueKey('invite-hours'),
                  initialValue: _hours,
                  decoration: const InputDecoration(labelText: 'مدة صلاحية الدعوة'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('ساعة واحدة')),
                    DropdownMenuItem(value: 6, child: Text('6 ساعات')),
                    DropdownMenuItem(value: 24, child: Text('24 ساعة')),
                    DropdownMenuItem(value: 72, child: Text('3 أيام')),
                    DropdownMenuItem(value: 168, child: Text('7 أيام')),
                  ],
                  onChanged: (v) => setState(() => _hours = v ?? _hours),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.negative, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('invite-create'),
                        onPressed: _submit,
                        child: const Text('إنشاء'),
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
