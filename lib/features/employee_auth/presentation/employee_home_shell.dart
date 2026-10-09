import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/background_alerts.dart';
import '../../../shared/logger.dart';
import '../../../shared/realtime_sync.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/presentation/currency_buy_screen.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../../transfers/presentation/transfers_screen.dart';
import '../../sub_users/domain/employee_permissions.dart';
import '../../archive/presentation/archive_screen.dart';
import '../../companies/presentation/accounts_screen.dart';
import '../../employee_alerts/presentation/employee_alerts_providers.dart';
import '../../employee_alerts/presentation/employee_inbox_screen.dart';
import 'employee_my_account_screen.dart';
import 'employee_records_screen.dart';
import '../data/employee_auth_repository.dart';
import 'employee_auth_providers.dart';

/// Role-aware shell shown after a successful employee login.
///
/// The bottom navigation only exposes tabs the employee is authorised
/// for — role='entry' sees just الدخول, role='exit' sees just الخروج,
/// role='both' sees both. The actual TransfersScreen and CurrencyBuyScreen
/// are reused as-is; their internal admin-only affordances (archive,
/// settings drawer) are gated by `isEmployeeProvider` so the same widget
/// renders a stripped-down version when invoked from this shell.
class EmployeeHomeShell extends ConsumerStatefulWidget {
  const EmployeeHomeShell({super.key});

  @override
  ConsumerState<EmployeeHomeShell> createState() => _EmployeeHomeShellState();
}

