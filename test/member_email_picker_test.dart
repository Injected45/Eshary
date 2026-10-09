import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/features/auth/presentation/member_auth_screen.dart';
import 'package:eshary/shared/device_email_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePicker extends DeviceEmailPicker {
  _FakePicker(this.answer, {this.supported = true});
  final EmailPick answer;
  final bool supported;
  int calls = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<EmailPick> pick() async {
    calls++;
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(WidgetTester tester, DeviceEmailPicker picker) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [deviceEmailPickerProvider.overrideWithValue(picker)],
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
  }

  final emailField = find.byKey(const ValueKey('member-email'));

  String textOf(WidgetTester tester) =>
      tester.widget<TextField>(emailField).controller!.text;

  testWidgets('tapping the field opens the phone accounts and fills it',
      (tester) async {
    final picker = _FakePicker(const EmailPicked('rahala@gmail.com'));
    await open(tester, picker);
    expect(find.text('اضغط لاختيار بريدك من الهاتف'), findsOneWidget);
    await tester.tap(emailField);
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(textOf(tester), 'rahala@gmail.com');
  });

  testWidgets('the address cannot be typed by hand', (tester) async {
    await open(tester, _FakePicker(const EmailPickCancelled()));
    expect(tester.widget<TextField>(emailField).readOnly, isTrue);
    await tester.tap(emailField);
    await tester.pumpAndSettle();
    expect(textOf(tester), isEmpty, reason: 'closed without choosing');
  });

  testWidgets('no chooser on the phone: typing is allowed, with a note',
      (tester) async {
    await open(tester, _FakePicker(const EmailPickUnavailable()));
    await tester.tap(emailField);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(emailField).readOnly, isFalse);
    expect(find.textContaining('اكتب بريدك الإلكتروني'), findsOneWidget);
    await tester.enterText(emailField, 'a@b.ly');
    expect(textOf(tester), 'a@b.ly');
  });

  testWidgets('not Android (web): typed from the start', (tester) async {
    await open(
      tester,
      _FakePicker(const EmailPickUnavailable(), supported: false),
    );
    expect(tester.widget<TextField>(emailField).readOnly, isFalse);
  });

  group('the channel', () {
    const channel = MethodChannel('eshary/account_picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('a chosen account comes back lower-case', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'pickEmail' ? ' Rahala@Gmail.com ' : null,
      );
      final r = await const DeviceEmailPicker().pick();
      expect((r as EmailPicked).email, 'rahala@gmail.com');
      debugDefaultTargetPlatformOverride = null;
    });

    test('closed: cancelled; not an e-mail or an error: unavailable', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await const DeviceEmailPicker().pick(), isA<EmailPickCancelled>());
      messenger.setMockMethodCallHandler(channel, (call) async => 'not-mail');
      expect(
        await const DeviceEmailPicker().pick(),
        isA<EmailPickUnavailable>(),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'unavailable'),
      );
      expect(
        await const DeviceEmailPicker().pick(),
        isA<EmailPickUnavailable>(),
      );
      debugDefaultTargetPlatformOverride = null;
    });
  });

  test('Android side: the chooser lists the phone accounts', () {
    final kt = File(
      'android/app/src/main/kotlin/com/rahala/eshary/MainActivity.kt',
    ).readAsStringSync();
    expect(kt, contains('"eshary/account_picker"'));
    expect(kt, contains('AccountManager.newChooseAccountIntent'));
    expect(kt, contains('KEY_ACCOUNT_NAME'));
  });
}
