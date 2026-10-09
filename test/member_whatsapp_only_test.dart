import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/data/member_auth_repository.dart';
import 'package:eshary/features/auth/presentation/member_auth_screen.dart';
import 'package:eshary/shared/device_email_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Picker extends DeviceEmailPicker {
  @override
  bool get isSupported => true;

  @override
  Future<EmailPick> pick() async => const EmailPicked('rahala@gmail.com');
}

class _Repo implements MemberAuthRepository {
  _Repo({required this.needsEmail});
  final bool needsEmail;
  int requests = 0;

  @override
  Future<MemberOtpSent> requestOtp(String email, String phone) async {
    requests++;
    return MemberOtpSent(
      phoneMasked: '09****1234',
      isNew: !needsEmail,
      needsEmail: needsEmail,
    );
  }

  @override
  Future<void> verify(
    String email,
    String phone,
    String otp, {
    String? emailCode,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> signUp(WidgetTester tester, _Repo repo) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceEmailPickerProvider.overrideWithValue(_Picker()),
          memberAuthRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MemberAuthScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'رقم الهاتف (واتساب)'), '0912345678');
    await tester.tap(find.text('إرسال رمز التحقق'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new account goes straight to the WhatsApp code', (tester) async {
    final repo = _Repo(needsEmail: false);
    await signUp(tester, repo);
    expect(repo.requests, 1);
    expect(find.text('رمز واتساب'), findsOneWidget);
    expect(find.text('رمز البريد الإلكتروني'), findsNothing);
    expect(find.textContaining('أدخل رمز واتساب الواصل إلى 09****1234'), findsOneWidget);
  });

  testWidgets('an old account without a phone still gets the e-mail code', (tester) async {
    await signUp(tester, _Repo(needsEmail: true));
    expect(find.text('رمز واتساب'), findsOneWidget);
    expect(find.text('رمز البريد الإلكتروني'), findsOneWidget);
  });

  test('server side: new e-mail needs no e-mail code, existing one without a phone does', () {
    final sql = File('supabase/migrations/0049_new_account_whatsapp_only.sql').readAsStringSync();
    expect(sql, contains("'userId', null, 'needsEmail', false"));
    expect(sql, contains("'userId', v_user, 'needsEmail', true"));
    final fn = File('supabase/functions/member-session/index.ts').readAsStringSync();
    expect(fn, contains('admin.auth.admin.createUser({ email: mail, email_confirm: true })'));
    expect(fn, contains('if (checked.needsEmail)'));
  });
}
