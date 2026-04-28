import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Frosted-glass surface — backdrop blur + translucent fill + hairline border.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.radius = 20,
    this.blur = 18,
    this.fill = AppColors.glassFill,
    this.border = AppColors.glassBorder,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final double radius;
  final double blur;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  fill,
                  fill.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(radius),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Subtle "section" container without the card chrome — flatter glass.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.radius = 14,
    this.blur = 12,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Shows a dialog with a slide-up + scale + fade entrance, matching the
/// dark glass aesthetic. Dismiss by tapping the dim backdrop or via the
/// dialog's own close button.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => builder(context),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.12),
        end: Offset.zero,
      ).animate(curved);
      final scale = Tween<double>(begin: 0.94, end: 1.0).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(scale: scale, child: child),
        ),
      );
    },
  );
}

/// AppBar that lets the liquid background show through, with a faint glass blur.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.title, this.actions});

  final Widget title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AppBar(
          title: title,
          actions: actions,
          backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
          elevation: 0,
        ),
      ),
    );
  }
}
