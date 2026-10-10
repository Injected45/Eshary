import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../../auth/data/member_auth_repository.dart';
import '../../auth/presentation/auth_card.dart';
import '../../auth/presentation/phone_code_step.dart';
import '../domain/member_invite.dart';
import 'invite_scan_screen.dart';

/// "لدي دعوة": the invited person scans the administrator's QR (or pastes the
/// text they were sent), types their phone number, and enters the code that
/// arrives on WhatsApp at the number the administrator registered. The account
/// is then created with the licence the administrator chose.
class InviteRedeemScreen extends ConsumerStatefulWidget {
  const InviteRedeemScreen({super.key});

  @override
  ConsumerState<InviteRedeemScreen> createState() => _InviteRedeemScreenState();
}

class _InviteRedeemScreenState extends ConsumerState<InviteRedeemScreen> {
  final _paste = TextEditingController();
  String? _token;
  InvitePreview? _preview;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const InviteScanScreen()),
    );
    if (token != null && mounted) await _open(token);
  }

  Future<void> _fromText() async {
    final token = inviteTokenFromText(_paste.text);
    if (token == null) {
      setState(() => _error = 'لم أجد رمز دعوة في النص. الصق الرسالة كاملة.');
      return;
    }
    await _open(token);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || !mounted) return;
    setState(() => _paste.text = data!.text!);
    final token = inviteTokenFromText(data!.text!);
    if (token != null) await _open(token);
  }

  Future<void> _open(String token) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview =
          await ref.read(memberAuthRepositoryProvider).invitePreview(token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _preview = preview;
      });
    } catch (e, st) {
      AppLogger.error('invite.preview', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(memberAuthRepositoryProvider);
    final token = _token;
    final preview = _preview;
    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(
            child: FaIcon(
              FontAwesomeIcons.qrcode,
              size: 28,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'لدي دعوة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            preview == null
                ? 'امسح الـ QR الذي أرسله لك المدير، أو الصق رسالة الدعوة.'
                : 'مرحباً ${preview.name}. اكتب رقم هاتفك المسجّل '
                    '(${preview.phoneMasked}) فيصلك رمز التحقق على واتساب.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textLow,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          if (token == null || preview == null) ...[
            FilledButton.icon(
              key: const ValueKey('scan-invite'),
              onPressed: _busy ? null : _scan,
              icon: const FaIcon(FontAwesomeIcons.camera, size: 15),
              label: const Text('مسح QR'),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('paste-field'),
              controller: _paste,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'أو الصق رسالة الدعوة / الرمز',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('paste-clipboard'),
                    onPressed: _busy ? null : _pasteFromClipboard,
                    child: const Text('لصق'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('continue-invite'),
                    onPressed: _busy ? null : _fromText,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text('متابعة'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AuthError(_error!),
            ],
          ] else
            PhoneCodeStep(
              phoneHint: 'رقم هاتفك المسجّل (واتساب)',
              request: (phone) => repo.inviteRequestOtp(token, phone),
              confirm: (phone, otp) => repo.redeemInvite(token, phone, otp),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/sign-in'),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}
