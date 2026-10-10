import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../data/trial_admin_repository.dart';
import '../domain/trial_models.dart';
import 'audit_alerts_screen.dart';
import 'phone_changes_admin_screen.dart';
import 'phone_input.dart';

/// The administrator's trial requests: filters, indicators, and the decisions
/// (3 days, 1 week, ask for information, reject, withdraw, renew an expired
/// approval, fix the phone, resend the code). The request status, the
/// subscription status and the WhatsApp message status are shown apart.
class TrialRequestsScreen extends ConsumerStatefulWidget {
  const TrialRequestsScreen({super.key});

  @override
  ConsumerState<TrialRequestsScreen> createState() =>
      _TrialRequestsScreenState();
}

const _filters = <(String, String)>[
  ('', 'الكل'),
  ('pending_review', 'قيد المراجعة'),
  ('needs_info', 'تحتاج معلومات'),
  ('approved_waiting', 'موافَق عليها'),
  ('message_failed', 'فشل الرسالة'),
  ('approval_expired', 'موافقة منتهية'),
  ('active_trial', 'تجربة فعّالة'),
  ('ending_soon', 'تنتهي قريباً'),
  ('expired_trial', 'تجربة منتهية'),
  ('paid', 'مدفوعة'),
  ('rejected_or_suspended', 'مرفوضة / موقوفة'),
];

