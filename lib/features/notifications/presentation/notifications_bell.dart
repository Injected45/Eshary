import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'notifications_providers.dart';
import 'notifications_screen.dart';

/// The bell at the top of the app. A red number says how many notifications
/// were not opened yet; it drops by one each time one is opened and, at zero,
/// the number and the red are gone. A tap opens the list.
class NotificationsBell extends ConsumerWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return IconButton(
      key: const ValueKey('notifications-bell'),
      tooltip: 'الإشعارات',
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        label: Text(
          unread > 99 ? '99+' : '$unread',
          key: const ValueKey('notifications-bell-count'),
        ),
        child: const FaIcon(FontAwesomeIcons.bell, size: 16),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
      ),
    );
  }
}
