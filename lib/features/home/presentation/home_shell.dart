import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/realtime_sync.dart';
import '../../archive/presentation/archive_screen.dart';
import '../../companies/presentation/accounts_screen.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/presentation/currency_buy_screen.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../../transfers/presentation/transfers_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  /// Inside the "الحوالات" tab: null = hub with the two buttons,
  /// 0 = خروج (transfers), 1 = دخول (currency buy).
  int? _sub;

  static const _titles = [
    'الحوالات',
    'الإقفالات',
    'حساباتي',
    'الإعدادات',
  ];

  static const _subTitles = [
    'تنفيذ خروج حوالة',
    'تنفيذ دخول حوالة',
  ];

  static final _transfersScreen = TransfersScreen(key: transfersScreenKey);
  static const _currencyBuyScreen = CurrencyBuyScreen();

  static final _otherScreens = <Widget>[
    const ArchiveScreen(),
    const AccountsScreen(),
    const SettingsScreen(),
  ];

  bool get _inSub => _index == 0 && _sub != null;

  static const _outColor = AppColors.negative;
  static const _inColor = AppColors.positive;

  /// Re-themes [child] so buttons, focus borders and other primary-coloured
  /// widgets pick up [color] without touching the screen itself.
  Widget _tinted(BuildContext context, Color color, Widget child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(primary: color),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the Realtime channel alive for the duration of the home shell
    // so cross-device DB changes (admin archiving, balances moving) flow
    // into provider invalidations without manual refresh.
    ref.watch(realtimeSyncProvider);
    return PopScope(
      canPop: !_inSub,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inSub) setState(() => _sub = null);
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // Inner IndexedStack keeps both entry forms alive so they retain their
    // state when switching between hub / خروج / دخول.
    final screens = <Widget>[
      IndexedStack(
        index: _sub == null ? 0 : _sub! + 1,
        children: [
          _TransfersHub(onSelect: (i) => setState(() => _sub = i)),
          _tinted(context, _outColor, _transfersScreen),
          _tinted(context, _inColor, _currencyBuyScreen),
        ],
      ),
      ..._otherScreens,
    ];
    // Each entry screen has its own accent: خروج red, دخول green.
    final subColor = _inSub ? (_sub == 0 ? _outColor : _inColor) : null;
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
              title: Text(_inSub ? _subTitles[_sub!] : _titles[_index]),
              leading: _inSub
                  ? BackButton(onPressed: () => setState(() => _sub = null))
                  : null,
              backgroundColor: subColor == null
                  ? AppColors.bgDeep.withValues(alpha: 0.35)
                  : Color.alphaBlend(
                      subColor.withValues(alpha: 0.28),
                      AppColors.bgDeep.withValues(alpha: 0.35),
                    ),
              elevation: 0,
              bottom: subColor == null
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(3),
                      child: Container(height: 3, color: subColor),
                    ),
              actions: [
                IconButton(
                  tooltip: 'تحديث',
                  icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 16),
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
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(index: _index, children: screens),
      ),
      bottomNavigationBar: _GlassBottomNav(
        index: _index,
        onChanged: (i) => setState(() {
          // Tapping "الحوالات" again returns to the hub.
          if (i == 0) _sub = null;
          _index = i;
        }),
      ),
    );
  }
}

/// Landing screen of the "الحوالات" tab: two big buttons that open the
/// existing خروج (transfers) and دخول (currency buy) screens unchanged.
class _TransfersHub extends StatelessWidget {
  const _TransfersHub({required this.onSelect});
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, contentTopPadding(context), 16, 96),
      children: [
        _HubButton(
          icon: FontAwesomeIcons.paperPlane,
          label: 'خروج',
          color: AppColors.negative,
          onTap: () => onSelect(0),
        ),
        const SizedBox(height: 16),
        _HubButton(
          icon: FontAwesomeIcons.moneyBillTransfer,
          label: 'دخول',
          color: AppColors.positive,
          onTap: () => onSelect(1),
        ),
      ],
    );
  }
}

class _HubButton extends StatelessWidget {
  const _HubButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          children: [
            FaIcon(icon, size: 36, color: color),
            const SizedBox(height: 14),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({required this.index, required this.onChanged});
  final int index;
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
                destinations: const [
                  NavigationDestination(
                    icon: FaIcon(
                      FontAwesomeIcons.moneyBillTransfer,
                      size: 18,
                    ),
                    label: 'الحوالات',
                  ),
                  NavigationDestination(
                    icon: FaIcon(FontAwesomeIcons.boxArchive, size: 18),
                    label: 'الإقفالات',
                  ),
                  NavigationDestination(
                    icon: FaIcon(FontAwesomeIcons.wallet, size: 18),
                    label: 'حساباتي',
                  ),
                  NavigationDestination(
                    icon: FaIcon(FontAwesomeIcons.gear, size: 18),
                    label: 'الإعدادات',
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
