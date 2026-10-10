import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/device_email_picker.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/member_auth_repository.dart';

/// "إنشاء حساب جديد / دخول": e-mail + phone (no password, no Google). The
/// e-mail is chosen from the accounts signed in on the phone, so it is an
/// address the person really holds. A 4-digit code is sent by WhatsApp to the
/// phone; entering it creates the account (which then waits for the
/// administrator's approval) or, for an existing member, signs in.
class MemberAuthScreen extends ConsumerStatefulWidget {
  const MemberAuthScreen({super.key});

  @override
  ConsumerState<MemberAuthScreen> createState() => _MemberAuthScreenState();
}

class _MemberAuthScreenState extends ConsumerState<MemberAuthScreen> {
  static const _cooldown = 45;
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phoneRegex = RegExp(r'^09[0-9]{8}$');

  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _emailCode = TextEditingController();

  bool _busy = false;
  bool _needsEmail = false;

  /// The address is chosen from the phone's accounts; typing is only allowed
  /// when the phone has no chooser.
  late bool _manualEmail = !ref.read(deviceEmailPickerProvider).isSupported;
  final _emailFocus = FocusNode();
  bool _sent = false;
  String? _maskedPhone;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _emailFocus.dispose();
    _phone.dispose();
    _code.dispose();
    _emailCode.dispose();
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

  /// Opens the phone's list of e-mail accounts and fills the field with the
  /// one chosen.
  Future<void> _pickEmail() async {
    if (_busy || _sent || _manualEmail) return;
    final pick = await ref.read(deviceEmailPickerProvider).pick();
    if (!mounted) return;
    switch (pick) {
      case EmailPicked(:final email):
        setState(() {
          _email.text = email;
          _error = null;
        });
      case EmailPickCancelled():
        break;
      case EmailPickUnavailable():
        setState(() {
          _manualEmail = true;
          _error = 'تعذّر عرض حسابات الهاتف. اكتب بريدك الإلكتروني.';
        });
        _emailFocus.requestFocus();
    }
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = 'أدخل بريداً إلكترونياً صحيحاً');
      return;
    }
    if (!_phoneRegex.hasMatch(phone)) {
      setState(() => _error = 'رقم الهاتف بالصيغة 09XXXXXXXX (10 أرقام)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent =
          await ref.read(memberAuthRepositoryProvider).requestOtp(email, phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _maskedPhone = sent.phoneMasked;
        _needsEmail = sent.needsEmail;
        _code.clear();
        _emailCode.clear();
      });
      _startCooldown(_cooldown);
    } on MemberRefused catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      if (e.wait != null) _startCooldown(e.wait!);
    } catch (e, st) {
      AppLogger.error('memberAuth.requestOtp', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirms by itself as soon as every required code is complete, so the
  /// user never has to look for a button.
  void _autoVerify() {
    if (_busy || !_sent) return;
    final waReady = _code.text.trim().length == 4;
    final mailReady = !_needsEmail || _emailCode.text.trim().length >= 6;
    if (waReady && mailReady) _verify();
  }

  Future<void> _verify() async {
    final otp = _code.text.trim();
    final emailCode = _emailCode.text.trim();
    if (otp.length != 4) {
      setState(() => _error = 'أدخل رمز واتساب المكوّن من 4 أرقام');
      return;
    }
    if (_needsEmail && emailCode.length < 6) {
      setState(() => _error = 'أدخل رمز البريد الإلكتروني الذي وصلك');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(memberAuthRepositoryProvider)
          .verify(
            _email.text,
            _phone.text,
            otp,
            emailCode: _needsEmail ? emailCode : null,
          );
      // The auth state change moves the user on (pending activation / home).
    } on MemberRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'invalid_otp' && e.left != null
            ? '${friendlyError(e)} (متبقي ${e.left} محاولة)'
            : friendlyError(e);
        if (e.code == 'invalid_otp') _code.clear();
      });
    } catch (e, st) {
      AppLogger.error('memberAuth.verify', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/sign-in');
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/background.jpeg',
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: GlassCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(
                            child: FaIcon(
                              FontAwesomeIcons.userPlus,
                              size: 28,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'إنشاء حساب / دخول',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHigh,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            !_sent
                                ? 'اختر بريدك من حسابات هاتفك وأدخل رقم هاتفك، وسيصلك رمز التحقق على واتساب.'
                                : (_needsEmail
                                    ? 'أدخل رمز البريد ورمز واتساب '
                                        '(${_maskedPhone ?? ''}). تحتاجهما هذه المرة فقط.'
                                    : 'أدخل رمز واتساب الواصل إلى '
                                        '${_maskedPhone ?? ''}.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textLow,
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 22),
                          ..._form(),
                          if (_sent) ..._codeStep(),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.negative.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.negative
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style:
                                    const TextStyle(color: AppColors.negative),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed:
                                _busy ? null : () => context.go('/sign-in'),
                            child: const Text('رجوع'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _form() => [
        TextField(
          key: const ValueKey('member-email'),
          controller: _email,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          // Chosen from the phone's accounts, not typed.
          readOnly: _sent || !_manualEmail,
          showCursor: _manualEmail && !_sent,
          onTap: _pickEmail,
          decoration: InputDecoration(
            labelText: 'البريد الإلكتروني',
            hintText: _manualEmail ? null : 'اضغط لاختيار بريدك من الهاتف',
            prefixIcon:
                const Icon(Icons.alternate_email, color: AppColors.textLow),
            suffixIcon: (_manualEmail || _sent)
                ? null
                : const Icon(Icons.arrow_drop_down, color: AppColors.textLow),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          readOnly: _sent,
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف (واتساب)',
            hintText: '09XXXXXXXX',
            prefixIcon: Icon(Icons.phone, color: AppColors.textLow),
          ),
          onSubmitted: (_) => _send(),
        ),
        if (!_sent) ...[
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy ? _spinner() : const Text('إرسال رمز التحقق'),
          ),
        ],
      ];

  List<Widget> _codeStep() => [
        const SizedBox(height: 18),
        if (_needsEmail) ...[
          TextField(
            controller: _emailCode,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            maxLength: 8,
            textAlign: TextAlign.center,
            autofocus: true,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              labelText: 'رمز البريد الإلكتروني',
              counterText: '',
            ),
            onChanged: (_) => _autoVerify(),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          maxLength: 4,
          textAlign: TextAlign.center,
          autofocus: !_needsEmail,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            labelText: 'رمز واتساب',
            counterText: '',
            hintText: '••••••',
          ),
          onChanged: (_) => _autoVerify(),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 16),
        FilledButton(
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
          child: const Text('تغيير البيانات'),
        ),
      ];

  Widget _spinner() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
      );
}
