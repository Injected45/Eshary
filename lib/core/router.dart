import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import 'supabase_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final refresh = _StreamRefresh(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = client.auth.currentSession != null;
      final loc = state.matchedLocation;

      // Splash and onboarding manage their own navigation.
      if (loc == '/splash' || loc == '/onboarding') return null;

      final atAuth = loc == '/sign-in' || loc == '/sign-up';
      if (!loggedIn && !atAuth) return '/sign-in';
      if (loggedIn && atAuth) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (_, __) => const HomeShell()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),
    ],
  );
});

/// Bridges a [Stream] (e.g. supabase auth changes) to GoRouter's
/// [refreshListenable]. Each emit triggers a router redirect re-evaluation.
class _StreamRefresh extends ChangeNotifier {
  _StreamRefresh(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
