import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/auth_repository.dart';
import '../data/member_auth_repository.dart' show MemberRefused;
import '../data/phone_link_repository.dart';

/// Last step of "إنشاء حساب جديد": the person has chosen a Google account (which
/// proves the e-mail), so only the phone is left. They type it, a 4-digit code
/// arrives on WhatsApp, and entering it links the phone. The router shows this
/// screen for as long as the account has no phone (see [needsPhoneProvider]).
class LinkPhoneScreen extends ConsumerStatefulWidget {
  const LinkPhoneScreen({super.key});

  @override
  ConsumerState<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends ConsumerState<LinkPhoneScreen> {
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
      final masked = await ref.read(phoneLinkRepositoryProvider).requestCode(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _masked = masked;
        _code.clear();
      });
      _startCooldown(_cooldown);
    } on MemberRefused catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      if (e.wait != null) _startCooldown(e.wait!);
    } catch (e, st) {
      AppLogger.error('linkPhone.request', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
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
      await ref.read(phoneLinkRepositoryProvider).confirm(_phone.text, otp);
      // The router leaves this screen once the account no longer needs a phone.
      ref.invalidate(needsPhoneProvider);
    } on MemberRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'invalid_otp' && e.left != null
            ? '${friendlyError(e)} (متبقي ${e.left} محاولة)'
            : friendlyError(e);
        if (e.code == 'invalid_otp') _code.clear();
      });
    } catch (e, st) {
      AppLogger.error('linkPhone.confirm', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useAnotherAccount() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (e, st) {
      AppLogger.error('linkPhone.signOut', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentSessionProvider)?.user.email ?? '';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background.jpeg', fit: BoxFit.cover),
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
                            FontAwesomeIcons.whatsapp,
                            size: 30,
                            color: AppColors.positive,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'تأكيد رقم الهاتف',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textHigh,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _sent
                              ? 'أدخل رمز واتساب الواصل إلى ${_masked ?? ''}.'
                              : 'أدخل رقم هاتفك، وسيصلك رمز التحقق على واتساب.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textLow,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.glassFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_outlined,
                                  size: 18,
                                  color: AppColors.positive,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    email,
                                    key: const ValueKey('link-email'),
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      color: AppColors.textHigh,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          readOnly: _sent,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف (واتساب)',
                            hintText: '09XXXXXXXX',
                            prefixIcon: Icon(Icons.phone, color: AppColors.textLow),
                          ),
                          onSubmitted: (_) => _sent ? null : _send(),
                        ),
                        if (!_sent) ...[
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _busy ? null : _send,
                            child: _busy ? _spinner() : const Text('إرسال رمز التحقق'),
                          ),
                        ] else ...[
                          const SizedBox(height: 14),
                          TextField(
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
                            onPressed: _busy ? null : _verify,
                            child: _busy ? _spinner() : const Text('تأكيد'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: (_busy || _wait > 0) ? null : _send,
                            child: Text(
                              _wait > 0
                                  ? 'إعادة الإرسال بعد $_wait ث'
                                  : 'إعادة إرسال الرمز',
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.negative.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.negative.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.negative),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _useAnotherAccount,
                          child: const Text('استخدام حساب آخر'),
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
    );
  }

  Widget _spinner() => const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
      );
}
