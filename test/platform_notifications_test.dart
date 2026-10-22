import 'dart:io';

import 'package:eshary/core/supabase_provider.dart';
import 'package:eshary/features/notifications/domain/app_notification.dart';
import 'package:eshary/features/notifications/presentation/notifications_providers.dart';
import 'package:eshary/features/notifications/presentation/notifications_screen.dart';
import 'package:eshary/features/notifications/presentation/platform_notifications_listener.dart';
import 'package:eshary/shared/cache.dart';
import 'package:eshary/shared/notification_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppNotification _n(String id, String body, DateTime at, {String? title}) =>
    AppNotification(
      id: id,
      title: title,
      body: body,
      isActive: true,
      createdAt: at,
    );

final _t0 = DateTime(2026, 10, 22, 12);

void main() {
  group('the dropdown', () {
    Future<void> show(
      WidgetTester tester, {
      VoidCallback? onOpen,
      int more = 0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showNotificationDropdown(
                    context,
                    title: 'تنبيه',
                    body: 'تم تحديث النظام',
                    more: more,
                    onOpen: onOpen,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('drops down with the text and stays 15 seconds', (
      tester,
    ) async {
      await show(tester);
      expect(find.byKey(const ValueKey('notification-dropdown')), findsOne);
      expect(find.text('تنبيه'), findsOneWidget);
      expect(find.text('تم تحديث النظام'), findsOneWidget);

      await tester.pump(const Duration(seconds: 14));
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsOneWidget,
        reason: 'still on screen at 14 s',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsNothing,
        reason: 'gone after 15 s',
      );
    });

    testWidgets('its background is white and see-through', (tester) async {
      await show(tester);
      final box = tester.widget<Container>(
        find.byKey(const ValueKey('notification-dropdown')),
      );
      final color = (box.decoration! as BoxDecoration).color!;
      expect((color.r * 255).round(), 255);
      expect((color.g * 255).round(), 255);
      expect((color.b * 255).round(), 255);
      expect(color.a, greaterThan(0.5));
      expect(color.a, lessThan(1.0), reason: 'translucent, not solid');
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the close button removes it', (tester) async {
      await show(tester);
      await tester
          .tap(find.byKey(const ValueKey('notification-dropdown-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsNothing,
      );
    });

    testWidgets('a tap opens the list and closes it', (tester) async {
      var opened = 0;
      await show(tester, onOpen: () => opened++);
      await tester.tap(find.text('تم تحديث النظام'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 1);
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsNothing,
      );
    });

    testWidgets('says how many others came with it', (tester) async {
      await show(tester, more: 2);
      expect(find.text('+ 2 إشعارات أخرى'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a new one replaces the one on screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        showNotificationDropdown(context, body: 'الأولى'),
                    child: const Text('one'),
                  ),
                  TextButton(
                    onPressed: () =>
                        showNotificationDropdown(context, body: 'الثانية'),
                    child: const Text('two'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('one'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('two'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('الأولى'), findsNothing);
      expect(find.text('الثانية'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('arrival', () {
    late StateProvider<List<AppNotification>> feed;

    Future<ProviderContainer> pump(
      WidgetTester tester,
      List<AppNotification> start, {
      required VoidCallback onOpen,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      feed = StateProvider<List<AppNotification>>((ref) => start);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('u1'),
          notificationsListProvider
              .overrideWith((ref) async => ref.watch(feed)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: PlatformNotificationsListener(
                onOpen: onOpen,
                child: Consumer(
                  builder: (context, ref, _) {
                    ref.watch(notificationsListProvider);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return container;
    }

    testWidgets('what is already there at start does not ring', (
      tester,
    ) async {
      await pump(tester, [_n('a', 'قديم', _t0)], onOpen: () {});
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsNothing,
      );
    });

    testWidgets('a new notification drops down for 15 s', (tester) async {
      final c = await pump(tester, [_n('a', 'قديم', _t0)], onOpen: () {});
      c.read(feed.notifier).state = [
        _n('b', 'نص جديد', _t0.add(const Duration(minutes: 1)), title: 'مهم'),
        _n('a', 'قديم', _t0),
      ];
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('notification-dropdown')), findsOne);
      expect(find.text('مهم'), findsOneWidget);
      expect(find.text('نص جديد'), findsOneWidget);
      expect(find.text('قديم'), findsNothing);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsNothing,
      );
    });

    testWidgets('several at once: the newest, and how many more', (
      tester,
    ) async {
      final c = await pump(tester, [_n('a', 'قديم', _t0)], onOpen: () {});
      c.read(feed.notifier).state = [
        _n('d', 'الرابع', _t0.add(const Duration(minutes: 3))),
        _n('c', 'الثالث', _t0.add(const Duration(minutes: 2))),
        _n('a', 'قديم', _t0),
      ];
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('الرابع'), findsOneWidget);
      expect(find.text('+ 1 إشعارات أخرى'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a notification switched off does not ring', (tester) async {
      final c = await pump(
        tester,
        [_n('a', 'قديم', _t0), _n('b', 'ثان', _t0)],
        onOpen: () {},
      );
      c.read(feed.notifier).state = [_n('a', 'قديم', _t0)];
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('notification-dropdown')),
        findsNothing,
      );
    });

    testWidgets('a tap on the panel calls onOpen', (tester) async {
      var opened = 0;
      final c = await pump(
        tester,
        [_n('a', 'قديم', _t0)],
        onOpen: () => opened++,
      );
      c.read(feed.notifier).state = [
        _n('b', 'نص جديد', _t0.add(const Duration(minutes: 1))),
        _n('a', 'قديم', _t0),
      ];
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('نص جديد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(opened, 1);
    });
  });

  group('read and unread', () {
    Future<ProviderContainer> container(
      List<AppNotification> list, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(p),
          currentUserIdProvider.overrideWithValue('u1'),
          notificationsListProvider.overrideWith((ref) async => list),
        ],
      );
      addTearDown(c.dispose);
      await c.read(notificationsListProvider.future);
      return c;
    }

    final list = [
      _n('b', 'ب', _t0.add(const Duration(hours: 2))),
      _n('a', 'أ', _t0),
    ];

    test('everything is unread before the first visit', () async {
      final c = await container(list);
      expect(c.read(unreadNotificationsProvider), 2);
    });

    test('opening the list marks them read, and it is remembered', () async {
      final c = await container(list);
      await c.read(notificationsSeenProvider.notifier).markSeen(list);
      expect(c.read(unreadNotificationsProvider), 0);
      final stored = c.read(jsonCacheProvider).readString('notif_seen:u1');
      expect(stored, isNotNull);

      // a later notification is unread again; a restart keeps what was read
      final again = await container(
        [_n('c', 'ج', _t0.add(const Duration(hours: 3))), ...list],
        prefs: {'notif_seen:u1': stored!},
      );
      expect(again.read(unreadNotificationsProvider), 1);
    });

    test('each account keeps its own', () async {
      final c = await container(list);
      await c.read(notificationsSeenProvider.notifier).markSeen(list);
      expect(
        c.read(jsonCacheProvider).readString('notif_seen:other'),
        isNull,
      );
    });
  });

  group('the screen', () {
    Future<void> pump(
      WidgetTester tester,
      List<AppNotification> list, {
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final p = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(p),
            currentUserIdProvider.overrideWithValue('u1'),
            notificationsListProvider.overrideWith((ref) async => list),
          ],
          child: const MaterialApp(
            home: Scaffold(body: NotificationsView(topPadding: 8)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists title, text and time, newest first', (tester) async {
      await pump(tester, [
        _n('b', 'نص الثاني', _t0.add(const Duration(hours: 1)), title: 'عنوان'),
        _n('a', 'نص الأول', _t0),
      ]);
      expect(find.text('عنوان'), findsOneWidget);
      expect(find.text('نص الثاني'), findsOneWidget);
      expect(find.text('نص الأول'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('نص الثاني')).dy,
        lessThan(tester.getTopLeft(find.text('نص الأول')).dy),
      );
    });

    testWidgets('a dot marks what arrived after the last visit', (
      tester,
    ) async {
      await pump(
        tester,
        [
          _n('b', 'جديد', _t0.add(const Duration(hours: 2))),
          _n('a', 'قديم', _t0),
        ],
        prefs: {
          'notif_seen:u1': _t0.add(const Duration(hours: 1)).toIso8601String(),
        },
      );
      expect(find.byKey(const ValueKey('notification-unread')), findsOne);
    });

    testWidgets('empty says so', (tester) async {
      await pump(tester, const []);
      expect(find.text('لا توجد إشعارات حاليًا'), findsOneWidget);
    });
  });

  group('the app', () {
    final shell = File('lib/features/home/presentation/home_shell.dart')
        .readAsStringSync();

    test('has an "الإشعارات" tab with a badge', () {
      expect(shell, contains("label: 'الإشعارات'"));
      expect(shell, contains('unreadNotificationsProvider'));
      expect(shell, contains('const NotificationsView()'));
    });

    test(
        'the tab sits after "التقارير" for the admin, after "العمليات" otherwise',
        () {
      expect(shell, contains("'التقارير',\n    'الإشعارات',"));
      expect(shell, contains("'العمليات',\n    'الإشعارات',"));
      expect(shell, contains('showReports ? 3 : 2'));
    });

    test('rings in both shells and the sync re-reads every few seconds', () {
      expect(shell, contains('PlatformNotificationsListener('));
      expect(
        File('lib/features/employee_auth/presentation/employee_home_shell.dart')
            .readAsStringSync(),
        contains('PlatformNotificationsListener('),
      );
      expect(
        File('lib/shared/realtime_sync.dart').readAsStringSync(),
        contains('ref.invalidate(notificationsListProvider)'),
      );
    });

    test('the sound is the app bell and the time is 15 seconds', () {
      final listener = File(
        'lib/features/notifications/presentation/platform_notifications_listener.dart',
      ).readAsStringSync();
      expect(listener, contains('playAlert()'));
      expect(kNotificationDropdownDuration, const Duration(seconds: 15));
    });
  });
}
