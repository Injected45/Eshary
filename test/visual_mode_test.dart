import 'dart:io';

import 'package:eshary/core/theme.dart';
import 'package:eshary/shared/cache.dart';
import 'package:eshary/shared/liquid_background.dart';
import 'package:eshary/shared/visual_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// identity helper (just forwards): avoids a naming clash in the widget tests
// below where the field 'container' shadows the function.
ProviderContainer container(ProviderContainer c) => c;

void main() {
  test('the visual mode is remembered on this phone', () async {
    SharedPreferences.setMockInitialValues({'theme:visual-mode': 'calm'});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    addTearDown(c.dispose);
    expect(c.read(visualModeProvider), AppVisualMode.calm);

    await c.read(visualModeProvider.notifier).set(AppVisualMode.deep);
    expect(c.read(visualModeProvider), AppVisualMode.deep);
    expect(sp.getString('theme:visual-mode'), 'deep');
  });

  test('default is deep (OLED) on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    addTearDown(c.dispose);
    expect(c.read(visualModeProvider), AppVisualMode.deep);
  });

  testWidgets('LiquidBackground paints the base colour of the chosen mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({'theme:visual-mode': 'calm'});
    final sp = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container(c),
        child: const MaterialApp(home: LiquidBackground(child: SizedBox())),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('liquid-base')))
          .color,
      AppColors.bgCalm,
    );

    await c.read(visualModeProvider.notifier).set(AppVisualMode.deep);
    await tester.pump();
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('liquid-base')))
          .color,
      AppColors.bgDeep,
    );
    // stop the animation so the harness can tear down cleanly
    await tester.pumpWidget(const SizedBox());
  });

  test('Settings has the two choices with their keys, and only those two', () {
    final src = File('lib/features/settings/presentation/settings_screen.dart')
        .readAsStringSync();
    expect(src, contains("ValueKey('visual-mode-deep')"));
    expect(src, contains("ValueKey('visual-mode-calm')"));
    expect(src, contains("'شكل التطبيق'"));
    expect(src, contains("'داكن'"));
    expect(src, contains("'عادي'"));
    // only the two we introduced — no stray light-mode leftover
    expect(src, isNot(contains("'فاتح'")));
  });
}
