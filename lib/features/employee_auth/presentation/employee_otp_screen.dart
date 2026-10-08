import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/employee_auth_repository.dart';

/// Second factor after the QR: a 6-digit code is sent by WhatsApp to the phone
/// number the admin registered for the employee, and must be typed here. It
/// proves the person who scanned the QR holds the registered phone.
///
/// Pops `true` once the server accepted the code, `null` if cancelled.
class EmployeeOtpScreen extends ConsumerStatefulWidget {
  const EmployeeOtpScreen({
    super.key,
    required this.token,
    required this.employeeName,
  });

  final String token;
  final String employeeName;

  @override
  ConsumerState<EmployeeOtpScreen> createState() => _EmployeeOtpScreenState();
}

class _EmployeeOtpScreenState extends ConsumerState<EmployeeOtpScreen> {
  static const _cooldown = 45;

  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _phone;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = await ref
          .read(employeeAuthRepositoryProvider)
          .requestOtp(widget.token);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _phone = phone;
      });
      _startCooldown(_cooldown);
    } on OtpRefused catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      if (e.wait != null) _startCooldown(e.wait!);
    } catch (e, st) {
      AppLogger.error('employeeAuth.requestOtp', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final otp = _code.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'أدخل الرمز المكوّن من 6 أرقام');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(employeeAuthRepositoryProvider)
          .verifyOtp(widget.token, otp);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } on OtpRefused catch (e) {
      if (!mounted) return;
      final fatal = e.code == 'too_many_attempts' || e.code == 'otp_expired';
      setState(() {
        _error = e.code == 'invalid_otp' && e.left != null
            ? '${friendlyError(e)} (متبقي ${e.left} محاولة)'
            : friendlyError(e);
        if (e.code != 'otp_expired') _code.clear();
      });
      if (e.code == 'too_many_attempts') {
        // The QR is burned: nothing more can be done on this screen.
        await ref.read(employeeAuthRepositoryProvider).cancelPending();
      }
      if (fatal && e.code != 'otp_expired') _timer?.cancel();
    } catch (e, st) {
      AppLogger.error('employeeAuth.verifyOtp', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    await ref.read(employeeAuthRepositoryProvider).cancelPending();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassCard(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: FaIcon(
                          FontAwesomeIcons.whatsapp,
                          size: 34,
                          color: AppColors.positive,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'رمز التحقق',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textHigh,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _sent
                            ? 'أرسلنا رمزاً من 6 أرقام عبر واتساب إلى '
                                'رقم ${widget.employeeName} المسجَّل لدى المدير '
                                '(${_phone ?? ''}).'
                            : 'جارٍ إرسال الرمز إلى رقمك المسجَّل لدى المدير...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textLow,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _code,
                        enabled: _sent,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        autofocus: true,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 10,
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '••••••',
                        ),
                        onSubmitted: (_) => _verify(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
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
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: (_busy || !_sent) ? null : _verify,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text('تأكيد'),
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
                        onPressed: _busy ? null : _cancel,
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
