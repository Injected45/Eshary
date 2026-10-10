import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../../auth/presentation/auth_card.dart';
import '../data/trial_repository.dart';
import '../domain/trial_models.dart';
import 'phone_input.dart';

/// "دخول حسابي": a subscriber who already has an account (new device, new
/// install) types the phone and the six-digit WhatsApp code. Signing in never
/// touches the subscription: a reinstall does not restart a trial.
class TrialLoginScreen extends ConsumerStatefulWidget {
  const TrialLoginScreen({super.key});

  @override
  ConsumerState<TrialLoginScreen> createState() => _TrialLoginScreenState();
}

class _TrialLoginScreenState extends ConsumerState<TrialLoginScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  String _phone = '';
  bool _sent = false;
  bool _busy = false;
  String? _error;
  int? _left;
  int _wait = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startWait(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_phone)) {
      setState(() => _error = 'اكتب رقم الهاتف مع اختيار رمز الدولة.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _left = null;
    });
    try {
      final wait = await ref.read(trialRepositoryProvider).loginRequest(_phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code.clear();
      });
      _startWait(wait);
    } on TrialRefused catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      if (e.wait != null) _startWait(e.wait!);
    } catch (e, st) {
      AppLogger.error('trial.loginRequest', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'أدخل رمز واتساب المكوّن من 6 أرقام.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _left = null;
    });
    try {
      await ref.read(trialRepositoryProvider).loginVerify(_phone, code);
      // The session that follows moves the router.
    } on TrialRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _left = e.left;
        if (e.code == 'invalid_code') _code.clear();
      });
    } catch (e, st) {
      AppLogger.error('trial.loginVerify', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(
            child: FaIcon(
              FontAwesomeIcons.whatsapp,
              size: 30,
              color: AppColors.positive,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'دخول حسابي',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'اكتب رقمك المسجّل، فيصلك رمز التحقق على واتساب.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textLow,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          PhoneInput(enabled: !_sent && !_busy, onChanged: (v) => _phone = v),
          if (!_sent) ...[
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('send-code'),
              onPressed: _busy ? null : _send,
              child: const Text('إرسال رمز التحقق'),
            ),
          ] else ...[
            const SizedBox(height: 14),
            CodeField(
              controller: _code,
              enabled: !_busy,
              onComplete: () {
                if (!_busy) _verify();
              },
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey('confirm-code'),
              onPressed: _busy ? null : _verify,
              child: const Text('تأكيد'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: (_busy || _wait > 0) ? null : _send,
              child: Text(
                _wait > 0 ? 'إعادة الإرسال بعد $_wait ث' : 'إعادة إرسال الرمز',
              ),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _sent = false;
                        _error = null;
                        _timer?.cancel();
                      }),
              child: const Text('تغيير الرقم'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            AuthError(
                _left == null ? _error! : '$_error (متبقي $_left محاولة)'),
          ],
          TextButton(
            onPressed: _busy ? null : () => context.go('/sign-in'),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}
