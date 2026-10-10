import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../data/member_auth_repository.dart' show MemberRefused;
import 'auth_card.dart';

/// "Type your phone number → a 4-digit code arrives on WhatsApp → type it".
/// Used by the invitation screen and by sign-in with a phone number. The two
/// calls are supplied by the screen:
///
///   [request]  sends the code, returns the masked phone it went to;
///   [confirm]  checks the code and signs in (the router moves on by itself).
///
/// It keeps the 45-second wait before a resend, confirms by itself as soon as
/// the 4th digit is typed, and shows the server's refusals in Arabic (with the
/// tries left when the server says so).
class PhoneCodeStep extends ConsumerStatefulWidget {
  const PhoneCodeStep({
    super.key,
    required this.request,
    required this.confirm,
    this.phoneHint = 'رقم الهاتف (واتساب)',
    this.sendLabel = 'إرسال رمز التحقق',
  });

  final Future<String> Function(String phone) request;
  final Future<void> Function(String phone, String otp) confirm;
  final String phoneHint;
  final String sendLabel;

  @override
  ConsumerState<PhoneCodeStep> createState() => _PhoneCodeStepState();
}

class _PhoneCodeStepState extends ConsumerState<PhoneCodeStep> {
  static const _cooldown = 45;
  static final _phoneRegex = RegExp(r'^09[0-9]{8}$');

  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _masked;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  String _message(Object e) {
    if (e is MemberRefused) {
      if (e.code == 'invalid_otp' && e.left != null) {
        return '${friendlyError(e)} (متبقي ${e.left} محاولة)';
      }
      if (e.code == 'phone_mismatch' && e.left != null) {
        return '${friendlyError(e)} (متبقي ${e.left} محاولة)';
      }
    }
    return friendlyError(e);
  }

  Future<void> _send() async {
    final phone = _phone.text.trim();
    if (!_phoneRegex.hasMatch(phone)) {
      setState(() => _error = 'رقم الهاتف بالصيغة 09XXXXXXXX (10 أرقام)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final masked = await widget.request(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _masked = masked;
        _code.clear();
      });
      _startCooldown(_cooldown);
    } on MemberRefused catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(e));
      if (e.wait != null) _startCooldown(e.wait!);
    } catch (e, st) {
      AppLogger.error('phoneCode.request', e, st);
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final otp = _code.text.trim();
    if (otp.length != 4) {
      setState(() => _error = 'أدخل رمز واتساب المكوّن من 4 أرقام');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.confirm(_phone.text.trim(), otp);
      // The session that follows moves the router.
    } catch (e, st) {
      AppLogger.error('phoneCode.confirm', e, st);
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        if (e is MemberRefused && e.code == 'invalid_otp') _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('phone-field'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          readOnly: _sent,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          decoration: InputDecoration(
            labelText: widget.phoneHint,
            hintText: '09XXXXXXXX',
            prefixIcon: const Icon(Icons.phone, color: AppColors.textLow),
          ),
          onSubmitted: (_) => _sent ? null : _send(),
        ),
        if (!_sent) ...[
          const SizedBox(height: 18),
          FilledButton(
            key: const ValueKey('send-code'),
            onPressed: _busy ? null : _send,
            child: _busy ? _spinner() : Text(widget.sendLabel),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Text(
            'أُرسل رمز واتساب إلى ${_masked ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('code-field'),
            controller: _code,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            maxLength: 4,
            textAlign: TextAlign.center,
            autofocus: true,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              labelText: 'رمز واتساب',
              counterText: '',
            ),
            // Confirms by itself once the 4 digits are in.
            onChanged: (v) {
              if (v.trim().length == 4 && !_busy) _verify();
            },
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('confirm-code'),
            onPressed: _busy ? null : _verify,
            child: _busy ? _spinner() : const Text('تأكيد'),
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
          AuthError(_error!),
        ],
      ],
    );
  }

  Widget _spinner() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
      );
}
