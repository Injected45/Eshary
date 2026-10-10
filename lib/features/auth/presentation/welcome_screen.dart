import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/cache.dart';
import '../../trial/data/trial_repository.dart';

/// First screen for signed-out users:
///   - ابدأ تجربتك     -> asks for a trial; the administrator decides and a
///     WhatsApp code starts it (no e-mail, no invitation, no SMS)
///   - دخول حسابي      -> a subscriber already in: phone + WhatsApp code
///   - جولة تعريفية    -> a tour with invented data
///   - تسجيل دخول موظف -> temporary code or QR
/// The platform administrator's e-mail / password sign-in lives behind the
/// small "دخول المدير" link, so it is not shown to employees.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasRequest = savedFollowToken(ref.watch(jsonCacheProvider)) != null;
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
                        FilledButton.icon(
                          key: const ValueKey('welcome-trial'),
                          onPressed: () => context.go(hasRequest
                              ? '/trial-follow'
                              : '/trial-request'),
                          icon: const FaIcon(FontAwesomeIcons.rocket, size: 16),
                          label: Text(
                            hasRequest ? 'متابعة طلب التجربة' : 'ابدأ تجربتك',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const ValueKey('welcome-phone'),
                          onPressed: () => context.go('/phone-login'),
                          icon:
                              const FaIcon(FontAwesomeIcons.whatsapp, size: 16),
                          label: const Text('دخول حسابي'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('welcome-demo'),
                          onPressed: () => context.go('/demo'),
                          icon: const FaIcon(FontAwesomeIcons.play, size: 14),
                          label: const Text('جولة تعريفية'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textHigh,
                            side: const BorderSide(
                                color: AppColors.glassBorderStrong),
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
