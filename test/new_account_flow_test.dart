import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/presentation/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// New accounts: the e-mail is picked from the phone's accounts, the phone is
/// confirmed with one WhatsApp code. No Google sign-in anywhere.
void main() {
  testWidgets('the welcome screen has one entry for a new account / sign-in',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: WelcomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('welcome-member')), findsOneWidget);
    expect(find.text('إنشاء حساب بالبريد / دخول'), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-invite')), findsOneWidget);
    expect(find.byKey(const ValueKey('welcome-phone')), findsOneWidget);
    expect(find.text('تسجيل دخول موظف'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);
  });

  test('Google is gone from the app', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('google_sign_in') ||
          src.contains('signInWithGoogle') ||
          src.contains('GoogleSignIn')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(pub, isNot(contains('google_sign_in')));
  });

  test('the database: a new e-mail needs only the WhatsApp code', () {
    final sql = File('supabase/migrations/0057_new_account_by_phone_email.sql')
        .readAsStringSync();
    expect(sql, contains("'userId', null, 'needsEmail', false"));
    expect(sql, contains("'userId', v_user, 'needsEmail', true"));
    expect(sql, isNot(contains("'code', 'use_google'")));
  });

  test('the app calls the deployed name of the sign-in function', () {
    final repo = File('lib/features/auth/data/member_auth_repository.dart')
        .readAsStringSync();
    expect(repo, contains("const kMemberSessionFunction = 'super-handler';"));
    // exactly one place invokes it, through the constant
    expect(RegExp(r"functions\.invoke\(\s*kMemberSessionFunction").hasMatch(repo), isTrue);
    expect(repo, isNot(contains("invoke(\n        'member-session'")));
  });
}
