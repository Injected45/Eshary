import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/libya_time.dart';
import '../domain/app_notification.dart';
import 'notifications_providers.dart';

final _stamp = LibyaDateFormat('yyyy/MM/dd  HH:mm');

/// The platform's notifications, newest first. One not opened yet has a blue
/// dot; a tap opens it (it becomes read and the bell's number drops by one).
/// Reached from الإعدادات → الإشعارات, from the bell and from the dropdown.
class NotificationsView extends ConsumerWidget {
  const NotificationsView({super.key, this.topPadding});

  /// Space under a transparent app bar.
  final double? topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsListProvider);
    final read = ref.watch(notificationsReadProvider);
    final top = topPadding ?? contentTopPadding(context);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(notificationsListProvider.future),
      child: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: EdgeInsets.fromLTRB(16, top, 16, 16),
          children: const [
            _Empty('تعذّر تحميل الإشعارات. اسحب للأسفل للتحديث'),
          ],
        ),
        data: (list) => ListView(
          key: const ValueKey('notifications-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            top,
            16,
            contentBottomPadding(context),
          ),
          children: [
            if (list.isEmpty)
              const _Empty('لا توجد إشعارات حاليًا')
            else
              for (final n in list) ...[
                _Tile(
                  n: n,
                  unread: !read.contains(n.id),
                  onOpen: () => ref
                      .read(notificationsReadProvider.notifier)
                      .markRead(n.id),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const FaIcon(
              FontAwesomeIcons.bellSlash,
              size: 34,
              color: AppColors.textLow,
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textLow, fontSize: 13),
            ),
          ],
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.n, required this.unread, required this.onOpen});
  final AppNotification n;
  final bool unread;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = (n.title ?? '').trim();
    return GlassCard(
      key: ValueKey('notification-${n.id}'),
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  key: unread ? const ValueKey('notification-unread') : null,
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unread ? AppColors.accent : Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.textHigh,
                          fontSize: 15,
                          fontWeight:
                              unread ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    if (title.isNotEmpty) const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: TextStyle(
                        color: unread ? AppColors.textHigh : AppColors.textMid,
                        fontSize: 13.5,
                        height: 1.55,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stamp.format(n.createdAt),
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list as its own page: opened from الإعدادات → الإشعارات, from the bell
/// at the top of the app and from the dropdown. It reads nothing by itself:
/// each notification is read when it is opened (tapped).
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('الإشعارات'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: const NotificationsView(),
    );
  }
}
