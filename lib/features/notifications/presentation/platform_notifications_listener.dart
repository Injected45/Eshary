import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/audio_feedback.dart';
import '../../../shared/background_alerts.dart';
import '../../../shared/notification_dropdown.dart';
import 'notifications_providers.dart';

/// Rings when the platform publishes a notification while the app is open:
/// the bell sound and a dropdown panel that stays 15 seconds. With the app in
/// the background it raises a system notification instead.
///
/// The first read after the app starts shows nothing (those are old: the
/// notifications tab marks them unread). Only what arrives afterwards rings.
/// [onOpen] runs when the person taps the panel.
class PlatformNotificationsListener extends ConsumerWidget {
  const PlatformNotificationsListener({
    super.key,
    required this.child,
    required this.onOpen,
  });

  final Widget child;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(notificationsListProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (before == null || now == null) return; // first load: no ring
      final known = before.map((n) => n.id).toSet();
      final fresh = now.where((n) => !known.contains(n.id)).toList();
      if (fresh.isEmpty) return;
      // newest first (the list is)
      final first = fresh.first;

      if (BackgroundAlerts.instance.inBackground) {
        for (final n in fresh.take(5)) {
          BackgroundAlerts.instance.notify(
            id: n.id.hashCode,
            title: (n.title ?? '').trim().isEmpty ? 'إشعار جديد' : n.title!,
            body: n.body,
          );
        }
        return;
      }
      playAlert();
      showNotificationDropdown(
        context,
        title: first.title,
        body: first.body,
        more: fresh.length - 1,
        onOpen: onOpen,
      );
    });
    return child;
  }
}
