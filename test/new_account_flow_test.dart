import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/presentation/welcome_screen.dart';
import 'package:eshary/features/trial/data/trial_repository.dart';
import 'package:eshary/features/trial/presentation/demo_tour_screen.dart';
import 'package:eshary/features/trial/presentation/phone_input.dart';
import 'package:eshary/features/trial/presentation/trial_request_screen.dart';
import 'package:eshary/shared/cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// New subscribers come in through a trial request: no e-mail sign-up, no
/// invitation QR, no SMS, no Google.
void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget screen, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Directionality(textDirection: TextDirection.rtl, child: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('welcome: start a trial / sign in / tour, nothing else',
      (tester) async {
    await pump(tester, const WelcomeScreen());
    expect(find.text('ابدأ تجربتك'), findsOneWidget);
    expect(find.text('دخول حسابي'), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-demo')), findsOneWidget);
    expect(find.text('تسجيل دخول موظف'), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-invite')), findsNothing);
    expect(find.byKey(const ValueKey('welcome-member')), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
  });

  testWidgets('welcome offers to follow a request already sent',
      (tester) async {
    await pump(
      tester,
      const WelcomeScreen(),
      prefs: {'trial:follow-token': 'abc'},
    );
    expect(find.text('متابعة طلب التجربة'), findsOneWidget);
    expect(find.text('ابدأ تجربتك'), findsNothing);
  });

  testWidgets('the request form asks for name, business, phone and consent',
      (tester) async {
    await pump(tester, const TrialRequestScreen());
    expect(find.byKey(const ValueKey('trial-manager')), findsOneWidget);
    expect(find.byKey(const ValueKey('trial-business')), findsOneWidget);
    expect(find.byKey(const ValueKey('country-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('trial-consent')), findsOneWidget);
    // Nothing is sent without the consent / a valid phone.
    await tester.tap(find.byKey(const ValueKey('trial-submit')));
    await tester.pump();
    expect(find.text('اكتب اسم المدير واسم النشاط.'), findsOneWidget);
  });

  test('phone numbers are composed in international form', () {
    expect(composePhone('+218', '0912345678'), '+218912345678');
    expect(composePhone('+218', '91 234 5678'), '+218912345678');
    expect(composePhone('+20', '01012345678'), '+201012345678');
    expect(composePhone('+218', ''), '');
  });

  testWidgets('the tour uses invented data and no server', (tester) async {
    await pump(tester, const DemoTourScreen());
    expect(find.text('بيانات تجريبية للعرض فقط'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('demo-next')));
    await tester.pumpAndSettle();
    expect(find.text('شراء دولار'), findsOneWidget);
  });

  test('Google, invitations and SMS are gone from the app', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('google_sign_in') ||
          src.contains('signInWithGoogle') ||
          src.contains('GoogleSignIn') ||
          src.contains('member_invite') ||
          src.contains('signInWithOtp') ||
          src.contains('signInWithPhone')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(pub, isNot(contains('google_sign_in')));
  });

  test('the app calls the deployed name of the sign-in function', () {
    final repo =
        File('lib/features/trial/data/trial_repository.dart').readAsStringSync();
    expect(repo, contains("const kMemberSessionFunction = 'super-handler';"));
    expect(
      RegExp(r'functions\.invoke\(\s*kMemberSessionFunction').hasMatch(repo),
      isTrue,
    );
    expect(kMemberSessionFunction, 'super-handler');
  });

  test('the database: activation starts the clock, only on the server', () {
    final sql = File('supabase/migrations/0059_trial_onboarding.sql')
        .readAsStringSync();
    expect(sql, contains('create or replace function trial_activate'));
    expect(sql, contains('_server_now()'));
    // no SMS anywhere in the flow
    expect(sql.toLowerCase(), isNot(contains('sms_send')));
  });
}
