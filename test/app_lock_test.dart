import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/shared/app_lock.dart';
import 'package:eshary/shared/cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements DeviceAuth {
  _FakeAuth(this.result);
  bool result;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return result;
  }
}

Future<_FakeAuth> _pump(
  WidgetTester tester, {
  required bool enabled,
  required String? uid,
  required bool authResult,
}) async {
  SharedPreferences.setMockInitialValues({if (enabled) 'applock:enabled': '1'});
  final sp = await SharedPreferences.getInstance();
  final fake = _FakeAuth(authResult);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        currentUserIdProvider.overrideWithValue(uid),
        deviceAuthProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: AppLockGate(child: Scaffold(body: Text('بيانات سرية'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('lock on + signed in: the data is hidden until the phone agrees',
      (tester) async {
    final fake = await _pump(
      tester,
      enabled: true,
      uid: 'u1',
      authResult: false,
    );
    expect(fake.asked, 1); // asked automatically at start
    expect(find.text('التطبيق مقفل'), findsOneWidget);
    expect(find.text('بيانات سرية'), findsNothing);

    fake.result = true;
    await tester.tap(find.byKey(const ValueKey('unlock')));
    await tester.pumpAndSettle();
    expect(find.text('بيانات سرية'), findsOneWidget);
    expect(find.text('التطبيق مقفل'), findsNothing);
  });

  testWidgets('lock off: nothing is asked', (tester) async {
    final fake = await _pump(
      tester,
      enabled: false,
      uid: 'u1',
      authResult: false,
    );
    expect(fake.asked, 0);
    expect(find.text('بيانات سرية'), findsOneWidget);
  });

  testWidgets('signed out: no lock screen', (tester) async {
    final fake = await _pump(
      tester,
      enabled: true,
      uid: null,
      authResult: false,
    );
    expect(fake.asked, 0);
    expect(find.text('بيانات سرية'), findsOneWidget);
  });
}
