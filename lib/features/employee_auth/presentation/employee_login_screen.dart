import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/employee_auth_repository.dart';
import 'employee_auth_providers.dart';
import 'employee_otp_screen.dart';
import 'employee_qr_scan_screen.dart';

/// "تسجيل دخول موظف": two ways in.
///   - مسح QR: the QR the admin issued, confirmed with a code sent by
///     WhatsApp to the phone the admin registered for the employee.
///   - كود الدخول المؤقت: the phone number + 6-digit code the admin gave.
class EmployeeLoginScreen extends ConsumerStatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  ConsumerState<EmployeeLoginScreen> createState() =>
      _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends ConsumerState<EmployeeLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _showCodeForm = false;
  String? _error;

  // Same Libyan format as add_sub_user_dialog (matches the DB check).
  static final _libyanPhoneRegex = RegExp(r'^09[0-9]{8}$');

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<ScannedEmployeeQr>(
      MaterialPageRoute(builder: (_) => const EmployeeQrScanScreen()),
    );
    if (scanned == null || !mounted) return;

    // Second factor: a code sent by WhatsApp to the phone the admin registered.
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EmployeeOtpScreen(
          token: scanned.token,
          employeeName: scanned.employeeName,
        ),
      ),
    );
    if (verified != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(employeeAuthRepositoryProvider)
          .signInWithQr(token: scanned.token);
      ref.invalidate(currentEmployeeProvider);
      if (!mounted) return;
      context.go('/employee-home');
    } catch (e, st) {
      AppLogger.error('employeeAuth.signInWithQr', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();

    if (!_libyanPhoneRegex.hasMatch(phone)) {
      setState(() => _error = 'الصيغة: 09XXXXXXXX (10 أرقام)');
      return;
    }
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'كود الدخول يجب أن يكون 6 أرقام');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(employeeAuthRepositoryProvider)
          .signIn(phone: phone, code: code);
      // Refresh provider so router + home screen see the new identity.
      ref.invalidate(currentEmployeeProvider);
      if (!mounted) return;
      context.go('/employee-home');
    } catch (e, st) {
      AppLogger.error('employeeAuth.signIn', e, st);
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
                              FontAwesomeIcons.userTie,
                              size: 28,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'تسجيل دخول موظف',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textHigh,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'ادخل بكود الدخول المؤقت الذي زوّدك به المدير، '
                            'أو امسح الـ QR الذي أصدره لك.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textLow,
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _busy ? null : _scanQr,
                            icon: const FaIcon(FontAwesomeIcons.qrcode, size: 16),
                            label: const Text('مسح QR'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                      () => _showCodeForm = !_showCodeForm,
                                    ),
                            icon: const FaIcon(
                              FontAwesomeIcons.keyboard,
                              size: 15,
                            ),
                            label: const Text('كود الدخول المؤقت'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                          if (_showCodeForm) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                hintText: '09XXXXXXXX',
                                prefixIcon:
                                    Icon(Icons.phone, color: AppColors.textLow),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _code,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8,
                                fontFamily: 'monospace',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'كود الدخول',
                                counterText: '',
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Text('دخول'),
                            ),
                          ],
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
}
