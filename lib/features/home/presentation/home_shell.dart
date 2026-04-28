import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../archive/presentation/archive_screen.dart';
import '../../currency_buy/presentation/currency_buy_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../transfers/presentation/transfers_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _titles = [
    'تنفيذ حوالة جديدة',
    'شراء عملة',
    'الأرشيف العام',
    'الإعدادات',
  ];

  static final _screens = <Widget>[
    TransfersScreen(key: transfersScreenKey),
    const CurrencyBuyScreen(),
    const ArchiveScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
              title: Text(_titles[_index]),
              backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
              elevation: 0,
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(index: _index, children: _screens),
      ),
      floatingActionButton: _index == 0 ? _testDataFab() : null,
      bottomNavigationBar: _GlassBottomNav(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }

  Widget _testDataFab() => FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const FaIcon(FontAwesomeIcons.flaskVial, size: 16),
        label: const Text('بيانات اختبار'),
        onPressed: () => transfersScreenKey.currentState?.fillDefaults(),
      );
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
                    icon: FaIcon(FontAwesomeIcons.paperPlane, size: 18),
                    label: 'خروج',
                  ),
                  NavigationDestination(
                    icon: FaIcon(FontAwesomeIcons.moneyBillTransfer,
                        size: 18),
                    label: 'دخول',
                  ),
                  NavigationDestination(
                    icon: FaIcon(FontAwesomeIcons.boxArchive, size: 18),
                    label: 'الأرشيف',
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
