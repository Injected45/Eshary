import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/employee_alerts_repository.dart';
import '../domain/employee_alert.dart';
import 'employee_alerts_providers.dart';

final _dateFmt = DateFormat('yyyy-MM-dd  HH:mm');

/// The employee's inbox: messages from the admin, newest first. Opening the
/// screen marks them read (the unread ones stay highlighted for this visit).
/// Available to every employee, whatever permissions they hold.
class EmployeeInboxScreen extends ConsumerStatefulWidget {
  const EmployeeInboxScreen({super.key});

  @override
  ConsumerState<EmployeeInboxScreen> createState() =>
      _EmployeeInboxScreenState();
}

class _EmployeeInboxScreenState extends ConsumerState<EmployeeInboxScreen> {
  /// Ids that were unread when they first appeared here, to keep them
  /// highlighted while this screen is open.
  final Set<String> _freshIds = {};
  bool _marking = false;

  Future<void> _markRead(List<String> ids) async {
    if (ids.isEmpty || _marking) return;
    _marking = true;
    try {
      await ref.read(employeeAlertsRepositoryProvider).markInboxRead(ids);
      ref.invalidate(employeeInboxProvider);
    } catch (e) {
      AppLogger.warning('[inbox] mark read failed: $e');
    } finally {
      _marking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(employeeInboxProvider);

    ref.listen(employeeInboxProvider, (_, next) {
      final unread = [
        for (final m in next.valueOrNull ?? const <EmployeeMessage>[])
          if (!m.isRead) m.id,
      ];
      if (unread.isEmpty) return;
      _freshIds.addAll(unread);
      _markRead(unread);
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('رسائل المدير'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(employeeInboxProvider),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
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
          // First build: the listener only fires on changes, so handle the
          // data already loaded.
          final unread = [
            for (final m in messages)
              if (!m.isRead) m.id,
          ];
          if (unread.isNotEmpty) {
            _freshIds.addAll(unread);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _markRead(unread));
          }
          if (messages.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  'لا توجد رسائل من المدير.',
                  style: TextStyle(color: AppColors.textLow),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(employeeInboxProvider);
              await ref.read(employeeInboxProvider.future);
            },
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = messages[i];
                final fresh = _freshIds.contains(m.id);
                return GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (fresh)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsetsDirectional.only(end: 8),
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              (m.title ?? '').isEmpty ? 'رسالة' : m.title!,
                              style: const TextStyle(
                                color: AppColors.textHigh,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m.body,
                        style: const TextStyle(
                          color: AppColors.textMid,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _dateFmt.format(m.createdAt),
                        style: const TextStyle(
                          color: AppColors.textLow,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
