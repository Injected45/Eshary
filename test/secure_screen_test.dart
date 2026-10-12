import 'package:eshary/shared/cache.dart';
import 'package:eshary/shared/screen_security.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('off by default; the choice is remembered and told to the window',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('eshary/device'),
            (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('eshary/device'), null));

    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)]);
    addTearDown(c.dispose);
    expect(c.read(secureScreenProvider), isFalse);

    await c.read(secureScreenProvider.notifier).set(true);
    expect(c.read(secureScreenProvider), isTrue);
    expect(sp.getString('security:secure-screen'), '1');
    expect(calls.last.method, 'setSecure');
    expect(calls.last.arguments, true);

    await c.read(secureScreenProvider.notifier).set(false);
    expect(calls.last.arguments, false);
    expect(sp.getString('security:secure-screen'), '');
  });

  test('a saved "on" is read at the next start', () async {
    SharedPreferences.setMockInitialValues({'security:secure-screen': '1'});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)]);
    addTearDown(c.dispose);
    expect(c.read(secureScreenProvider), isTrue);
  });

  test('where there is no native side nothing breaks', () async {
    await applySecureScreen(
        true); // no handler: MissingPluginException is swallowed
  });
}
