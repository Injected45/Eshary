import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../domain/cancellation.dart';
import 'cancel_operation_dialog.dart';
import 'cancellations_providers.dart';

/// The bottom of an operation's details page:
///   * cancelled → a purple "عملية ملغاة" banner;
///   * today, admin → "إلغاء العملية" (reason + password), showing an
///     employee's open request when there is one;
///   * today, employee → "طلب إلغاء", or "بانتظار المدير" once sent;
///   * an earlier day → nothing (the database would refuse it anyway).
class OperationCancelBar extends ConsumerWidget {
  const OperationCancelBar({
    super.key,
    required this.kind,
    required this.operationId,
    required this.amount,
    required this.createdAt,
    required this.cancelledAt,
    this.partyName,
  });

  final OperationKind kind;
  final String operationId;
  final double amount;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final String? partyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cancelledAt != null) {
      return _Banner(
        text: 'عملية ملغاة — '
            '${DateFormat('yyyy/MM/dd  HH:mm').format(cancelledAt!.toLocal())}\n'
            'أُعيد الرصيد بقيد عكسي.',
      );
    }
    if (!canCancelToday(createdAt: createdAt, cancelledAt: cancelledAt)) {
      return const SizedBox.shrink();
    }

    final isEmployee = ref.watch(isEmployeeProvider);
    final pending = ref.watch(pendingRequestForProvider(operationId));

    if (isEmployee) {
      if (pending != null) {
        return const _Banner(text: 'طلب الإلغاء مُرسل وبانتظار المدير.');
      }
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cancelled,
          side: const BorderSide(color: AppColors.cancelled),
          minimumSize: const Size.fromHeight(46),
        ),
        icon: const Icon(Icons.undo_rounded, size: 18),
        label: const Text('طلب إلغاء العملية'),
        onPressed: () => showCancelRequestDialog(
          context,
          kind: kind,
          operationId: operationId,
          amount: amount,
          partyName: partyName,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending != null) ...[
          _Banner(
            text: 'طلب إلغاء من الموظف ${pending.employeeName}\n'
                'السبب: ${pending.reason}',
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.cancelled,
            minimumSize: const Size.fromHeight(46),
          ),
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: Text(pending != null ? 'الموافقة وإلغاء العملية' : 'إلغاء العملية'),
          onPressed: () async {
            final done = await showAdminCancelDialog(
              context,
              kind: kind,
              operationId: operationId,
              amount: amount,
              partyName: partyName,
              requestId: pending?.id,
              initialReason: pending?.reason,
            );
            if (done && context.mounted) Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cancelled.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cancelled.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.cancelled,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ),
    );
  }
}
