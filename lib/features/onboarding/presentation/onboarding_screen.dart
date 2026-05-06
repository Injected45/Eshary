import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../data/onboarding_storage.dart';

enum _SceneKind { plane, wallet, vault, accounts }

class _Page {
  const _Page({
    required this.kind,
    required this.tint,
    required this.title,
    required this.subtitle,
  });
  final _SceneKind kind;
  final Color tint;
  final String title;
  final String subtitle;
}

const _pages = [
  _Page(
    kind: _SceneKind.plane,
    tint: AppColors.accent,
    title: 'دخول تحويلات',
    subtitle:
        'سجّل الحوالات الواردة، أنشئ رسائل الاستلام والتسليم، شاركها آلياً، تابع العمليات قيد التنفيذ حتى الإقفال مع تحديث الرصيد وحفظ بيانات المرسل.',
  ),
  _Page(
    kind: _SceneKind.wallet,
    tint: AppColors.positive,
    title: 'خروج تحويلات',
    subtitle:
        'سجّل الحوالات الصادرة، أنشئ رسائل الإرسال والتسليم وشاركها آلياً، تحديث الرصيد بعد الإقفال والترحيل وحفظ بيانات المستلم.',
  ),
  _Page(
    kind: _SceneKind.vault,
    tint: AppColors.warning,
    title: 'الإقفالات',
    subtitle:
        'تابع إقفالات الدخول والخروج، استرجع أي حوالة سابقة، راجع تفاصيل العمليات حسب التاريخ بكل دقة.',
  ),
  _Page(
    kind: _SceneKind.accounts,
    tint: AppColors.accent,
    title: 'حساباتي',
    subtitle:
        'تحكّم في حساباتك المتعددة بسهولة، افتح وتابع أكثر من حساب في أكثر من شركة ودولة، واعرف أرصدتك التفصيلية والإجمالية من شاشة واحدة آمنة وواضحة.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _ctrl = PageController();
  final _pageOffset = ValueNotifier<double>(0);
  int _index = 0;

  late final List<AnimationController> _entryCtrls;
  late final List<AnimationController> _idleCtrls;
  late final AnimationController _ctaPulseCtrl;

  @override
  void initState() {
    super.initState();
    _entryCtrls = List.generate(
      _pages.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      ),
    );
    _idleCtrls = List.generate(
      _pages.length,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 2400 + i * 400),
      )..repeat(reverse: true),
    );
    _ctaPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _ctrl.addListener(_onPageScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entryCtrls[0].forward();
    });
  }

  void _onPageScroll() {
    if (!_ctrl.hasClients) return;
    final page = _ctrl.page;
    if (page == null) return;
    _pageOffset.value = page;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onPageScroll);
    _ctrl.dispose();
    _pageOffset.dispose();
    for (final c in _entryCtrls) {
      c.dispose();
    }
    for (final c in _idleCtrls) {
      c.dispose();
    }
    _ctaPulseCtrl.dispose();
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
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _entryCtrls[i].forward(from: 0);
  }

  void _replayCurrent() {
    _entryCtrls[_index].forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final illusHeight = constraints.maxHeight * 0.58;
            return Column(
              children: [
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
                SizedBox(
                  height: illusHeight,
                  child: PageView.builder(
                    controller: _ctrl,
                    itemCount: _pages.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _replayCurrent,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _pageOffset,
                          builder: (_, offset, __) {
                            return _OnboardingScene(
                              page: _pages[i],
                              index: i,
                              pageOffset: offset,
                              entry: _entryCtrls[i],
                              idle: _idleCtrls[i],
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: Text(
                            _pages[_index].title,
                            key: ValueKey('title_$_index'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHigh,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: Text(
                              _pages[_index].subtitle,
                              key: ValueKey('sub_$_index'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: AppColors.textMid,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _WormIndicator(count: _pages.length, current: _index),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _ctaPulseCtrl,
                      builder: (context, child) {
                        final glow = isLast
                            ? Curves.easeInOut.transform(_ctaPulseCtrl.value)
                            : 0.0;
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(
                                  alpha: 0.20 + 0.40 * glow,
                                ),
                                blurRadius: 24 + 18 * glow,
                                spreadRadius: 1 + 3 * glow,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OnboardingScene extends StatelessWidget {
  const _OnboardingScene({
    required this.page,
    required this.index,
    required this.pageOffset,
    required this.entry,
    required this.idle,
  });

  final _Page page;
  final int index;
  final double pageOffset;
  final AnimationController entry;
  final AnimationController idle;

  @override
  Widget build(BuildContext context) {
    final delta = (pageOffset - index).clamp(-1.0, 1.0);
    final activeness = 1.0 - delta.abs();
    final scale = 0.92 + 0.08 * activeness;
    final opacity = (0.35 + 0.65 * activeness).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: Listenable.merge([entry, idle]),
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: CustomPaint(
                    painter: _ScenePainter(
                      kind: page.kind,
                      tint: page.tint,
                      entry: Curves.easeOutCubic.transform(entry.value),
                      idle: idle.value,
                      parallax: delta,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.kind,
    required this.tint,
    required this.entry,
    required this.idle,
    required this.parallax,
  });

  final _SceneKind kind;
  final Color tint;
  final double entry; // 0 to 1
  final double idle; // 0 to 1
  final double parallax; // -1 to 1

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case _SceneKind.plane:
        _paintPlane(canvas, size);
      case _SceneKind.wallet:
        _paintWallet(canvas, size);
      case _SceneKind.vault:
        _paintVault(canvas, size);
      case _SceneKind.accounts:
        _paintWallet(canvas, size);
    }
  }

  // ----- Scene 1: paper plane crossing horizon -----
  void _paintPlane(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        size.width * 0.6,
        [tint.withValues(alpha: 0.30), tint.withValues(alpha: 0.0)],
      );
    canvas.drawCircle(Offset(cx, cy), size.width * 0.6, glow);

    final bgOffset = parallax * 18;
    for (var i = 0; i < 3; i++) {
      final y = cy + 50 + i * 18.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bgOffset - 4, y, size.width, 6),
          const Radius.circular(3),
        ),
        Paint()..color = tint.withValues(alpha: 0.10 - i * 0.025),
      );
    }

    const starPositions = [
      Offset(-100, -70),
      Offset(90, -90),
      Offset(-60, -110),
      Offset(60, -55),
      Offset(-20, -130),
    ];
    for (final s in starPositions) {
      final twinkle =
          0.5 + 0.5 * math.sin(idle * 2 * math.pi + s.dx * 0.05);
      canvas.drawCircle(
        Offset(cx + s.dx + parallax * 6, cy + s.dy),
        2.0,
        Paint()
          ..color = AppColors.glassBorderStrong.withValues(alpha: twinkle),
      );
    }

    final pathStart = Offset(cx - 110, cy + 40);
    final pathCtrl = Offset(cx, cy - 80);
    final pathEnd = Offset(cx + 110, cy - 30);
    final curve = Path()
      ..moveTo(pathStart.dx, pathStart.dy)
      ..quadraticBezierTo(pathCtrl.dx, pathCtrl.dy, pathEnd.dx, pathEnd.dy);

    final metric = curve.computeMetrics().first;
    final trailEnd = metric.length * entry;
    if (trailEnd > 0) {
      final trail = metric.extractPath(0, trailEnd);
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: 0.5),
      );
      final tan = metric.getTangentForOffset(trailEnd);
      if (tan != null) {
        final bob = math.sin(idle * 2 * math.pi) * 4;
        canvas.save();
        canvas.translate(
          tan.position.dx + parallax * 12,
          tan.position.dy + bob,
        );
        canvas.rotate(tan.angle);
        _drawPaperPlane(canvas, 22);
        canvas.restore();
      }
    }
  }

  void _drawPaperPlane(Canvas canvas, double s) {
    final body = Path()
      ..moveTo(-s, -s * 0.6)
      ..lineTo(s, 0)
      ..lineTo(-s, s * 0.6)
      ..lineTo(-s * 0.4, 0)
      ..close();
    final wing = Path()
      ..moveTo(-s, s * 0.6)
      ..lineTo(-s * 0.4, 0)
      ..lineTo(-s * 0.2, s * 0.45)
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-s, 0),
          Offset(s, 0),
          [
            Colors.white.withValues(alpha: 0.95),
            tint.withValues(alpha: 0.80),
          ],
        ),
    );
    canvas.drawPath(
      wing,
      Paint()..color = tint.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.glassBorderStrong,
    );
  }

  // ----- Scene 2: coins falling into a wallet -----
  void _paintWallet(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawCircle(
      Offset(cx, cy + 30),
      size.width * 0.55,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy + 30),
          size.width * 0.55,
          [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.0)],
        ),
    );

    const coins = <_CoinSlot>[
      _CoinSlot(dx: -56, delay: 0.05),
      _CoinSlot(dx: 0, delay: 0.22),
      _CoinSlot(dx: 56, delay: 0.40),
      _CoinSlot(dx: -28, delay: 0.58),
      _CoinSlot(dx: 28, delay: 0.74),
    ];
    for (final c in coins) {
      final t = ((entry - c.delay) / (1 - c.delay)).clamp(0.0, 1.0);
      final eased = Curves.easeInCubic.transform(t);
      final startY = cy - 200;
      final landY = cy + 30;
      final wobble = math.sin(t * math.pi * 2) * 5;
      final ox = cx + c.dx + parallax * 14 + wobble;
      final y = startY + (landY - startY) * eased;
      final landed = t >= 1.0;
      final alpha = landed ? (0.85 + 0.15 * idle) : 0.95;
      _drawCoin(canvas, Offset(ox, y), 16, alpha);
    }

    final walletRect = Rect.fromCenter(
      center: Offset(cx + parallax * 22, cy + 80),
      width: 220,
      height: 130,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        walletRect.shift(const Offset(0, 10)),
        const Radius.circular(20),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(walletRect, const Radius.circular(20)),
      Paint()
        ..shader = ui.Gradient.linear(
          walletRect.topLeft,
          walletRect.bottomRight,
          [tint.withValues(alpha: 0.55), tint.withValues(alpha: 0.20)],
        ),
    );
    final flapRect = Rect.fromLTWH(
      walletRect.left,
      walletRect.top,
      walletRect.width,
      28,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        flapRect,
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(walletRect, const Radius.circular(20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.glassBorderStrong,
    );
    canvas.drawCircle(
      Offset(walletRect.right - 22, walletRect.center.dy),
      6,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  void _drawCoin(Canvas canvas, Offset c, double r, double alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          c.translate(-r, -r),
          c.translate(r, r),
          [
            tint.withValues(alpha: alpha),
            tint.withValues(alpha: alpha * 0.55),
          ],
        ),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: alpha * 0.6),
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '\$',
        style: TextStyle(
          color: Colors.white.withValues(alpha: alpha),
          fontWeight: FontWeight.w900,
          fontSize: r * 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  // ----- Scene 3: vault with check-mark seal -----
  void _paintVault(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.55,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          size.width * 0.55,
          [tint.withValues(alpha: 0.30), tint.withValues(alpha: 0.0)],
        ),
    );

    const bodyR = 92.0;
    final bodyCenter = Offset(cx + parallax * 18, cy);
    canvas.drawCircle(
      bodyCenter,
      bodyR,
      Paint()
        ..shader = ui.Gradient.linear(
          bodyCenter.translate(-bodyR, -bodyR),
          bodyCenter.translate(bodyR, bodyR),
          [tint.withValues(alpha: 0.40), tint.withValues(alpha: 0.12)],
        ),
    );
    canvas.drawCircle(
      bodyCenter,
      bodyR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.glassBorderStrong,
    );

    for (var i = 0; i < 8; i++) {
      final a = i * (math.pi * 2 / 8);
      final p =
          bodyCenter + Offset(math.cos(a), math.sin(a)) * (bodyR - 12);
      canvas.drawCircle(
        p,
        3.5,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    const innerR = bodyR - 18;
    final doorAngle = -entry * 0.55;
    canvas.save();
    canvas.translate(bodyCenter.dx - innerR, bodyCenter.dy);
    canvas.rotate(doorAngle);
    canvas.translate(-(bodyCenter.dx - innerR), -bodyCenter.dy);
    canvas.drawCircle(
      bodyCenter,
      innerR,
      Paint()..color = AppColors.bgPanel.withValues(alpha: 0.95),
    );
    canvas.drawCircle(
      bodyCenter,
      innerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.glassBorder,
    );
    canvas.drawCircle(
      bodyCenter + const Offset(40, 0),
      8,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawLine(
      bodyCenter + const Offset(40, -16),
      bodyCenter + const Offset(40, 16),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 3,
    );
    canvas.restore();

    final checkProgress = ((entry - 0.5) / 0.5).clamp(0.0, 1.0);
    if (checkProgress > 0) {
      final checkPath = Path()
        ..moveTo(bodyCenter.dx - 22, bodyCenter.dy + 2)
        ..lineTo(bodyCenter.dx - 6, bodyCenter.dy + 18)
        ..lineTo(bodyCenter.dx + 26, bodyCenter.dy - 14);
      final metric = checkPath.computeMetrics().first;
      final drawn = metric.extractPath(0, metric.length * checkProgress);
      final pulse = 0.7 + 0.3 * idle;
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.positive.withValues(alpha: pulse),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) {
    return old.entry != entry ||
        old.idle != idle ||
        old.parallax != parallax ||
        old.kind != kind ||
        old.tint != tint;
  }
}

class _CoinSlot {
  const _CoinSlot({required this.dx, required this.delay});
  final double dx;
  final double delay;
}

class _WormIndicator extends StatelessWidget {
  const _WormIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: active ? 24 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [AppColors.accent, AppColors.positive],
                  )
                : null,
            color: active ? null : AppColors.glassBorderStrong,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
