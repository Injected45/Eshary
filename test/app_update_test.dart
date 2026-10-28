import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:eshary/core/theme.dart';
import 'package:eshary/features/app_update/data/app_update_repository.dart';
import 'package:eshary/features/app_update/data/update_engine.dart';
import 'package:eshary/features/app_update/domain/app_release.dart';
import 'package:eshary/features/app_update/presentation/app_update_controller.dart';
import 'package:eshary/features/app_update/presentation/update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------- helpers

String _sha(List<int> bytes) => sha256.convert(bytes).toString();
final _bytes64 = List<int>.generate(2000, (i) => i % 251);
final _bytes32 = List<int>.generate(1500, (i) => (i * 7) % 251);

AppRelease _release(
  int build, {
  bool mandatory = true,
  int? min,
  String? notes = 'إصلاحات وتحسينات',
}) =>
    AppRelease(
      buildNumber: build,
      versionName: '1.0.$build',
      notes: notes,
      mandatory: mandatory,
      minBuildNumber: min ?? (mandatory ? build : 0),
      files: {
        'arm64-v8a': ReleaseFile(
          url: 'https://x/$build/Eshary-64.apk',
          sha256: _sha(_bytes64),
          size: _bytes64.length,
        ),
        'armeabi-v7a': ReleaseFile(
          url: 'https://x/$build/Eshary-32.apk',
          sha256: _sha(_bytes32),
          size: _bytes32.length,
        ),
      },
    );

class _FakeRepo implements AppUpdateRepository {
  AppRelease? latest;
  AppRelease? cachedRelease;
  bool offline = false;
  int fetches = 0;

  @override
  Future<AppRelease?> fetchLatest() async {
    fetches++;
    if (offline) throw const SocketException('offline');
    cachedRelease = latest;
    return latest;
  }

  @override
  AppRelease? cached() => cachedRelease;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeEngine implements UpdateEngine {
  List<String> phoneAbis = ['arm64-v8a', 'armeabi-v7a'];
  bool allowed = true;
  bool corrupt = false;
  bool downloadFails = false;
  final files = <String, List<int>>{};
  final downloads = <String>[];
  final installs = <String>[];
  int cleanups = 0;
  int settingsOpened = 0;
  Completer<void>? holdDownload;

  @override
  Future<String> updatesDir() async => '/cache/updates';

  @override
  Future<List<String>> abis() async => phoneAbis;

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<void> install(String path) async => installs.add(path);

  @override
  Future<void> download(
    String url,
    String dest,
    void Function(int received, int total) onProgress,
  ) async {
    downloads.add(url);
    if (downloadFails) throw const SocketException('no network');
    final data = url.endsWith('64.apk') ? _bytes64 : _bytes32;
    onProgress(data.length ~/ 2, data.length);
    if (holdDownload != null) await holdDownload!.future;
    onProgress(data.length, data.length);
    files[dest] = corrupt ? [...data.take(10)] : data;
  }

  @override
  Future<bool> fileMatches(String path, String sha256Hex, int size) async {
    final f = files[path];
    return f != null && _sha(f) == sha256Hex && (size == 0 || f.length == size);
  }

  @override
  Future<void> cleanup() async {
    cleanups++;
    files.clear();
  }
}

class _Setup {
  _Setup({this.installed = 5, this.enabled = true}) {
    controller = AppUpdateController(
      repository: repo,
      engine: engine,
      installedBuild: installed,
      enabled: enabled,
      now: () => clock,
    );
  }

