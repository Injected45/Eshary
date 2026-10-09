import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../cancellations/presentation/cancellations_screen.dart';
import '../../sub_users/presentation/sub_users_providers.dart';
import '../data/employee_alerts_repository.dart';
import '../domain/employee_alert.dart';
import 'employee_alerts_providers.dart';
import 'send_employee_message_dialog.dart';

final _dateFmt = DateFormat('yyyy-MM-dd  HH:mm');

/// The notification text for one operation, in the wording the admin asked for.
String alertText(EmployeeAlert a) {
  final party = (a.partyName ?? '').trim().isEmpty ? '—' : a.partyName!.trim();
  if (a.isCancelRequest) {
    return 'طلب إلغاء "${a.directionLabel}" من الموظف ${a.employeeName}\n'
        'بقيمة ${formatMoney(a.amount)}\$ - ${a.partyLabel} $party';
  }
  return 'تم تنفيذ "${a.directionLabel}" من الموظف ${a.employeeName}\n'
      'بقيمة ${formatMoney(a.amount)}\$ إلى ${a.partyLabel} $party';
}

/// Key that groups alerts by employee. An employee deleted later keeps their
/// alerts, grouped by the name stored on them.
String _groupKey(EmployeeAlert a) => a.subUserId ?? 'deleted:${a.employeeName}';

