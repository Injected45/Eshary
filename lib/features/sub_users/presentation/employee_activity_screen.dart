import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/activity_logs_repository.dart';
import '../domain/activity_log.dart';
import '../domain/sub_user.dart';

/// Chronological log of everything a single employee has done — opened
/// by the admin from the إدارة الموظفين screen. Useful for audit and
/// dispute resolution.
class EmployeeActivityScreen extends ConsumerWidget {
  const EmployeeActivityScreen({super.key, required this.subUser});

  final SubUser subUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subUserActivityLogsProvider(subUser.id));
    final dateFmt = DateFormat('yyyy-MM-dd  hh:mm a');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('سجل نشاط: ${subUser.employeeName}'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            tooltip: 'تحديث',
            onPressed: () =>
                ref.invalidate(subUserActivityLogsProvider(subUser.id)),
          ),
        ],
      ),
      body: async.when(
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
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FaIcon(
                      FontAwesomeIcons.fileLines,
                      size: 36,
                      color: AppColors.textLow,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'لا توجد عمليات مسجّلة بعد لهذا الموظف',
                      style: TextStyle(
                        color: AppColors.textLow,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _LogTile(log: logs[i], dateFmt: dateFmt),
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.dateFmt});

  final ActivityLog log;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final accent = _colorFor(log.eventType);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.15),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: FaIcon(_iconFor(log.eventType), size: 14, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activityEventLabel(log.eventType),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateFmt.format(log.createdAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textLow,
                  ),
                ),
              ],
            ),
          ),
          if (log.amount != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                '\$${formatMoney(log.amount!)}',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _colorFor(ActivityEventType t) {
    switch (t) {
      case ActivityEventType.login:
      case ActivityEventType.logout:
        return AppColors.accent;
      case ActivityEventType.transferCreated:
        return AppColors.negative;
      case ActivityEventType.currencyBuyCreated:
        return AppColors.positive;
      case ActivityEventType.pendingBuyCreated:
        return AppColors.warning;
      case ActivityEventType.unknown:
        return AppColors.textLow;
    }
  }

  IconData _iconFor(ActivityEventType t) {
    switch (t) {
      case ActivityEventType.login:
        return FontAwesomeIcons.rightToBracket;
      case ActivityEventType.logout:
        return FontAwesomeIcons.rightFromBracket;
      case ActivityEventType.transferCreated:
        return FontAwesomeIcons.paperPlane;
      case ActivityEventType.currencyBuyCreated:
        return FontAwesomeIcons.moneyBillTransfer;
      case ActivityEventType.pendingBuyCreated:
        return FontAwesomeIcons.clock;
      case ActivityEventType.unknown:
        return FontAwesomeIcons.circleQuestion;
    }
  }
}
