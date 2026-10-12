import 'dart:async';

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

/// Five groups instead of eleven states. The exact state of each request
/// (message failed, approval expired, ending soon ...) stays on its card.
const _filters = <(String, String, Set<String>)>[
  ('decide', 'تنتظر قراري', {'pending_review', 'needs_info'}),
  (
    'activate',
    'بانتظار التفعيل',
    {'approved_waiting', 'message_failed', 'approval_expired'},
  ),
  ('active', 'فعّالة', {'active_trial', 'ending_soon', 'paid'}),
  ('closed', 'منتهية أو مغلقة', {'expired_trial', 'rejected_or_suspended'}),
  ('', 'الكل', <String>{}),
];

class _TrialRequestsScreenState extends ConsumerState<TrialRequestsScreen> {
  /// It opens on what needs a decision, the one thing the administrator came for.
  String _filter = 'decide';
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    // a new request appears by itself while the screen is open
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(trialRequestsProvider);
    ref.invalidate(trialStatsProvider);
    ref.invalidate(adminPendingCountsProvider);
  }

  /// Runs an action; its result is a message for the administrator (or null for
  /// the default one).
  Future<void> _run(Future<String?> Function() action, String done) async {
    try {
      final custom = await action();
      _reload();
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text(custom ?? done)));
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
    await _run(() async {
      final res = await ref
          .read(trialAdminRepositoryProvider)
          .decide(r.id, decision, note: note);
      return _decisionMessage(r, decision, res);
    }, 'تم تنفيذ القرار');
  }

  /// What the administrator reads after pressing a decision: what happened and
  /// what the applicant has been told.
  String _decisionMessage(
    TrialRequestRow r,
    String decision,
    Map<String, dynamic> res,
  ) {
    switch (decision) {
      case 'approve_72':
      case 'approve_168':
      case 'renew_approval':
        final m = res['message'];
        final sent = m is Map && m['ok'] == true;
        return sent
            ? 'تمت الموافقة وأُرسل رمز التفعيل إلى واتساب ${r.managerName}.'
            : 'تمت الموافقة، لكن تعذّر إرسال الرمز الآن. اضغط «إعادة إرسال الرمز» على بطاقته.';
      case 'request_info':
        return 'أُرسل طلب المعلومات إلى ${r.managerName} على واتساب وسيراه في التطبيق.';
      case 'reject':
        return 'تم رفض الطلب وسيرى المتقدّم السبب.';
      case 'withdraw':
        return 'سُحبت الموافقة وعاد الطلب إلى المراجعة.';
      default:
        return 'تم تنفيذ القرار';
    }
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
    await _run(() async {
      await ref.read(trialAdminRepositoryProvider).fixPhone(r.id, phone);
      return null;
    }, 'تم تصحيح الرقم وسُجّل التغيير');
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
                  for (final (key, label, _) in _filters)
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
                        : all
                            .where(
                              (r) => _filters
                                  .firstWhere((f) => f.$1 == _filter)
                                  .$3
                                  .contains(r.bucket),
                            )
                            .toList();
                    if (rows.isEmpty) {
                      return ListView(
                        children: [
                          const SizedBox(height: 40),
                          Center(
                            child: Text(
                              _filter == 'decide'
                                  ? 'لا توجد طلبات تنتظر قرارك ✓'
                                  : 'لا توجد طلبات',
                              key: const ValueKey('requests-empty'),
                              style: const TextStyle(color: AppColors.textLow),
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
                        onResend: () => _run(() async {
                          await ref
                              .read(trialAdminRepositoryProvider)
                              .resendCode(rows[i].id);
                          return null;
                        }, 'أُرسل رمز جديد إلى واتساب المتقدّم'),
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

  /// "قبل 5 دقائق" instead of a date to decode.
  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'الآن';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }

  /// The state of the request in one sentence, with its colour.
  (String, Color) _statusLine() {
    final r = row;
    switch (r.bucket) {
      case 'pending_review':
        return ('طلب جديد ينتظر قرارك', AppColors.warning);
      case 'needs_info':
        return ('بانتظار ردّ المتقدّم على طلب المعلومات', AppColors.textMid);
      case 'message_failed':
        return ('تمت الموافقة لكن لم يصل الرمز', AppColors.negative);
      case 'approval_expired':
        return ('انتهت صلاحية الموافقة', AppColors.negative);
      case 'approved_waiting':
        return (
          'تمت الموافقة، بانتظار أن يُدخل المتقدّم الرمز',
          AppColors.accent
        );
      case 'active_trial':
      case 'ending_soon':
        final left = r.remainingSeconds;
        final days = left == null ? null : (left / 86400).ceil();
        return (
          days == null ? 'تجربة فعّالة' : 'تجربة فعّالة، متبقي $days يوم',
          AppColors.positive,
        );
      case 'paid':
        return ('مشترك', AppColors.positive);
      case 'expired_trial':
        return ('انتهت التجربة', AppColors.negative);
      default:
        return (r.status == 'rejected' ? 'مرفوض' : 'موقوف', AppColors.negative);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = row;
    final open = r.status == 'pending_review' || r.status == 'needs_info';
    final approved = r.status == 'approved';
    final (status, statusColor) = _statusLine();
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.businessName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                _ago(r.requestedAt),
                style: const TextStyle(color: AppColors.textLow, fontSize: 11),
              ),
            ],
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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status,
            key: const ValueKey('request-status'),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (r.repeatHint > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child:
                  _chip('تشابه مع ${r.repeatHint} طلب آخر', AppColors.negative),
            ),
          if ((r.reviewNote ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ملاحظتك: ${r.reviewNote}',
                style: const TextStyle(color: AppColors.textMid, fontSize: 12),
              ),
            ),
          if (open || approved) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (open) ...[
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('approve-72'),
                      onPressed: () => onDecide('approve_72'),
                      child: const Text('موافقة 3 أيام'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('approve-168'),
                      onPressed: () => onDecide('approve_168'),
                      child: const Text('موافقة أسبوع'),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('resend-code'),
                      onPressed: r.bucket == 'approval_expired'
                          ? () => onDecide('renew_approval')
                          : onResend,
                      child: Text(
                        r.bucket == 'approval_expired'
                            ? 'تجديد الموافقة'
                            : 'إعادة إرسال الرمز',
                      ),
                    ),
                  ),
                ],
                PopupMenuButton<String>(
                  key: const ValueKey('request-menu'),
                  icon: const FaIcon(
                    FontAwesomeIcons.ellipsisVertical,
                    size: 16,
                    color: AppColors.textLow,
                  ),
                  onSelected: (v) {
                    if (v == 'fix_phone') {
                      onFixPhone();
                    } else {
                      onDecide(v);
                    }
                  },
                  itemBuilder: (_) => [
                    if (open) ...const [
                      PopupMenuItem(
                        value: 'request_info',
                        child: Text('طلب معلومات'),
                      ),
                      PopupMenuItem(
                        value: 'reject',
                        child: Text(
                          'رفض',
                          style: TextStyle(color: AppColors.negative),
                        ),
                      ),
                    ],
                    if (approved)
                      const PopupMenuItem(
                        value: 'withdraw',
                        child: Text('سحب الموافقة'),
                      ),
                    const PopupMenuItem(
                      value: 'fix_phone',
                      child: Text('تصحيح رقم الهاتف'),
                    ),
                  ],
                ),
              ],
            ),
          ],
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
}
