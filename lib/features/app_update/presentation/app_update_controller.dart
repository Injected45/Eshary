import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/build_info.dart';
import '../../../core/build_flavor.dart';
import '../../../shared/logger.dart';
import '../data/app_update_repository.dart';
import '../data/update_engine.dart';
import '../domain/app_release.dart';

enum UpdatePhase {
  /// Nothing to show.
  idle,

  /// A newer release is waiting (the buttons: update / later when optional).
  offered,
  downloading,
  verifying,

  /// Android has to be told once that this app may install apps.
  needsPermission,

  /// Downloaded and checked; the installer was opened (or can be reopened).
  ready,
  failed,
}

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.mandatory = false,
    this.release,
    this.progress = 0,
    this.error,
  });

  final UpdatePhase phase;

  /// The app is blocked until it is updated.
  final bool mandatory;
  final AppRelease? release;

  /// 0..1 while downloading.
  final double progress;
  final String? error;

  bool get visible => phase != UpdatePhase.idle;

  UpdateState copyWith({
    UpdatePhase? phase,
    bool? mandatory,
    AppRelease? release,
    double? progress,
    String? error,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        mandatory: mandatory ?? this.mandatory,
        release: release ?? this.release,
        progress: progress ?? this.progress,
        error: error,
      );
}

/// The in-app update (the direct APK): asks the server for the latest release
/// when the app opens and whenever it comes back to the screen, and walks the
/// person through download → check → install.
///
/// Fail-safe by design:
///  * it never blocks without a published release that is newer than this
///    build (withdraw a release in the database and every phone is free again);
///  * a phone that cannot reach the server is blocked only if the last answer
///    it got said so;
///  * the file is installed only after its SHA-256 matches the published one
///    (and Android itself refuses a file signed with another key).
class AppUpdateController extends StateNotifier<UpdateState> {
  AppUpdateController({
    required AppUpdateRepository repository,
    required UpdateEngine engine,
    required this.installedBuild,
    required this.enabled,
    DateTime Function()? now,
    this.minGap = const Duration(minutes: 3),
  })  : _repo = repository,
        _engine = engine,
        _now = now ?? DateTime.now,
        super(const UpdateState());

  final AppUpdateRepository _repo;
  final UpdateEngine _engine;
  final DateTime Function() _now;

  /// This APK's build number.
  final int installedBuild;

  /// False for the Play build, a debug run and everything but Android.
  final bool enabled;

  /// The shortest time between two checks made by coming back to the app.
  final Duration minGap;

  DateTime? _lastCheck;
  bool _busy = false;
  int? _dismissedBuild;

  /// Asks the server whether this build is current.
  Future<void> check({bool force = false}) async {
    // build 0 is a debug run: never asked
    if (!enabled || installedBuild <= 0 || _busy) return;
    if (const {
      UpdatePhase.downloading,
      UpdatePhase.verifying,
    }.contains(state.phase)) {
      return;
    }
    final now = _now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < minGap) {
      return;
    }
    _lastCheck = now;

    AppRelease? release;
    var reached = true;
    try {
      release = await _repo.fetchLatest();
    } catch (e) {
      reached = false;
      release = _repo.cached(); // a forced update stays forced offline
    }
    if (!mounted) return;

