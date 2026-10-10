import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/trial_admin_repository.dart';
import 'subscription_screen.dart' show formatTripoli;

final _auditProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(trialAdminRepositoryProvider).audit();
});

final _alertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(trialAdminRepositoryProvider).alerts();
});

const _kindLabels = <String, String>{
  'trial_requested': 'طلب تجربة جديد',
  'trial_approve_72': 'موافقة 3 أيام',
  'trial_approve_168': 'موافقة أسبوع',
  'trial_request_info': 'طلب معلومات',
  'trial_reject': 'رفض',
  'trial_withdraw': 'سحب موافقة',
  'trial_renew_approval': 'تجديد موافقة',
  'trial_phone_changed': 'تغيير رقم الهاتف',
  'trial_code_resent': 'إعادة إرسال رمز',
  'trial_activated': 'تفعيل التجربة',
  'activation_failed': 'محاولة تفعيل فاشلة',
  'trial_extended': 'تمديد تجربة',
  'payment_confirmed': 'تأكيد دفع',
  'account_suspended': 'إيقاف حساب',
  'account_reactivated': 'إعادة تفعيل',
  'time_anomaly': 'تراجع ساعة الخادم',
  'time_guard_reset': 'إعادة ضبط الحارس الزمني',
  'login': 'دخول',
  'sub_request_subscribe': 'طلب اشتراك',
  'sub_request_extend': 'طلب تمديد',
};

/// Two lists for the administrator: alerts (new requests, subscription
/// requests, clock problems) and the append-only audit log.
class AuditAlertsScreen extends ConsumerWidget {
  const AuditAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: const Text('التنبيهات وسجل التدقيق'),
        ),
        body: SafeArea(
          child: Column(children: [
            const TabBar(
              tabs: [Tab(text: 'التنبيهات'), Tab(text: 'سجل التدقيق')],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _list(
                    context,
                    ref.watch(_alertsProvider),
                    () => ref.invalidate(_alertsProvider),
                    (r) => (
                      _kindLabels[r['kind']] ?? (r['kind'] as String? ?? ''),
                      r['body'] as String? ?? '',
                      r['created_at'] as String?,
                    ),
                  ),
                  _list(
                    context,
                    ref.watch(_auditProvider),
                    () => ref.invalidate(_auditProvider),
                    (r) => (
                      _kindLabels[r['kind']] ?? (r['kind'] as String? ?? ''),
                      [
                        if (r['actor_email'] != null) '${r['actor_email']}',
                        if ((r['note'] as String?)?.isNotEmpty ?? false)
                          '${r['note']}',
                      ].join(' — '),
                      r['at'] as String?,
                    ),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    AsyncValue<List<Map<String, dynamic>>> async,
    VoidCallback reload,
    (String, String, String?) Function(Map<String, dynamic>) map,
  ) {
    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [Text(friendlyError(e))],
        ),
        data: (rows) => rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 40),
                  Center(
                    child: Text(
                      'لا توجد عناصر',
                      style: TextStyle(color: AppColors.textLow),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  contentBottomPadding(context),
                ),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final (title, body, at) = map(rows[i]);
                  return GlassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textHigh,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (body.isNotEmpty)
                          Text(
                            body,
                            style: const TextStyle(
                              color: AppColors.textMid,
                              fontSize: 12.5,
                            ),
                          ),
                        if (at != null)
                          Text(
                            formatTripoli(DateTime.parse(at)),
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
      ),
    );
  }
}
