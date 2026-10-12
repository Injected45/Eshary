import 'package:eshary/features/employee_auth/data/device_id_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<DeviceIdService> _svc(
  Map<String, Object> prefs, {
  Future<String?> Function()? native,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return DeviceIdService(
    await SharedPreferences.getInstance(),
    nativeKey: native ?? () async => 'a' * 40,
  );
}

void main() {
  test(
      'a phone with its own key sends NEW, and NEW~OLD while an old key exists',
      () async {
    final s = await _svc({'eshary.device_id.v1': 'UP1A.231005.007'});
    expect(await s.get(), '${'a' * 40}~UP1A.231005.007');
  });

  test('no old key: only the new key is sent', () async {
    final s = await _svc({});
    // (the test host is not Android, so no build id is offered either)
    expect(await s.get(), 'a' * 40);
  });

  test('the key is the same at every sign-in', () async {
    var n = 0;
    final s =
        await _svc({}, native: () async => n++ == 0 ? 'k' * 40 : 'z' * 40);
    final first = await s.get();
    final second = await s.get();
    expect(first, second, reason: 'cached after the first read');
    expect(first, 'k' * 40);
  });

  test('without a native key a random id is made once and kept', () async {
    final s = await _svc({}, native: () async => null);
    final first = await s.get();
    expect(first, isNotEmpty);
    expect(first.contains('~'), isFalse);
    expect(await s.get(), first, reason: 'kept on the phone');
  });

  test('the old key is never sent as the new one', () async {
    final s = await _svc({'eshary.device_id.v1': 'UP1A.old'});
    final k = await s.get();
    expect(k.split('~').first, 'a' * 40);
    expect(k.split('~').first, isNot('UP1A.old'));
  });

  test('an old key equal to the new one is not repeated', () async {
    final s = await _svc({'eshary.device_id.v1': 'a' * 40});
    expect(await s.get(), 'a' * 40);
  });
}
