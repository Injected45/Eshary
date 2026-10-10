import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/employee_auth/presentation/employee_home_shell.dart';
import '../features/employee_auth/presentation/employee_login_screen.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/license/presentation/license_provider.dart';
import '../features/license/presentation/pending_activation_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../features/trial/presentation/demo_tour_screen.dart';
import '../features/trial/presentation/phone_change_screen.dart';
import '../features/trial/presentation/subscription_screen.dart';
import '../features/trial/presentation/trial_follow_screen.dart';
import '../features/trial/presentation/trial_login_screen.dart';
import '../features/trial/presentation/trial_request_screen.dart';
import '../shared/messages_dispatch_screen.dart';
import 'supabase_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final refresh = _StreamRefresh(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  // Re-evaluate redirects whenever the license result transitions
  // (loading → data, or data → data with a different is_valid).
  ref.listen(licenseStatusProvider, (_, __) => refresh.bump());

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = client.auth.currentUser;
      final loggedIn = client.auth.currentSession != null && user != null;
      final isAnonymous = user?.isAnonymous == true;
      final loc = state.matchedLocation;

      // Splash and onboarding manage their own navigation.
      if (loc == '/splash' || loc == '/onboarding') return null;

      final atAdminAuth = loc == '/sign-in' ||
          loc == '/sign-up' ||
          loc == '/admin-sign-in' ||
          loc == '/phone-login' ||
          loc == '/trial-request' ||
          loc == '/trial-follow' ||
          loc == '/demo';
      final atEmployeeAuth = loc == '/employee-sign-in';
      final atAuth = atAdminAuth || atEmployeeAuth;

      // Not signed in: only auth screens are reachable.
      if (!loggedIn) {
        if (!atAuth) return '/sign-in';
        return null;
      }

      // Anonymous (employee) session: scope to employee-allowed routes.
      // /employee-sign-in must stay reachable until the login screen
      // manually navigates after a successful RPC. /messages-dispatch is
      // shared with admins — employees land there after saving a transfer
      // or currency_buy to share the composed messages.
      if (isAnonymous) {
        const employeeAllowed = {
          '/employee-home',
          '/employee-sign-in',
          '/messages-dispatch',
        };
        if (employeeAllowed.contains(loc)) return null;
        return '/employee-home';
      }

      // Admin session: redirect away from any auth screen, including the
      // employee sign-in (an admin shouldn't try to sign in as an employee
      // without signing out first).
      if (atAuth || loc == '/employee-home') return '/';

      // License gate — admin only.
      final license = ref.read(licenseStatusProvider);
      final status = license.maybeWhen(
        data: (s) => s,
        orElse: () => null,
      );
      if (status != null) {
        // An expired subscriber still reaches the data (read only); the
        // server refuses every write. Pending / blocked stay on the gate.
        final canEnter = status.isValid || status.isReadOnly;
        if (!canEnter && loc != '/pending-activation') {
          return '/pending-activation';
        }
        if (canEnter && loc == '/pending-activation') {
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', builder: (_, __) => const HomeShell()),
      // First screen for signed-out users: create account / employee sign-in.
      GoRoute(path: '/sign-in', builder: (_, __) => const WelcomeScreen()),
      // Platform administrator: e-mail + password or Google.
      GoRoute(
        path: '/admin-sign-in',
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: '/phone-login',
        builder: (_, __) => const TrialLoginScreen(),
      ),
      GoRoute(
        path: '/trial-request',
        builder: (_, __) => const TrialRequestScreen(),
      ),
      GoRoute(
        path: '/trial-follow',
        builder: (_, __) => const TrialFollowScreen(),
      ),
      GoRoute(
        path: '/phone-change',
        builder: (_, __) => const PhoneChangeScreen(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, __) => const SubscriptionScreen(),
      ),
      GoRoute(path: '/demo', builder: (_, __) => const DemoTourScreen()),
      GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: '/employee-sign-in',
        builder: (_, __) => const EmployeeLoginScreen(),
      ),
      GoRoute(
        path: '/employee-home',
        builder: (_, __) => const EmployeeHomeShell(),
      ),
      GoRoute(
        path: '/pending-activation',
        builder: (_, __) => const PendingActivationScreen(),
      ),
      GoRoute(
        path: '/messages-dispatch',
        builder: (_, __) => const MessagesDispatchScreen(),
      ),
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

  /// Manual refresh trigger used when non-stream sources (e.g. license
  /// FutureProvider transitions) need to re-evaluate the redirect chain.
  void bump() => notifyListeners();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
