import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:local_auth/local_auth.dart';

import '../core/supabase_provider.dart';
import '../core/theme.dart';
import 'cache.dart';
import 'logger.dart';

const _lockKey = 'applock:enabled';

/// How long the app may stay in the background before it asks again.
const kLockAfter = Duration(seconds: 60);

/// The phone's own fingerprint / face / screen-lock check. It only keeps a
/// borrowed or unlocked phone from opening the app; it is not an identity
/// proof for the account, which stays with the WhatsApp code.
abstract class DeviceAuth {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class LocalDeviceAuth implements DeviceAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e, st) {
      AppLogger.error('appLock.authenticate', e, st);
      return false;
    }
  }
}

final deviceAuthProvider = Provider<DeviceAuth>((ref) => LocalDeviceAuth());

/// Whether the lock is on for this phone (kept on the phone only).
class AppLockEnabled extends StateNotifier<bool> {
  AppLockEnabled(this._cache) : super(_cache.readString(_lockKey) == '1');

  final JsonCache _cache;

  Future<void> set(bool on) async {
    state = on;
    await _cache.writeString(_lockKey, on ? '1' : '');
  }
}

final appLockEnabledProvider =
    StateNotifierProvider<AppLockEnabled, bool>((ref) {
  return AppLockEnabled(ref.watch(jsonCacheProvider));
});

/// Covers the whole app with an unlock screen when the lock is on: at start and
/// after [kLockAfter] in the background. Time away is measured with a monotonic
/// stopwatch, never with the phone's date.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  Duration? _leftAt;
  bool _locked = true;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftAt ??= _clock.elapsed;
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && _clock.elapsed - left >= kLockAfter) {
        setState(() => _locked = true);
        _maybePrompt();
      }
    }
  }

  bool get _active {
    if (!ref.read(appLockEnabledProvider)) return false;
    return ref.read(currentUserIdProvider) != null;
  }

  Future<void> _maybePrompt() async {
    if (!mounted || _prompting || !_locked || !_active) return;
    _prompting = true;
    final ok = await ref
        .read(deviceAuthProvider)
        .authenticate('افتح إشاري بالبصمة أو قفل الهاتف');
    _prompting = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    // A fresh sign-in (WhatsApp code) is proof enough: no second prompt.
    ref.listen<String?>(currentUserIdProvider, (prev, next) {
      if (prev == null && next != null) setState(() => _locked = false);
    });
    final enabled = ref.watch(appLockEnabledProvider);
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final show = enabled && signedIn && _locked;
    return Stack(
      children: [
        // The app stays alive underneath but is not painted or tappable.
        Offstage(offstage: show, child: widget.child),
        if (show)
          Positioned.fill(
            child: Material(
              color: AppColors.bgDeep,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.fingerprint,
                        size: 56,
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'التطبيق مقفل',
                        style: TextStyle(
                          color: AppColors.textHigh,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('unlock'),
                        onPressed: _maybePrompt,
                        child: const Text('فتح'),
                      ),
                      TextButton(
                        key: const ValueKey('lock-sign-out'),
                        onPressed: () async {
                          await ref
                              .read(supabaseClientProvider)
                              .auth
                              .signOut();
                          if (mounted) setState(() => _locked = true);
                        },
                        child: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
