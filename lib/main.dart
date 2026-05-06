import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/license/presentation/license_provider.dart';
import 'shared/cache.dart';
import 'shared/liquid_background.dart';
import 'shared/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF020617),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  if (!Env.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );
  final prefs = await SharedPreferences.getInstance();
  AppLogger.init(prefs);

  FlutterError.onError = (details) {
    AppLogger.error(
      'FlutterError',
      details.exceptionAsString(),
      details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('PlatformDispatcher', error, stack);
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const EsharyApp(),
    ),
  );
}

class EsharyApp extends ConsumerStatefulWidget {
  const EsharyApp({super.key});

  @override
  ConsumerState<EsharyApp> createState() => _EsharyAppState();
}

class _EsharyAppState extends ConsumerState<EsharyApp> {
  // Re-entrancy guard so a single 'blocked' transition does not call
  // signOut twice if the provider re-emits while the call is in flight.
  bool _signingOut = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Force-logout when an admin blocks this user. Acts only when:
    //  - there is a current session (otherwise nothing to sign out),
    //  - the new value is fresh data (not loading / error),
    //  - the server explicitly reports status='blocked' (no cache fallback —
    //    LicenseRepository refuses to cache negative states).
    ref.listen(licenseStatusProvider, (_, next) {
      next.whenData((s) async {
        if (s.status != 'blocked') return;
        if (_signingOut) return;
        if (Supabase.instance.client.auth.currentSession == null) return;
        _signingOut = true;
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (e, st) {
          AppLogger.error('license.forceSignOut', e, st);
        } finally {
          _signingOut = false;
        }
      });
    });

    return MaterialApp.router(
      title: 'شركة الرحالة',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: LiquidBackground(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'SUPABASE_URL / SUPABASE_ANON_KEY missing.\n\n'
                'Run with:\n'
                '  flutter run --dart-define=SUPABASE_URL=...'
                ' --dart-define=SUPABASE_ANON_KEY=...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