    switch (updateNeed(installedBuild: installedBuild, release: release)) {
      case UpdateNeed.none:
        state = const UpdateState();
        // up to date (or the release was withdrawn): drop old downloads
        if (reached) unawaited(_engine.cleanup());
      case UpdateNeed.optional:
        if (_dismissedBuild == release!.buildNumber) {
          state = const UpdateState();
        } else {
          _offer(release, mandatory: false);
        }
      case UpdateNeed.required:
        _offer(release!, mandatory: true);
    }
  }

  void _offer(AppRelease release, {required bool mandatory}) {
    // keep a download / permission / error already on screen for this build
    if (state.release?.buildNumber == release.buildNumber &&
        state.phase != UpdatePhase.idle &&
        state.phase != UpdatePhase.offered) {
      state = state.copyWith(mandatory: mandatory, release: release);
      return;
    }
    state = UpdateState(
      phase: UpdatePhase.offered,
      mandatory: mandatory,
      release: release,
    );
  }

  /// "Later" (only for an optional update; a mandatory one cannot be put off).
  void dismiss() {
    if (state.mandatory) return;
    _dismissedBuild = state.release?.buildNumber;
    state = const UpdateState();
  }

  /// "تحديث الآن" / "إعادة المحاولة" / "تثبيت": download if needed, check the
  /// file, make sure Android allows installing, then open the installer.
  Future<void> start() async {
    final release = state.release;
    if (release == null || _busy) return;
    _busy = true;
    try {
      final file = release.fileFor(await _engine.abis());
      if (file == null) {
        _fail('لا يوجد ملف تحديث مناسب لمعالج هاتفك. تواصل مع الإدارة.');
        return;
      }
      final dest =
          '${await _engine.updatesDir()}/Eshary-${release.buildNumber}.apk';

      if (!await _engine.fileMatches(dest, file.sha256, file.size)) {
        state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
        var last = -1;
        await _engine.download(file.url, dest, (received, total) {
          final total0 = total > 0 ? total : file.size;
          if (total0 <= 0 || !mounted) return;
          final pct = (received * 100 ~/ total0).clamp(0, 100);
          if (pct == last) return;
          last = pct;
          state = state.copyWith(progress: pct / 100);
        });
        if (!mounted) return;
        state = state.copyWith(phase: UpdatePhase.verifying, progress: 1);
        if (!await _engine.fileMatches(dest, file.sha256, file.size)) {
          await _engine.cleanup();
          _fail('الملف المنزَّل غير سليم ولم يُثبَّت. أعد المحاولة.');
          return;
        }
      }

      if (!await _engine.canInstall()) {
        state = state.copyWith(phase: UpdatePhase.needsPermission);
        return;
      }
      state = state.copyWith(phase: UpdatePhase.ready);
      await _engine.install(dest);
    } catch (e, st) {
      AppLogger.error('appUpdate.start', e, st);
      _fail(_friendly(e));
    } finally {
      _busy = false;
    }
  }

  /// Opens the Android page where the person lets this app install apps.
  Future<void> openPermissionSettings() async {
    try {
      await _engine.openInstallSettings();
    } catch (e, st) {
      AppLogger.error('appUpdate.settings', e, st);
    }
  }

  /// The app came back to the screen: finish the install if the person has just
  /// allowed it, otherwise look for a newer release.
  Future<void> onResumed() async {
    if (!enabled) return;
    if (state.phase == UpdatePhase.needsPermission) {
      if (await _engine.canInstall()) {
        await start();
      }
      return;
    }
    await check();
  }

  void _fail(String message) {
    if (!mounted) return;
    state = state.copyWith(phase: UpdatePhase.failed, error: message);
  }

  static String _friendly(Object e) {
    if (e is SocketException || e is TimeoutException) {
      return 'تعذّر الاتصال بالإنترنت. تحقق من الاتصال ثم أعد المحاولة.';
    }
    if (e is HttpException) {
      return 'تعذّر تنزيل التحديث الآن. أعد المحاولة بعد قليل.';
    }
    return 'تعذّر إكمال التحديث. أعد المحاولة.';
  }
}

/// The phone's real update engine (a test replaces it).
final updateEngineProvider = Provider<UpdateEngine>((ref) {
  return PlatformUpdateEngine();
});

/// Only the direct APK on Android, and only a distributed build
/// (APP_BUILD > 0): never the Play build, the web or a debug run.
final appUpdateEnabled = !kIsWeb && !kPlayBuild && kAppBuild > 0 && _android;
bool get _android {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, UpdateState>((ref) {
  return AppUpdateController(
    repository: ref.watch(appUpdateRepositoryProvider),
    engine: ref.watch(updateEngineProvider),
    installedBuild: kAppBuild,
    enabled: appUpdateEnabled,
  );
});
