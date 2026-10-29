import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../onboarding/data/onboarding_storage.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _decideRoute();
  }

  Future<void> _decideRoute() async {
    // long enough for the logo to show, no longer (it was 1.6 s)
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final onboardingDone = ref.read(onboardingStorageProvider).isCompleted();
    final loggedIn =
        ref.read(supabaseClientProvider).auth.currentSession != null;

    if (loggedIn) {
      // Self-heal: makes sure the profile row exists (the database's trigger
      // creates it; this is only a safety net). Not awaited: on a slow
      // network it used to hold the splash for seconds.
      unawaited(ref.read(authRepositoryProvider).ensureProfile());
    }

    if (!mounted) return;
    if (!onboardingDone) {
      context.go('/onboarding');
    } else if (loggedIn) {
      // Always the main screen. Messages of a saved operation that were not
      // sent yet are offered there (a card on "الحوالات"), not forced.
      context.go('/');
    } else {
      context.go('/sign-in');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _ctrl,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.accent.withValues(alpha: 0.45),
                          AppColors.positive.withValues(alpha: 0.30),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.glassBorderStrong,
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.30),
                          blurRadius: 40,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.coins,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [AppColors.accent, AppColors.positive],
                    ).createShader(rect),
                    child: const Text(
                      'تطبيق الإشاري\nلإدارة الحوالات المالية',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'إدارة العمليات المالية',
                    style: TextStyle(
                      color: AppColors.textLow,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 56),
                  const SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: AppColors.glassBorder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