/// Settings → إشعارات الموظفين: one card per employee with their alert count,
/// plus sending messages to employees.
class EmployeeAlertsScreen extends ConsumerWidget {
  const EmployeeAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(employeeAlertsProvider);
    final employees = ref.watch(subUsersListProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('إشعارات الموظفين'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () {
              ref.invalidate(employeeAlertsProvider);
              ref.invalidate(subUsersListProvider);
            },
          ),
        ],
      ),
      body: alertsAsync.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              friendlyError(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textLow),
            ),
          ),
        ),
        data: (alerts) {
          final groups = <String, _Group>{
            for (final e in employees)
              e.id: _Group(key: e.id, name: e.employeeName),
          };
          for (final a in alerts) {
            groups
                .putIfAbsent(
                  _groupKey(a),
                  () => _Group(key: _groupKey(a), name: a.employeeName),
                )
                .alerts
                .add(a);
          }
          final list = groups.values.toList()
            ..sort((a, b) {
              final la = a.alerts.isEmpty ? null : a.alerts.first.createdAt;
              final lb = b.alerts.isEmpty ? null : b.alerts.first.createdAt;
              if (la != null && lb != null) return lb.compareTo(la);
              if (la != null) return -1;
              if (lb != null) return 1;
              return a.name.compareTo(b.name);
            });
          final unreadAll = alerts.where((a) => !a.isRead).length;

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
            children: [
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => showSendEmployeeMessageDialog(context),
                  icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 14),
                  label: const Text('إرسال رسالة للموظفين'),
                ),
              ),
              const SizedBox(height: 10),
              _NavCard(
                icon: FontAwesomeIcons.envelopeOpenText,
                title: 'الرسائل المرسلة',
                subtitle: 'ما أرسلته للموظفين وهل قرأوه',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SentMessagesScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'إشعارات العمليات',
                style: TextStyle(
                  color: AppColors.textMid,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _NavCard(
                icon: FontAwesomeIcons.bell,
                title: 'كل الموظفين',
                subtitle: '${alerts.length} إشعار',
                unread: unreadAll,
                onTap: () => _open(context, null, 'كل الموظفين'),
              ),
              for (final g in list) ...[
                const SizedBox(height: 10),
                _NavCard(
                  icon: FontAwesomeIcons.userTie,
                  title: g.name,
                  subtitle: g.alerts.isEmpty
                      ? 'لا توجد إشعارات'
                      : '${g.alerts.length} إشعار · آخرها '
                          '${_dateFmt.format(g.alerts.first.createdAt)}',
                  unread: g.alerts.where((a) => !a.isRead).length,
                  onTap: () => _open(context, g.key, g.name),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _open(BuildContext context, String? key, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeAlertsListScreen(groupKey: key, title: title),
      ),
    );
  }
}

class _Group {
  _Group({required this.key, required this.name});
  final String key;
  final String name;

  /// Newest first (the provider already returns them that way).
  final List<EmployeeAlert> alerts = [];
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.unread = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: FaIcon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textHigh,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0) ...[
                _CountBadge(count: unread),
                const SizedBox(width: 8),
              ],
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 14,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.negative,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A numbered statement of one employee's alerts (or everyone's when
/// [groupKey] is null). The oldest is #1, so the numbers grow with time.
class EmployeeAlertsListScreen extends ConsumerWidget {
  const EmployeeAlertsListScreen({
    super.key,
    required this.groupKey,
    required this.title,
  });

  final String? groupKey;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeeAlertsProvider);
    final all = async.valueOrNull ?? const <EmployeeAlert>[];
    final alerts = groupKey == null
        ? all
        : all.where((a) => _groupKey(a) == groupKey).toList();
    final unreadIds = [
      for (final a in alerts)
        if (!a.isRead) a.id,
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('إشعارات: $title'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          if (unreadIds.isNotEmpty)
            IconButton(
              tooltip: 'تعليم الكل كمقروء',
              icon: const FaIcon(FontAwesomeIcons.checkDouble, size: 14),
              onPressed: () async {
                await ref
                    .read(employeeAlertsRepositoryProvider)
                    .markAlertsRead(unreadIds);
                ref.invalidate(employeeAlertsProvider);
              },
            ),
        ],
      ),
      body: async.isLoading && all.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : alerts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text(
                      'لا توجد إشعارات بعد.',
                      style: TextStyle(color: AppColors.textLow),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(employeeAlertsProvider);
                    await ref.read(employeeAlertsProvider.future);
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
                    itemCount: alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _AlertTile(
                      number: alerts.length - i,
                      alert: alerts[i],
                      showEmployee: groupKey == null,
                    ),
                  ),
                ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({
    required this.number,
    required this.alert,
    required this.showEmployee,
  });

  final int number;
  final EmployeeAlert alert;
  final bool showEmployee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = alert.isExit;
    final color = alert.isCancelRequest
        ? AppColors.cancelled
        : isOut
            ? AppColors.negative
            : AppColors.positive;
    final party =
        (alert.partyName ?? '').trim().isEmpty ? '—' : alert.partyName!.trim();

    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetails(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 40),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '#$number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.isCancelRequest ? 'طلب إلغاء ' : ''}'
                      '${alert.directionLabel} · \$${formatMoney(alert.amount)}'
                      ' · $party',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textHigh,
                        fontSize: 13,
                        fontWeight:
                            alert.isRead ? FontWeight.w500 : FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${showEmployee ? '${alert.employeeName} · ' : ''}'
                      '${_dateFmt.format(alert.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!alert.isRead)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetails(BuildContext context, WidgetRef ref) async {
    if (!alert.isRead) {
      // Fire and forget: opening is what marks it read.
      ref
          .read(employeeAlertsRepositoryProvider)
          .markAlertsRead([alert.id])
          .then((_) => ref.invalidate(employeeAlertsProvider))
          .catchError((Object e) {
        AppLogger.warning('[alerts] mark read failed: $e');
      });
    }
    await showGlassDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'إشعار #$number',
                  style: const TextStyle(
                    color: AppColors.textMid,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  alertText(alert),
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 15,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'التاريخ والزمن: ${_dateFmt.format(alert.createdAt)}',
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                if (alert.isCancelRequest) ...[
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.cancelled,
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CancellationsScreen(),
                        ),
                      );
                    },
                    child: const Text('فتح طلبات الإلغاء'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the admin has sent: one card per message (a broadcast to several
/// employees is one card), with how many of the recipients have read it.
class SentMessagesScreen extends ConsumerWidget {
  const SentMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sentMessagesProvider);
    final employees = {
      for (final e in ref.watch(subUsersListProvider).valueOrNull ?? const [])
        e.id: e.employeeName,
    };

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الرسائل المرسلة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(sentMessagesProvider),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              friendlyError(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textLow),
            ),
          ),
        ),
        data: (messages) {
          if (messages.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'لم ترسل أي رسالة بعد.',
                  style: TextStyle(color: AppColors.textLow),
                ),
              ),
            );
          }
          final byBroadcast = <String, List<EmployeeMessage>>{};
          for (final m in messages) {
            byBroadcast.putIfAbsent(m.broadcastId, () => []).add(m);
          }
          final items = byBroadcast.values.toList();
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final group = items[i];
              final first = group.first;
              final read = group.where((m) => m.isRead).length;
              final names = group
                  .map((m) => employees[m.subUserId] ?? '—')
                  .toList()
                ..sort();
              return GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (first.title ?? '').isEmpty
                                ? 'رسالة'
                                : first.title!,
                            style: const TextStyle(
                              color: AppColors.textHigh,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'حذف',
                          visualDensity: VisualDensity.compact,
                          icon: const FaIcon(
                            FontAwesomeIcons.trashCan,
                            size: 14,
                            color: AppColors.negative,
                          ),
                          onPressed: () async {
                            await ref
                                .read(employeeAlertsRepositoryProvider)
                                .deleteMessages(
                                  group.map((m) => m.id).toList(),
                                );
                            ref.invalidate(sentMessagesProvider);
                          },
                        ),
                      ],
                    ),
                    Text(
                      first.body,
                      style: const TextStyle(
                        color: AppColors.textMid,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'إلى: ${names.join('، ')}',
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_dateFmt.format(first.createdAt)} · '
                      'قرأها $read من ${group.length}',
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