class _TrialRequestsScreenState extends ConsumerState<TrialRequestsScreen> {
  String _filter = '';

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      ref.invalidate(trialRequestsProvider);
      ref.invalidate(trialStatsProvider);
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text(done)));
    } catch (e, st) {
      AppLogger.error('admin.trial', e, st);
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(
          backgroundColor: AppColors.negative.withValues(alpha: 0.85),
          content: Text(
            friendlyError(e),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<String?> _ask(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(TrialRequestRow r, String decision) async {
    String? note;
    if (decision == 'request_info') {
      note = await _ask('ما المعلومات المطلوبة؟', 'تظهر للمتقدّم');
      if (note == null || note.isEmpty) return;
    } else if (decision == 'reject') {
      note = await _ask('سبب الرفض', 'يظهر للمتقدّم');
      if (note == null || note.isEmpty) return;
    }
    await _run(
      () => ref.read(trialAdminRepositoryProvider).decide(
            r.id,
            decision,
            note: note,
          ),
      'تم تنفيذ القرار',
    );
  }

  Future<void> _fixPhone(TrialRequestRow r) async {
    var phone = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تصحيح رقم الهاتف'),
          content: PhoneInput(onChanged: (v) => phone = v),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(trialAdminRepositoryProvider).fixPhone(r.id, phone),
      'تم تصحيح الرقم وسُجّل التغيير',
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trialRequestsProvider);
    final stats = ref.watch(trialStatsProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('طلبات التجربة'),
        actions: [
          IconButton(
            key: const ValueKey('phone-changes'),
            tooltip: 'طلبات تغيير الرقم',
            icon: const FaIcon(FontAwesomeIcons.phoneFlip, size: 15),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PhoneChangesAdminScreen(),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('audit-alerts'),
            tooltip: 'التنبيهات وسجل التدقيق',
            icon: const FaIcon(FontAwesomeIcons.bell, size: 15),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AuditAlertsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (stats != null) _Kpis(stats: stats),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final (key, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _filter == key,
                        onSelected: (_) => setState(() => _filter = key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(trialRequestsProvider);
                  ref.invalidate(trialStatsProvider);
                  await ref.read(trialRequestsProvider.future);
                },
                child: async.when(
                  skipLoadingOnReload: true,
                  skipError: true,
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          friendlyError(e),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textHigh),
                        ),
                      ),
                    ],
                  ),
                  data: (all) {
                    final rows = _filter.isEmpty
                        ? all
                        : all.where((r) => r.bucket == _filter).toList();
                    if (rows.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 40),
                          Center(
                            child: Text(
                              'لا توجد طلبات',
                              style: TextStyle(color: AppColors.textLow),
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        contentBottomPadding(context),
                      ),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _RequestCard(
                        row: rows[i],
                        onDecide: (d) => _decide(rows[i], d),
                        onFixPhone: () => _fixPhone(rows[i]),
                        onResend: () => _run(
                          () => ref
                              .read(trialAdminRepositoryProvider)
                              .resendCode(rows[i].id),
                          'أُرسل رمز جديد',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    String pct(Object? v) =>
        '${(((v as num?) ?? 0) * 100).toStringAsFixed(0)}%';
    final wait = ((stats['avgApprovalWaitSeconds'] as num?) ?? 0) / 3600;
    Widget cell(String k, String v) => Expanded(
          child: Column(
            children: [
              Text(
                v,
                style: const TextStyle(
                  color: AppColors.textHigh,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                k,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.textLow, fontSize: 10.5),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            cell('الطلبات', '${stats['requests'] ?? 0}'),
            cell('التفعيل', pct(stats['activationRate'])),
            cell('التحويل لمدفوع', pct(stats['conversionRate'])),
            cell('متوسط الانتظار (س)', wait.toStringAsFixed(1)),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.row,
    required this.onDecide,
    required this.onFixPhone,
    required this.onResend,
  });

  final TrialRequestRow row;
  final void Function(String decision) onDecide;
  final VoidCallback onFixPhone;
  final VoidCallback onResend;

  String _fmt(DateTime? t) {
    if (t == null) return '—';
    final l = t.toUtc().add(const Duration(hours: 2)); // Africa/Tripoli
    String p(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = row;
    final open = r.status == 'pending_review' || r.status == 'needs_info';
    final approved = r.status == 'approved';
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.businessName,
            style: const TextStyle(
              color: AppColors.textHigh,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          Text(
            r.managerName,
            style: const TextStyle(color: AppColors.textMid, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.whatsapp,
                size: 13,
                color: AppColors.positive,
              ),
              const SizedBox(width: 6),
              Text(
                r.phone,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: AppColors.textMid, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                r.phoneVerified ? 'مؤكَّد' : 'غير مؤكَّد',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      r.phoneVerified ? AppColors.positive : AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('الطلب: ${_requestLabel(r.status)}', AppColors.accent),
              if (r.messageStatus != null)
                _chip(
                  'الرسالة: ${_msgLabel(r.messageStatus!)}',
                  r.messageStatus == 'failed'
                      ? AppColors.negative
                      : AppColors.positive,
                ),
              if (r.userId != null)
                _chip('الاشتراك: ${_bucketLabel(r.bucket)}', AppColors.warning),
              if (r.repeatHint > 0)
                _chip('تشابه مع ${r.repeatHint} طلب', AppColors.negative),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'قُدّم: ${_fmt(r.requestedAt)}'
            '${r.approvalExpiresAt != null && approved ? '\nتنتهي الموافقة: ${_fmt(r.approvalExpiresAt)}' : ''}'
            '${r.trialEndsAt != null ? '\nتنتهي التجربة: ${_fmt(r.trialEndsAt)}' : ''}',
            style: const TextStyle(color: AppColors.textLow, fontSize: 11.5),
          ),
          if ((r.reviewNote ?? '').isNotEmpty)
            Text(
              'ملاحظة: ${r.reviewNote}',
              style: const TextStyle(color: AppColors.textMid, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (open) ...[
                FilledButton(
                  key: const ValueKey('approve-72'),
                  onPressed: () => onDecide('approve_72'),
                  child: const Text('موافقة 3 أيام'),
                ),
                FilledButton(
                  key: const ValueKey('approve-168'),
                  onPressed: () => onDecide('approve_168'),
                  child: const Text('موافقة أسبوع'),
                ),
                OutlinedButton(
                  onPressed: () => onDecide('request_info'),
                  child: const Text('طلب معلومات'),
                ),
                OutlinedButton(
                  onPressed: () => onDecide('reject'),
                  child: const Text('رفض'),
                ),
                TextButton(
                  onPressed: onFixPhone,
                  child: const Text('تصحيح الرقم'),
                ),
              ],
              if (approved) ...[
                OutlinedButton(
                  onPressed: onResend,
                  child: const Text('إعادة إرسال الرمز'),
                ),
                if (r.bucket == 'approval_expired')
                  FilledButton(
                    onPressed: () => onDecide('renew_approval'),
                    child: const Text('تجديد الموافقة'),
                  ),
                TextButton(
                  onPressed: () => onDecide('withdraw'),
                  child: const Text('سحب الموافقة'),
                ),
                TextButton(
                  onPressed: onFixPhone,
                  child: const Text('تصحيح الرقم'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );

  String _requestLabel(String s) => switch (s) {
        'pending_review' => 'قيد المراجعة',
        'needs_info' => 'تحتاج معلومات',
        'approved' => 'موافَق عليه',
        'rejected' => 'مرفوض',
        'activated' => 'مُفعَّل',
        _ => s,
      };

  String _msgLabel(String s) => switch (s) {
        'queued' => 'في الانتظار',
        'sent' => 'أُرسلت',
        'failed' => 'فشلت',
        _ => s,
      };

  String _bucketLabel(String s) => switch (s) {
        'active_trial' => 'تجربة فعّالة',
        'ending_soon' => 'تنتهي قريباً',
        'expired_trial' => 'تجربة منتهية',
        'paid' => 'مدفوع',
        'rejected_or_suspended' => 'موقوف',
        _ => s,
      };
}
