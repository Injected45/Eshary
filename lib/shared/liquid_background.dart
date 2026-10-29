import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import 'visual_mode.dart';

/// Dark background with three soft radial blobs behind every screen, the
/// "liquid glass" depth. Painted ONCE: it used to move (a 60 fps repaint
/// under a full-screen blur on every screen, idle or not, so the phone's GPU
/// and battery never rested). The gradients already fade to nothing, so the
/// blur added nothing visible. The deep
/// base colour comes from [visualModeProvider]: 'deep' is the original OLED
/// black, 'calm' is a softer navy. The glass bars and panels drawn on top are
/// transparent, so they adapt by themselves.
class LiquidBackground extends ConsumerWidget {
  const LiquidBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(visualModeProvider);
    final base =
        mode == AppVisualMode.calm ? AppColors.bgCalm : AppColors.bgDeep;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(key: const ValueKey('liquid-base'), color: base),
        RepaintBoundary(
          child: CustomPaint(
            painter: _BlobsPainter(progress: 0),
            isComplex: true,
            size: Size.infinite,
          ),
        ),
        child,
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
