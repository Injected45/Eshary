import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Every message of the app (confirmations, errors, notifications) appears at
/// the TOP of the screen, under the status bar, not at the bottom.
///
/// Call it exactly where a SnackBar used to be shown:
///
///   showTopSnackBar(context, SnackBar(content: Text('تم الحفظ')));
///
/// The [SnackBar] is only a description (content, colour, duration): what is
/// drawn is a banner in the app's glass style that slides down from the top,
/// stays for `duration` (4 s by default) and disappears on a tap or a swipe up.
/// A new message replaces the one on screen.
void showTopSnackBar(BuildContext context, SnackBar bar) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.dismiss();
  final entry = _TopMessage(overlay: overlay, bar: bar);
  _current = entry;
  entry.show();
}

/// Removes the message on screen, if any.
void hideTopSnackBar() => _current?.dismiss();

_TopMessage? _current;

class _TopMessage {
  _TopMessage({required this.overlay, required this.bar});

  final OverlayState overlay;
  final SnackBar bar;
  final _key = GlobalKey<_BannerState>();
  late final OverlayEntry _entry;
  bool _removed = false;

  void show() {
    _entry = OverlayEntry(
      builder: (context) => _Banner(
        key: _key,
        bar: bar,
        onClosed: _remove,
      ),
    );
    overlay.insert(_entry);
  }

  /// Slides out, then removes itself.
  void dismiss() {
    if (identical(_current, this)) _current = null;
    final state = _key.currentState;
    if (state == null) {
      _remove();
    } else {
      state.close();
    }
  }

  void _remove() {
    if (_removed) return;
    _removed = true;
    if (identical(_current, this)) _current = null;
    _entry.remove();
  }
}

/// The banner owns its timer and animation, so both end with the widget (no
/// timer is left behind when a screen or a test goes away).
class _Banner extends StatefulWidget {
  const _Banner({super.key, required this.bar, required this.onClosed});

  final SnackBar bar;
  final VoidCallback onClosed;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _closing) widget.onClosed();
    });
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.bar.duration, close);
  }

  void close() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) {
      _c.reverse();
    } else {
      widget.onClosed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // The app's glass look: translucent white over a slightly dark base (so it
    // is light but never a flat bright white). An error / warning keeps the
    // same glass with a tint of its colour.
    final tint = widget.bar.backgroundColor;
    final fill = tint == null
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.27),
            AppColors.bgPanel.withValues(alpha: 0.45),
          )
        : Color.alphaBlend(
            tint.withValues(alpha: 0.42),
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.14),
              AppColors.bgPanel.withValues(alpha: 0.45),
            ),
          );
    final border = Colors.white.withValues(alpha: tint == null ? 0.38 : 0.45);
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.6),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Dismissible(
            key: const ValueKey('top-message-dismiss'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onClosed(),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: close,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  // frosted glass: the screen behind blurs, so the text stays
                  // readable over any content
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      key: const ValueKey('top-message'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          color: AppColors.textHigh,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                        child: widget.bar.content,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