class _EmployeeHomeShellState extends ConsumerState<EmployeeHomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // An admin releasing the device, disabling the account or regenerating
    // the code changes the database, not this phone. Without a re-read the
    // employee would keep seeing the app until a restart, so re-check the
    // session on resume and every 45 seconds. A refresh keeps the current
    // screen (and any half-typed form) in place until the answer arrives.
    WidgetsBinding.instance.addObserver(this);
    // Keep the app connected in the background so messages can ring.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => BackgroundAlerts.instance.start());
    _poll = Timer.periodic(
      const Duration(seconds: 45),
      (_) => ref.invalidate(currentEmployeeProvider),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(currentEmployeeProvider);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    BackgroundAlerts.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cross-device sync — keep the Realtime channel alive while the
    // employee shell is mounted so admin-side archives clear the
    // employee's daily lists automatically.
    ref.watch(realtimeSyncProvider);
    // A new message from the admin pops up at once.
    ref.listen(employeeInboxProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (before == null || now == null) return; // first load: no popup
      final known = before.map((m) => m.id).toSet();
      final fresh = now.where((m) => !m.isRead && !known.contains(m.id));
      if (fresh.isEmpty) return;
      if (BackgroundAlerts.instance.inBackground) {
        // Not on screen: system banner with sound.
        for (final m in fresh.take(5)) {
          BackgroundAlerts.instance.notify(
            id: m.id.hashCode,
            title: (m.title ?? '').isEmpty ? 'رسالة من المدير' : m.title!,
            body: m.body,
          );
        }
        return;
      }
      playAlert();
      final first = fresh.first;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'رسالة من المدير: '
            '${(first.title ?? '').isEmpty ? first.body : first.title!}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    });
    final async = ref.watch(currentEmployeeProvider);

    return async.when(
      skipLoadingOnReload: true,
      skipError: true,
      loading: () => const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text(friendlyError(e))),
      ),
      data: (identity) {
        if (identity == null) {
          // Session lost (e.g. admin disabled account). Sign out + bounce.
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await ref.read(employeeAuthRepositoryProvider).signOut();
            if (context.mounted) context.go('/sign-in');
          });
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final tabs = _tabsFor(identity.permissions);
        // Defensive: if the saved index falls outside the role's tabs
        // (e.g. admin demoted the employee mid-session), reset to 0.
        final safeIndex = _index < tabs.length ? _index : 0;

        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          extendBody: true,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: AppBar(
                  title: Text(
                    tabs.isEmpty ? 'تطبيق الموظف' : tabs[safeIndex].title,
                  ),
                  backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
                  elevation: 0,
                  actions: [
                    IconButton(
                      tooltip: 'تحديث',
                      icon: const FaIcon(
                        FontAwesomeIcons.arrowsRotate,
                        size: 16,
                      ),
                      onPressed: () {
                        // Also re-reads the permissions the admin may have changed.
                        ref.invalidate(currentEmployeeProvider);
                        ref.invalidate(dailyTransfersProvider);
                        ref.invalidate(todayTransfersProvider);
                        ref.invalidate(todayBuysProvider);
                        ref.invalidate(archivedTransfersProvider);
                        ref.invalidate(dailyBuysProvider);
                        ref.invalidate(pendingBuysProvider);
                        ref.invalidate(archivedBuysProvider);
                        ref.invalidate(allExchangesProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('جاري التحديث...'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'رسائل المدير',
                      icon: Badge(
                        isLabelVisible: ref.watch(unreadInboxCountProvider) > 0,
                        label: Text('${ref.watch(unreadInboxCountProvider)}'),
                        child: const FaIcon(FontAwesomeIcons.bell, size: 16),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EmployeeInboxScreen(),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: identity.employeeName,
                      icon: const FaIcon(
                        FontAwesomeIcons.userTie,
                        size: 16,
                      ),
                      onPressed: () => _showProfileSheet(context, ref, identity),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: tabs.isEmpty
                ? _NoPermissionsView(name: identity.employeeName)
                : IndexedStack(
                    index: safeIndex,
                    children: tabs.map((t) => t.screen).toList(),
                  ),
          ),
          bottomNavigationBar: tabs.length <= 1
              ? null
              : _GlassBottomNav(
                  index: safeIndex,
                  tabs: tabs,
                  onChanged: (i) => setState(() => _index = i),
                ),
        );
      },
    );
  }

  /// The tabs follow the permissions the admin granted. A new employee has
  /// none, so the list is empty and the app shows only a waiting message.
  List<_EmployeeTab> _tabsFor(List<String> permissions) {
    final p = permissions.toSet();
    final canExit = p.contains(kPermTransfersCreate);
    final canEntry = p.contains(kPermBuysCreate);
    final canSeeRecords =
        p.contains(kPermViewOwn) || p.contains(kPermViewAll);
    return [
      if (canExit)
        _EmployeeTab(
          title: 'تنفيذ خروج حوالة',
          label: 'خروج',
          icon: FontAwesomeIcons.paperPlane,
          screen: TransfersScreen(key: transfersScreenKey),
        ),
      if (canEntry)
        const _EmployeeTab(
          title: 'تنفيذ دخول حوالة',
          label: 'دخول',
          icon: FontAwesomeIcons.moneyBillTransfer,
          screen: CurrencyBuyScreen(),
        ),
      if (canSeeRecords)
        const _EmployeeTab(
          title: 'سجل العمليات',
          label: 'السجل',
          icon: FontAwesomeIcons.clockRotateLeft,
          screen: EmployeeRecordsScreen(),
        ),
      // Closings: the button appears only with a closings permission. The
      // data scope (own / all) is enforced by the database.
      if (p.contains(kPermClosingsOwn) || p.contains(kPermClosingsAll))
        const _EmployeeTab(
          title: 'العمليات',
          label: 'العمليات',
          icon: FontAwesomeIcons.boxArchive,
          screen: ArchiveScreen(),
        ),
      // My account: the whole account, or only what this employee did.
      if (p.contains(kPermAccountsAll))
        const _EmployeeTab(
          title: 'حسابي',
          label: 'حسابي',
          icon: FontAwesomeIcons.wallet,
          screen: AccountsScreen(),
        )
      else if (p.contains(kPermAccountsOwn))
        const _EmployeeTab(
          title: 'حسابي',
          label: 'حسابي',
          icon: FontAwesomeIcons.wallet,
          screen: EmployeeMyAccountScreen(),
        ),
    ];
  }

  Future<void> _showProfileSheet(
    BuildContext context,
    WidgetRef ref,
    EmployeeIdentity identity,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.userTie,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.employeeName,
                          style: const TextStyle(
                            color: AppColors.textHigh,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _permissionsLabel(identity.permissions),
                          style: const TextStyle(
                            color: AppColors.textLow,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await ref.read(employeeAuthRepositoryProvider).signOut();
                  if (context.mounted) context.go('/sign-in');
                },
                icon: const FaIcon(
                  FontAwesomeIcons.rightFromBracket,
                  size: 14,
                ),
                label: const Text('تسجيل الخروج'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.negative,
                  side: BorderSide(
                    color: AppColors.negative.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _permissionsLabel(List<String> permissions) {
    if (permissions.isEmpty) return 'بدون صلاحيات';
    return permissions.map(employeePermissionLabel).join(' • ');
  }
}

/// Shown to an employee who has no permissions yet (every new employee).
class _NoPermissionsView extends StatelessWidget {
  const _NoPermissionsView({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(
              FontAwesomeIcons.userLock,
              size: 42,
              color: AppColors.textLow,
            ),
            const SizedBox(height: 18),
            Text(
              'مرحباً $name',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textHigh,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'لم تُمنح أي صلاحية بعد.\nتواصل مع المدير ليحدد لك ما تستطيع فعله.\nستظهر الأقسام هنا تلقائياً فور منحك الصلاحيات.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textLow,
                fontSize: 13,
                height: 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeTab {
  const _EmployeeTab({
    required this.title,
    required this.label,
    required this.icon,
    required this.screen,
  });

  final String title;
  final String label;
  final IconData icon;
  final Widget screen;
}

class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({
    required this.index,
    required this.tabs,
    required this.onChanged,
  });

  final int index;
  final List<_EmployeeTab> tabs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glassFillStrong,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                indicatorColor: AppColors.accent.withValues(alpha: 0.20),
                indicatorShape: const StadiumBorder(),
              ),
              child: NavigationBar(
                height: 64,
                selectedIndex: index,
                onDestinationSelected: onChanged,
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (final t in tabs)
                    NavigationDestination(
                      icon: FaIcon(t.icon, size: 18),
                      label: t.label,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
