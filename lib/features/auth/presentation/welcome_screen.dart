import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/google_button.dart';
import '../../../shared/logger.dart';
import '../data/auth_repository.dart';

/// First screen for signed-out users:
///   - التسجيل باستخدام Google  -> a NEW account: the person picks a Google
///     account on the phone (which proves the e-mail), then confirms the phone
///     with one WhatsApp code (the link-phone screen)
///   - لدي حساب                 -> a returning member: e-mail + phone + WhatsApp
///     code (member-auth)
///   - تسجيل دخول موظف          -> temporary code or QR
/// The platform administrator's e-mail / password / Google sign-in lives
/// behind the small "دخول المدير" link, so it is not shown to employees.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signUpWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The session that follows moves the router (link phone / pending).
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e, st) {
      AppLogger.error('welcome.google', e, st);
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
                            FontAwesomeIcons.lock,
                            size: 22,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'مرحباً بك في تطبيق إشاري',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textHigh,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'اختر طريقة الدخول',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textLow,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'إنشاء حساب جديد',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMid,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GoogleSignInButton(
                          onPressed: _signUpWithGoogle,
                          busy: _busy,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.negative,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => context.go('/member-auth'),
                          icon: const FaIcon(FontAwesomeIcons.rightToBracket, size: 16),
                          label: const Text('لدي حساب'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/employee-sign-in'),
                          icon: const FaIcon(
                            FontAwesomeIcons.userTie,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          label: const Text('تسجيل دخول موظف'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: BorderSide(
                              color: AppColors.accent.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go('/admin-sign-in'),
                          child: const Text(
                            'دخول المدير',
                            style: TextStyle(
                              color: AppColors.textLow,
                              fontSize: 12,
                            ),
                          ),
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
