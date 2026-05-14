import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../../../shared/realtime_sync.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/presentation/currency_buy_screen.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../../transfers/presentation/transfers_screen.dart';
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

class _EmployeeHomeShellState extends ConsumerState<EmployeeHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Cross-device sync — keep the Realtime channel alive while the
    // employee shell is mounted so admin-side archives clear the
    // employee's daily lists automatically.
    ref.watch(realtimeSyncProvider);
    final async = ref.watch(currentEmployeeProvider);

    return async.when(
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

        final tabs = _tabsFor(identity.role);
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
                  title: Text(tabs[safeIndex].title),
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
                        ref.invalidate(dailyTransfersProvider);
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
            child: IndexedStack(
              index: safeIndex,
              children: tabs.map((t) => t.screen).toList(),
            ),
          ),
          bottomNavigationBar: tabs.length == 1
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

  List<_EmployeeTab> _tabsFor(String role) {
    final canExit = role == 'exit' || role == 'both';
    final canEntry = role == 'entry' || role == 'both';
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
      const _EmployeeTab(
        title: 'سجل عملياتي',
        label: 'سجلاتي',
        icon: FontAwesomeIcons.clockRotateLeft,
        screen: EmployeeRecordsScreen(),
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
                          _roleLabel(identity.role),
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

  String _roleLabel(String role) {
    switch (role) {
      case 'entry':
        return 'صلاحية الدخول فقط';
      case 'exit':
        return 'صلاحية الخروج فقط';
      default:
        return 'صلاحية دخول وخروج';
    }
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
