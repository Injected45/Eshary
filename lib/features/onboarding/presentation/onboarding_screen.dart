import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../data/onboarding_storage.dart';

class _Page {
  const _Page({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
}

const _pages = [
  _Page(
    icon: FontAwesomeIcons.paperPlane,
    tint: AppColors.accent,
    title: 'إدارة الحوالات',
    subtitle:
        'أرسل الحوالات الدولية بسهولة، مع توليد رقم إشاري تلقائي وحفظ نص الرسالة جاهزاً للمشاركة.',
  ),
  _Page(
    icon: FontAwesomeIcons.moneyBillTransfer,
    tint: AppColors.positive,
    title: 'شراء العملات',
    subtitle:
        'اشترِ الدولار من العملاء وحساب القيمة بالدينار الليبي تلقائياً، مع تتبع العمليات المعلقة.',
  ),
  _Page(
    icon: FontAwesomeIcons.boxArchive,
    tint: AppColors.warning,
    title: 'الأرشيف العام',
    subtitle:
        'تابع إجمالي العمليات اليومية والمؤرشفة، وصدّر التقارير بصيغة PDF بضغطة واحدة.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingStorageProvider).markCompleted();
    if (!mounted) return;
    context.go('/sign-in');
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
    } else {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'تخطّي',
                    style: TextStyle(color: AppColors.textLow),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                page.tint.withValues(alpha: 0.45),
                                page.tint.withValues(alpha: 0.15),
                              ],
                            ),
                            border: Border.all(
                                color: AppColors.glassBorderStrong),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    page.tint.withValues(alpha: 0.30),
                                blurRadius: 50,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: FaIcon(page.icon,
                              size: 56, color: Colors.white),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHigh,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 360),
                          child: Text(
                            page.subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.7,
                              color: AppColors.textLow,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _Indicator(count: _pages.length, current: _index),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  radius: 16,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(isLast ? 'ابدأ الآن' : 'التالي'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.glassBorderStrong,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