  final int installed;
  final bool enabled;
  final repo = _FakeRepo();
  final engine = _FakeEngine();
  DateTime clock = DateTime(2026, 10, 28, 12);
  late final AppUpdateController controller;
}

Future<_Setup> _pumpApp(
  WidgetTester tester, {
  required void Function(_Setup) arrange,
  int installed = 5,
  bool enabled = true,
  VoidCallback? onChildTap,
}) async {
  final s = _Setup(installed: installed, enabled: enabled);
  arrange(s);
  await tester.binding.setSurfaceSize(const Size(420, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appUpdateProvider.overrideWith((ref) => s.controller)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: UpdateGate(
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const ValueKey('app-button'),
                onPressed: onChildTap ?? () {},
                child: const Text('التطبيق'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return s;
}

const _screen = ValueKey('update-screen');

void main() {
  group('what the app must do', () {
    test('up to date, no release, or a debug run: nothing', () {
      expect(updateNeed(installedBuild: 5, release: null), UpdateNeed.none);
      expect(
        updateNeed(installedBuild: 5, release: _release(5)),
        UpdateNeed.none,
      );
      expect(
        updateNeed(installedBuild: 9, release: _release(5)),
        UpdateNeed.none,
      );
      expect(
        updateNeed(installedBuild: 0, release: _release(99)),
        UpdateNeed.none,
        reason: 'build 0 = flutter run',
      );
    });

    test('older than a mandatory release: required', () {
      expect(
        updateNeed(installedBuild: 4, release: _release(5)),
        UpdateNeed.required,
      );
    });

    test('older than an optional release: optional', () {
      expect(
        updateNeed(installedBuild: 4, release: _release(5, mandatory: false)),
        UpdateNeed.optional,
      );
    });

    test('a later optional release never un-forces an older mandatory one', () {
      final r = _release(6, mandatory: false, min: 5);
      expect(updateNeed(installedBuild: 4, release: r), UpdateNeed.required);
      expect(updateNeed(installedBuild: 5, release: r), UpdateNeed.optional);
      expect(updateNeed(installedBuild: 6, release: r), UpdateNeed.none);
    });

    test('the file follows the phone processor, best first', () {
      final r = _release(5);
      expect(r.fileFor(['arm64-v8a', 'armeabi-v7a'])!.url, endsWith('64.apk'));
      expect(r.fileFor(['armeabi-v7a'])!.url, endsWith('32.apk'));
      expect(r.fileFor(['x86_64']), isNull);
    });

    test('the server answer is read, and survives the cache round trip', () {
      final r = AppRelease.fromJson({
        'buildNumber': 7,
        'versionName': '1.0.7',
        'notes': null,
        'mandatory': true,
        'minBuildNumber': 7,
        'files': {
          'arm64-v8a': {'url': 'https://x', 'sha256': 'AB' * 32, 'size': 3},
        },
      });
      expect(r.files['arm64-v8a']!.sha256, 'ab' * 32, reason: 'lower-cased');
      final back = AppRelease.fromJson(r.toJson());
      expect(back.buildNumber, 7);
      expect(back.minBuildNumber, 7);
      expect(back.files['arm64-v8a']!.size, 3);
    });
  });

  group('the downloaded file is checked', () {
    test('only the exact SHA-256 (and size) passes', () async {
      final dir = await Directory.systemTemp.createTemp('upd');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/a.apk')..writeAsBytesSync(_bytes64);
      expect(
        await fileHasSha256(f.path, _sha(_bytes64), _bytes64.length),
        isTrue,
      );
      expect(
        await fileHasSha256(f.path, _sha(_bytes64).toUpperCase(), 0),
        isTrue,
      );
      expect(await fileHasSha256(f.path, _sha(_bytes32), 0), isFalse);
      expect(
        await fileHasSha256(f.path, _sha(_bytes64), 5),
        isFalse,
        reason: 'size',
      );
      expect(
        await fileHasSha256('${dir.path}/none.apk', _sha(_bytes64), 0),
        isFalse,
      );
      f.writeAsBytesSync([..._bytes64, 1]);
      expect(
        await fileHasSha256(f.path, _sha(_bytes64), 0),
        isFalse,
        reason: 'one more byte',
      );
    });
  });

  group('the gate', () {
    testWidgets('up to date: the app is untouched', (tester) async {
      final s =
          await _pumpApp(tester, arrange: (s) => s.repo.latest = _release(5));
      expect(find.byKey(_screen), findsNothing);
      expect(s.repo.fetches, 1);
    });

    testWidgets('no release published: nothing', (tester) async {
      await _pumpApp(tester, arrange: (s) => s.repo.latest = null);
      expect(find.byKey(_screen), findsNothing);
    });

    testWidgets('a debug run (build 0) is never asked', (tester) async {
      final s = await _pumpApp(
        tester,
        installed: 0,
        arrange: (s) => s.repo.latest = _release(99),
      );
      expect(find.byKey(_screen), findsNothing);
      expect(s.repo.fetches, 0);
    });

    testWidgets('the Play build (updater off) is never asked', (tester) async {
      final s = await _pumpApp(
        tester,
        enabled: false,
        arrange: (s) => s.repo.latest = _release(99),
      );
      expect(find.byKey(_screen), findsNothing);
      expect(s.repo.fetches, 0);
    });

    testWidgets('a mandatory update blocks the app and cannot be dismissed', (
      tester,
    ) async {
      var taps = 0;
      await _pumpApp(
        tester,
        arrange: (s) => s.repo.latest = _release(6),
        onChildTap: () => taps++,
      );
      expect(find.byKey(_screen), findsOneWidget);
      expect(find.text('تحديث إلزامي'), findsOneWidget);
      expect(find.textContaining('1.0.6'), findsOneWidget);
      expect(find.text('إصلاحات وتحسينات'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-later')), findsNothing);
      // the app behind it cannot be reached
      await tester.tap(
        find.byKey(const ValueKey('app-button')),
        warnIfMissed: false,
      );
      expect(taps, 0);
      final pop = tester.widget<PopScope>(
        find.descendant(
          of: find.byType(UpdateGate),
          matching: find.byType(PopScope),
        ),
      );
      expect(pop.canPop, isFalse, reason: 'the back button cannot leave it');
    });

    testWidgets('update now: download, check, then the installer',
        (tester) async {
      final s =
          await _pumpApp(tester, arrange: (s) => s.repo.latest = _release(6));
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pump();
      await tester.pump();
      expect(
        s.engine.downloads,
        ['https://x/6/Eshary-64.apk'],
        reason: 'the 64-bit file for a 64-bit phone',
      );
      expect(s.engine.installs, ['/cache/updates/Eshary-6.apk']);
      expect(
        find.byKey(const ValueKey('update-install')),
        findsOneWidget,
        reason: 'if the person cancels the installer, "تثبيت" is still there',
      );
    });

    testWidgets('a 32-bit phone gets the 32-bit file', (tester) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.latest = _release(6);
          s.engine.phoneAbis = ['armeabi-v7a'];
        },
      );
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pump();
      await tester.pump();
      expect(s.engine.downloads, ['https://x/6/Eshary-32.apk']);
    });

    testWidgets('the progress is shown while it downloads', (tester) async {
      final hold = Completer<void>();
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.latest = _release(6);
          s.engine.holdDownload = hold;
        },
      );
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('update-now')),
        findsNothing,
        reason: 'no second download can be started',
      );
      hold.complete();
      await tester.pump();
      await tester.pump();
      expect(s.engine.installs, hasLength(1));
    });

    testWidgets('a damaged file is never installed', (tester) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.latest = _release(6);
          s.engine.corrupt = true;
        },
      );
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pump();
      await tester.pump();
      expect(s.engine.installs, isEmpty);
      expect(
        s.engine.cleanups,
        greaterThan(0),
        reason: 'the bad file is removed',
      );
      expect(find.textContaining('غير سليم'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-retry')), findsOneWidget);
      // retry with a good download
      s.engine.corrupt = false;
      await tester.tap(find.byKey(const ValueKey('update-retry')));
      await tester.pump();
      await tester.pump();
      expect(s.engine.installs, hasLength(1));
    });

    testWidgets('no network: an Arabic message and retry, still blocked', (
      tester,
    ) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.latest = _release(6);
          s.engine.downloadFails = true;
        },
      );
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('الاتصال بالإنترنت'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('update-later')), findsNothing);
      expect(s.engine.installs, isEmpty);
    });

    testWidgets(
        'Android has not allowed installing: the person is guided, then it continues by itself',
        (
      tester,
    ) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.latest = _release(6);
          s.engine.allowed = false;
        },
      );
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('update-settings')), findsOneWidget);
      expect(s.engine.installs, isEmpty);
      await tester.tap(find.byKey(const ValueKey('update-settings')));
      await tester.pump();
      expect(s.engine.settingsOpened, 1);

      // back from the settings, allowed now: the install starts (no new download)
      s.engine.allowed = true;
      await s.controller.onResumed();
      await tester.pump();
      expect(s.engine.installs, ['/cache/updates/Eshary-6.apk']);
      expect(s.engine.downloads, hasLength(1));
    });

    testWidgets(
        'an optional update can be put off, and is not asked again for that build',
        (
      tester,
    ) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) => s.repo.latest = _release(6, mandatory: false),
      );
      expect(find.text('يتوفر تحديث جديد'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-later')));
      await tester.pump();
      expect(find.byKey(_screen), findsNothing);
      s.clock = s.clock.add(const Duration(minutes: 10));
      await s.controller.check();
      await tester.pump();
      expect(
        find.byKey(_screen),
        findsNothing,
        reason: 'same build: not again',
      );
      // a newer build is offered again
      s.repo.latest = _release(7, mandatory: false);
      s.clock = s.clock.add(const Duration(minutes: 10));
      await s.controller.check();
      await tester.pump();
      expect(find.byKey(_screen), findsOneWidget);
    });

    testWidgets('a withdrawn release frees the app at once', (tester) async {
      final s =
          await _pumpApp(tester, arrange: (s) => s.repo.latest = _release(6));
      expect(find.byKey(_screen), findsOneWidget);
      s.repo.latest = null; // withdrawn in the database
      await s.controller.check(force: true);
      await tester.pump();
      expect(find.byKey(_screen), findsNothing);
    });

    testWidgets('offline: a forced update stays forced', (tester) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.cachedRelease = _release(6); // what the last visit said
          s.repo.offline = true;
        },
      );
      expect(find.byKey(_screen), findsOneWidget);
      expect(find.text('تحديث إلزامي'), findsOneWidget);
      expect(s.repo.fetches, 1);
    });

    testWidgets('offline with nothing known: the app is free', (tester) async {
      final s = await _pumpApp(
        tester,
        arrange: (s) {
          s.repo.cachedRelease = null;
          s.repo.offline = true;
        },
      );
      expect(find.byKey(_screen), findsNothing);
      expect(s.repo.fetches, 1);
    });

    testWidgets('coming back to the app checks again, but not every second', (
      tester,
    ) async {
      final s =
          await _pumpApp(tester, arrange: (s) => s.repo.latest = _release(5));
      expect(s.repo.fetches, 1);
      await s.controller.onResumed();
      expect(s.repo.fetches, 1, reason: 'within 3 minutes');
      s.clock = s.clock.add(const Duration(minutes: 4));
      s.repo.latest = _release(6);
      await s.controller.onResumed();
      await tester.pump();
      expect(s.repo.fetches, 2);
      expect(
        find.byKey(_screen),
        findsOneWidget,
        reason: 'a release published meanwhile',
      );
    });
  });

  downloadTests();

  group('the wiring', () {
    final main = File('lib/main.dart').readAsStringSync();

    test('the gate wraps the whole app (the sign-in screens too)', () {
      expect(main, contains('UpdateGate('));
      expect(
        main,
        contains("features/app_update/presentation/update_gate.dart"),
      );
    });

    test('only the direct APK on Android, only a distributed build', () {
      final c = File(
        'lib/features/app_update/presentation/app_update_controller.dart',
      ).readAsStringSync();
      expect(c, contains('!kPlayBuild'));
      expect(c, contains('kAppBuild > 0'));
      expect(c, contains('Platform.isAndroid'));
    });

    test('the installer permission is NOT in the Google Play manifest', () {
      final play =
          File('android/app/src/play/AndroidManifest.xml').readAsStringSync();
      final direct =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(play, isNot(contains('REQUEST_INSTALL_PACKAGES')));
      expect(play, isNot(contains('FileProvider')));
      expect(direct, contains('REQUEST_INSTALL_PACKAGES'));
      expect(direct, contains(r'${applicationId}.updates'));
    });

    test('the native side installs only a file it downloaded itself', () {
      final kt =
          File('android/app/src/main/kotlin/com/rahala/eshary/MainActivity.kt')
              .readAsStringSync();
      expect(kt, contains('eshary/update'));
      expect(kt, contains('canonicalFile.parentFile != dir.canonicalFile'));
      final paths = File('android/app/src/main/res/xml/update_paths.xml')
          .readAsStringSync();
      expect(paths, contains('cache-path'));
      expect(paths, contains('updates/'));
    });

    test('every build gets the next number and says so to the app', () {
      final bat = File('build-apk.bat').readAsStringSync();
      expect(bat, contains('bump-build.mjs'));
      expect(bat, contains('--dart-define=APP_BUILD=%BUILD%'));
      expect(bat, contains('--build-number=%BUILD%'));
      expect(bat, contains('build.json'));
    });

    test('downloads are https only', () {
      final e = File('lib/features/app_update/data/update_engine.dart')
          .readAsStringSync();
      expect(e, contains("uri.scheme != 'https'"));
    });
  });
}

