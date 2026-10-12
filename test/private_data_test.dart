import 'dart:io';

import 'package:eshary/shared/cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
      'signing out removes what the phone knew about the person, keeps its settings',
      () async {
    SharedPreferences.setMockInitialValues({
      'cache:transfers:u1:archived': '[{"x":1}]',
      'cache:license:u1': '{"status":"trial"}',
      'cache:companies:u1': '[]',
      'app_logs_v1': '[{"message":"error with a name"}]',
      // the phone's own settings stay
      'applock:enabled': '1',
      'theme:visual-mode': 'calm',
      'security:secure-screen': '1',
      'eshary.device_id.v2': 'k' * 40,
      'trial:follow-token': 'abc',
    });
    final sp = await SharedPreferences.getInstance();
    await clearPrivateData(sp);
    expect(sp.getKeys().where((k) => k.startsWith('cache:')), isEmpty);
    expect(sp.getString('app_logs_v1'), isNull);
    expect(sp.getString('applock:enabled'), '1');
    expect(sp.getString('theme:visual-mode'), 'calm');
    expect(sp.getString('security:secure-screen'), '1');
    expect(sp.getString('eshary.device_id.v2'), 'k' * 40);
    expect(sp.getString('trial:follow-token'), 'abc');
  });

  test('JsonCache.clearUserData does the same', () async {
    SharedPreferences.setMockInitialValues({
      'cache:a': '1',
      'applock:enabled': '1',
    });
    final sp = await SharedPreferences.getInstance();
    await JsonCache(sp).clearUserData();
    expect(sp.getString('cache:a'), isNull);
    expect(sp.getString('applock:enabled'), '1');
  });

  test('a restored backup no longer wipes the phone\'s own settings', () {
    final src = File('lib/features/admin/presentation/backup_screen.dart')
        .readAsStringSync();
    expect(src, contains('clearUserData()'));
    expect(src.contains('jsonCacheProvider).clear()'), isFalse);
  });

  test('the app clears private data on every sign-out, in one place', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('AuthChangeEvent.signedOut'));
    expect(main, contains('clearPrivateData(prefs)'));
  });
}
