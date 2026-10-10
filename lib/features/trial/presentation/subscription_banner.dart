import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../license/presentation/license_provider.dart';
import '../data/trial_repository.dart';
import '../domain/trial_models.dart';
import 'subscription_screen.dart';

/// A thin strip over the whole app for a signed-in subscriber: the time left in
/// the trial (the server's figure, counted down with monotonic time and
/// re-read from the server on resume and every few minutes) or, once the trial
/// is over, "read only". Nothing is shown to employees, to the platform
/// administrator or when signed out.
class SubscriptionBanner extends ConsumerStatefulWidget {
  const SubscriptionBanner({
    super.key,
    required this.child,
    required this.onOpen,
  });

  final Widget child;

  /// Opens the subscription screen (the banner sits above the Navigator).
  final VoidCallback onOpen;

  @override
  ConsumerState<SubscriptionBanner> createState() => _SubscriptionBannerState();
}

class _SubscriptionBannerState extends ConsumerState<SubscriptionBanner>
    with WidgetsBindingObserver {
  Timer? _tick;
  Timer? _resync;
  bool _expiredHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _resync = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _resync?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: the phone may have been offline or its clock
    // changed, so the server is asked again.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    _expiredHandled = false;
    ref.invalidate(subscriptionStateProvider);
    ref.invalidate(licenseStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUserIdProvider);
    final user = ref.watch(supabaseClientProvider).auth.currentUser;
    if (uid == null || user == null || user.isAnonymous) return widget.child;

    final s = ref.watch(subscriptionStateProvider).valueOrNull;
    if (s == null) return widget.child;
    final banner = _bannerFor(s);
    if (banner == null) return widget.child;

    return Column(
      children: [
        Material(
          color: banner.$2.withValues(alpha: 0.9),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              key: const ValueKey('subscription-banner'),
              onTap: widget.onOpen,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        banner.$1,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Text(
                      'التفاصيل',
                      style: TextStyle(color: Colors.black, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }

  (String, Color)? _bannerFor(SubscriptionState s) {
    switch (s.status) {
      case 'trial':
        final left = remainingOf(s);
        if (left == null) return null;
        if (left == Duration.zero && !_expiredHandled) {
          // The countdown reached zero: ask the server what it says now.
          _expiredHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.invalidate(subscriptionStateProvider);
              ref.invalidate(licenseStatusProvider);
            }
          });
        }
        return (
          'فترة تجريبية — المتبقي ${formatRemaining(left)}',
          left.inHours < 24 ? AppColors.negative : AppColors.warning,
        );
      case 'expired':
        return (
          'انتهى الاشتراك — القراءة والتصدير فقط. اضغط لطلب الاشتراك.',
          AppColors.negative,
        );
      case 'time_untrusted':
        return (
          'تعذّر التحقق من الوقت على الخادم — العمليات متوقفة مؤقتاً.',
          AppColors.warning,
        );
      default:
        return null;
    }
  }
}