/// The real download, against a local server: streaming to a file, progress,
/// no half file left behind, and https only.
void downloadTests() {
  group('the real download', () {
    late HttpServer server;
    late Directory dir;
    final engine = PlatformUpdateEngine(allowLoopbackHttp: true);

    setUp(() async {
      // the test binding answers every HttpClient with 400; this needs the real one
      HttpOverrides.global = null;
      dir = await Directory.systemTemp.createTemp('dl');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/ok.apk') {
          req.response.contentLength = _bytes64.length;
          req.response.add(_bytes64);
        } else if (req.uri.path == '/chunked.apk') {
          for (var i = 0; i < _bytes64.length; i += 500) {
            req.response
                .add(_bytes64.sublist(i, (i + 500).clamp(0, _bytes64.length)));
            await req.response.flush();
          }
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    String url(String p) => 'http://127.0.0.1:${server.port}$p';

    test('saves the file, reports progress, leaves no .part file', () async {
      final dest = '${dir.path}/a.apk';
      final seen = <int>[];
      await engine.download(url('/ok.apk'), dest, (r, t) {
        seen.add(r);
        expect(t, _bytes64.length);
      });
      expect(File(dest).readAsBytesSync(), _bytes64);
      expect(seen.last, _bytes64.length);
      expect(File('$dest.part').existsSync(), isFalse);
      expect(
        await engine.fileMatches(dest, _sha(_bytes64), _bytes64.length),
        isTrue,
      );
    });

    test('a chunked answer (no length) works', () async {
      final dest = '${dir.path}/b.apk';
      await engine.download(url('/chunked.apk'), dest, (r, t) {});
      expect(File(dest).readAsBytesSync(), _bytes64);
    });

    test('a missing file fails and leaves nothing', () async {
      final dest = '${dir.path}/c.apk';
      await expectLater(
        engine.download(url('/nope.apk'), dest, (r, t) {}),
        throwsA(isA<HttpException>()),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('a cut connection fails and leaves no half file to install', () async {
      // a raw server that promises 5000 bytes, sends 2000 and hangs up
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      raw.listen((sock) async {
        sock.add(
          'HTTP/1.1 200 OK\r\nContent-Length: 5000\r\n\r\n'.codeUnits,
        );
        sock.add(_bytes64);
        await sock.flush();
        sock.destroy();
      });
      final dest = '${dir.path}/d.apk';
      await expectLater(
        engine.download(
          'http://127.0.0.1:${raw.port}/cut.apk',
          dest,
          (r, t) {},
        ),
        throwsA(anything),
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('an old file is replaced, never appended to', () async {
      final dest = '${dir.path}/e.apk';
      File(dest).writeAsBytesSync([1, 2, 3]);
      await engine.download(url('/ok.apk'), dest, (r, t) {});
      expect(File(dest).readAsBytesSync(), _bytes64);
    });

    test('the real app never accepts http (only https)', () async {
      await expectLater(
        PlatformUpdateEngine()
            .download(url('/ok.apk'), '${dir.path}/f.apk', (r, t) {}),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        PlatformUpdateEngine().download(
          'ftp://example.com/a.apk',
          '${dir.path}/g.apk',
          (r, t) {},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
