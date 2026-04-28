import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Animated dark background with three slow-moving radial blobs that get
/// blurred behind every screen, producing the "liquid glass" depth.
class LiquidBackground extends StatefulWidget {
  const LiquidBackground({super.key, required this.child});
  final Widget child;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.bgDeep),
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _BlobsPainter(progress: _ctrl.value),
            size: Size.infinite,
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: const ColoredBox(color: Color(0x00000000)),
        ),
        widget.child,
      ],
    );
  }
}

class _BlobsPainter extends CustomPainter {
  _BlobsPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;

    final c1 = Offset(
      size.width * (0.7 + 0.18 * math.sin(t)),
      size.height * (0.22 + 0.12 * math.cos(t * 0.8)),
    );
    final r1 = size.shortestSide * 0.55;
    final p1 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.accent.withValues(alpha: 0.45),
          AppColors.accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c1, radius: r1));
    canvas.drawCircle(c1, r1, p1);

    final c2 = Offset(
      size.width * (0.18 + 0.18 * math.cos(t * 0.6)),
      size.height * (0.78 + 0.08 * math.sin(t * 0.9)),
    );
    final r2 = size.shortestSide * 0.5;
    final p2 = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.positive.withValues(alpha: 0.30),
          AppColors.positive.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c2, radius: r2));
    canvas.drawCircle(c2, r2, p2);

    final c3 = Offset(
      size.width * (0.5 + 0.10 * math.sin(t * 0.4)),
      size.height * (0.55 + 0.10 * math.cos(t * 0.5)),
    );
    final r3 = size.shortestSide * 0.4;
    final p3 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF8B5CF6).withValues(alpha: 0.20),
          const Color(0xFF8B5CF6).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c3, radius: r3));
    canvas.drawCircle(c3, r3, p3);
  }

  @override
  bool shouldRepaint(_BlobsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
