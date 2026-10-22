import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme.dart';

/// How long a platform notification stays on screen.
const kNotificationDropdownDuration = Duration(seconds: 15);

/// A notification from the platform drops down from the top of the screen,
/// stays [duration] (15 s) on a white, see-through panel, and goes away on its
/// own, on a tap on ✕ or on a swipe up. A tap on the panel calls [onOpen]
/// (the notifications list). The bell sound is played by the caller.
///
/// [more] is how many other new notifications arrived with it.
void showNotificationDropdown(
  BuildContext context, {
  String? title,
  required String body,
  int more = 0,
  VoidCallback? onOpen,
  Duration duration = kNotificationDropdownDuration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _current?.dismiss();
  final entry = _Dropdown(
    overlay: overlay,
    title: title,
    body: body,
    more: more,
    onOpen: onOpen,
    duration: duration,
  );
  _current = entry;
  entry.show();
}

/// Removes the panel on screen, if any.
void hideNotificationDropdown() => _current?.dismiss();

_Dropdown? _current;

class _Dropdown {
  _Dropdown({
    required this.overlay,
    required this.title,
    required this.body,
    required this.more,
    required this.onOpen,
    required this.duration,
  });

  final OverlayState overlay;
  final String? title;
  final String body;
  final int more;
  final VoidCallback? onOpen;
  final Duration duration;
  final _key = GlobalKey<_PanelState>();
  late final OverlayEntry _entry;
  bool _removed = false;

  void show() {
    _entry = OverlayEntry(
      builder: (_) => _Panel(
        key: _key,
        title: title,
        body: body,
        more: more,
        duration: duration,
        onOpen: onOpen,
        onClosed: _remove,
      ),
    );
    overlay.insert(_entry);
  }

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

class _Panel extends StatefulWidget {
  const _Panel({
    super.key,
    required this.title,
    required this.body,
    required this.more,
    required this.duration,
    required this.onOpen,
    required this.onClosed,
  });

  final String? title;
  final String body;
  final int more;
  final Duration duration;
  final VoidCallback? onOpen;
  final VoidCallback onClosed;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> with TickerProviderStateMixin {
  // slide in / out
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..addStatusListener((s) {
      if (s == AnimationStatus.dismissed && _closing) widget.onClosed();
    });
  // the remaining time, drawn as a thin bar
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
    _life.forward();
    _timer = Timer(widget.duration, close);
  }

  void close() {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    _life.stop();
    if (mounted) {
      _slide.reverse();
    } else {
      widget.onClosed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _life.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final curve = CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic);
    const ink = Color(0xFF0B1220);
    final title = (widget.title ?? '').trim();
    return Positioned(
      top: top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.8),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Dismissible(
            key: const ValueKey('notification-dropdown-dismiss'),
            direction: DismissDirection.up,
            onDismissed: (_) => widget.onClosed(),
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    key: const ValueKey('notification-dropdown'),
                    decoration: BoxDecoration(
                      // white and see-through: the screen shows faintly behind
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x44000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            close();
                            widget.onOpen?.call();
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: FaIcon(
                                    FontAwesomeIcons.bell,
                                    size: 18,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'إشعار جديد' : title,
                                        style: const TextStyle(
                                          color: ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.body,
                                        maxLines: 6,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: ink,
                                          fontSize: 13.5,
                                          height: 1.5,
                                        ),
                                      ),
                                      if (widget.more > 0)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '+ ${widget.more} إشعارات أخرى',
                                            style: const TextStyle(
                                              color: AppColors.accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'notification-dropdown-close',
                                  ),
                                  tooltip: 'إغلاق',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 18),
                                  color: ink.withValues(alpha: 0.6),
                                  onPressed: close,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // time left on screen
                        AnimatedBuilder(
                          animation: _life,
                          builder: (_, __) => LinearProgressIndicator(
                            minHeight: 3,
                            value: 1 - _life.value,
                            backgroundColor: Colors.transparent,
                            color: AppColors.accent.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
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
