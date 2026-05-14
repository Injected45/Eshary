import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/employee_auth_repository.dart';
import 'employee_auth_providers.dart';

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
  String? _error;

  // Same Libyan format as add_sub_user_dialog (matches the DB check).
  static final _libyanPhoneRegex = RegExp(r'^09[0-9]{8}$');

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
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
      await ref.read(employeeAuthRepositoryProvider).signIn(
            phone: phone,
            code: code,
          );
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
    return Scaffold(
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
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accent.withValues(alpha: 0.30),
                                AppColors.positive.withValues(alpha: 0.20),
                              ],
                            ),
                            border:
                                Border.all(color: AppColors.glassBorderStrong),
                          ),
                          child: const FaIcon(
                            FontAwesomeIcons.userTie,
                            size: 22,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'تسجيل دخول الموظف',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textHigh,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'أدخل رقم هاتفك وكود الدخول المؤقت الذي زوّدك به المدير.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textLow,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
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
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.negative.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    AppColors.negative.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.negative,
                              ),
                            ),
                          ),
                        if (_error != null) const SizedBox(height: 12),
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
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed:
                              _busy ? null : () => context.go('/sign-in'),
                          child: const Text('عودة لدخول المدير'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'شركة الرحالة للبرمجيات . جميع الحقوق محفوظة 2026 ©',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
