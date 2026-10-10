import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../data/trial_repository.dart';
import '../domain/trial_models.dart';

/// Time left, from the server's answer plus the monotonic time since it
/// arrived (the phone's clock is never read). Null when there is no trial.
Duration? remainingOf(SubscriptionState s) {
  final base = s.remainingSeconds;
  if (base == null) return null;
  final passed = kMonotonic.elapsedMilliseconds - s.receivedAtTicks;
  final left = base * 1000 - passed;
  return Duration(milliseconds: left < 0 ? 0 : left);
}

String formatRemaining(Duration d) {
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return '$days يوم و$hours ساعة';
  if (d.inHours > 0) return '${d.inHours} ساعة و$minutes دقيقة';
  if (d.inMinutes > 0) return '$minutes دقيقة';
  return 'أقل من دقيقة';
}

/// Libya time (UTC+2, no daylight saving) for display only.
String formatTripoli(DateTime utc) {
  final l = utc.toUtc().add(const Duration(hours: 2));
  String p(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${p(l.month)}-${p(l.day)} ${p(l.hour)}:${p(l.minute)}';
}

/// "اشتراكي": the state the server reports, what is allowed, and the requests
/// for a subscription or an extension. After expiry the data stays readable.
class SubscriptionScreen extends ConsumerWidget {
  const SubscriptionScreen({super.key});

  Future<void> _request(
      BuildContext context, WidgetRef ref, String kind) async {
    try {
      await ref.read(trialRepositoryProvider).subscriptionRequest(kind);
      if (context.mounted) {
        showTopSnackBar(
          context,
          const SnackBar(content: Text('أُرسل طلبك إلى الإدارة.')),
        );
      }
    } catch (e, st) {
      AppLogger.error('subscription.request', e, st);
      if (context.mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subscriptionStateProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: const Text('اشتراكي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            async.when(
              skipLoadingOnReload: true,
              skipError: true,
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (e, _) => const GlassCard(
                padding: EdgeInsets.all(20),
                child: Text(
                  'لا يوجد اتصال بالإنترنت. تتوقف العمليات المحمية حتى يعود الاتصال بالخادم.',
                  key: ValueKey('offline-notice'),
                  style: TextStyle(color: AppColors.warning),
                ),
              ),
              data: (s) => _body(context, ref, s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, SubscriptionState s) {
    final (label, color, text) = switch (s.status) {
      'trial' => (
          'فترة تجريبية',
          AppColors.warning,
          'تعمل الآن بكل المزايا حتى انتهاء المدة.',
        ),
      'paid' => ('مشترك', AppColors.positive, 'اشتراكك فعّال.'),
      'expired' => (
          'انتهى الاشتراك',
          AppColors.negative,
          'بياناتك محفوظة ويمكنك الاطلاع عليها وتصديرها، لكن لا يمكن إضافة عمليات أو تعديلها حتى الاشتراك.',
        ),
      'suspended' => (
          'موقوف',
          AppColors.negative,
          'أوقفت الإدارة الحساب. تواصل مع الدعم.',
        ),
      'time_untrusted' => (
          'تعذّر التحقق من الوقت',
          AppColors.warning,
          'تراجعت ساعة الخادم عن آخر وقت مسجَّل، فتوقفت العمليات مؤقتاً. تواصل مع الدعم.',
        ),
      _ => ('بانتظار التفعيل', AppColors.warning, ''),
    };
    final left = remainingOf(s);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMid, height: 1.6),
            ),
          ],
          if (s.status == 'trial' && left != null) ...[
            const SizedBox(height: 14),
            _row(FontAwesomeIcons.hourglassHalf, 'المتبقي',
                formatRemaining(left)),
          ],
          if (s.trialEndsAt != null) ...[
            const SizedBox(height: 8),
            _row(
              FontAwesomeIcons.clock,
              s.status == 'trial' ? 'تنتهي في' : 'انتهت في',
              formatTripoli(s.trialEndsAt!),
            ),
          ],
          const SizedBox(height: 8),
          _row(
            FontAwesomeIcons.shieldHalved,
            'المسموح',
            s.canWrite
                ? 'قراءة وكتابة وتصدير'
                : (s.allowedActions.contains('read')
                    ? 'قراءة وتصدير فقط'
                    : 'لا شيء'),
          ),
          if (s.status == 'expired' || s.status == 'trial') ...[
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('request-subscribe'),
              onPressed: () => _request(context, ref, 'subscribe'),
              child: const Text('طلب اشتراك'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('request-extend'),
              onPressed: () => _request(context, ref, 'extend'),
              child: const Text('طلب تمديد التجربة'),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('change-phone'),
            onPressed: () => context.push('/phone-change'),
            child: const Text('تغيير رقم واتساب'),
          ),
          TextButton(
            onPressed: () => ref.invalidate(subscriptionStateProvider),
            child: const Text('تحديث من الخادم'),
          ),
          TextButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String k, String v) => Row(
        children: [
          FaIcon(icon, size: 14, color: AppColors.textLow),
          const SizedBox(width: 10),
          Text(k, style: const TextStyle(color: AppColors.textLow)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.textHigh,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}
