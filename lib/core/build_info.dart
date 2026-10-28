/// The build number of this APK (set by build-apk.bat with
/// `--dart-define=APP_BUILD=<n>`). It is compared with the number of the
/// release published for an update. 0 (a debug run, `flutter run`) means "not a
/// distributed build": the updater stays out of the way.
const int kAppBuild = int.fromEnvironment('APP_BUILD');
