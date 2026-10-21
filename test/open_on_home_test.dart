import 'dart:io';

import 'package:eshary/shared/pending_dispatch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app always opens on the main screen, never on the messages', () {
    final splash = File('lib/features/splash/presentation/splash_screen.dart')
        .readAsStringSync();
    expect(splash.contains('/messages-dispatch'), isFalse);
    expect(splash.contains('pendingDispatchProvider'), isFalse);
    expect(splash, contains("context.go('/')"));
  });

  test('unsent messages are offered on the main screen, kept for a day', () {
    final home = File('lib/features/home/presentation/home_shell.dart')
        .readAsStringSync();
    expect(home, contains("ValueKey('pending-messages')"));
    expect(home, contains("ValueKey('pending-open')"));
    expect(home, contains("ValueKey('pending-dismiss')"));
    expect(home, contains("context.push('/messages-dispatch')"));
    expect(home, contains('Duration(hours: 24)'));
  });

  test('a pending dispatch remembers when it was saved', () {
    final p = PendingDispatch(
      kind: DispatchKind.transfer,
      savedRecordId: 'r',
      messages: const ['m'],
      openedIndices: const {},
      cardTitles: const ['t'],
      savedAt: DateTime(2026, 10, 20, 9),
    );
    expect(PendingDispatch.fromJson(p.toJson()).savedAt,
        DateTime(2026, 10, 20, 9));
  });
}
