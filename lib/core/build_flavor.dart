/// True in the Google Play build (built by build-aab.bat with
/// `--dart-define=PLAY_BUILD=true`). That build has no always-on background
/// service and no battery-optimisation exemption, both of which Google Play
/// restricts; the direct APK keeps them.
const bool kPlayBuild = bool.fromEnvironment('PLAY_BUILD');

/// How users reach the company about privacy and account deletion (set with
/// `--dart-define=SUPPORT_EMAIL=...` in the build scripts). Empty: the app says
/// to write to the administration inside the app.
const String kSupportEmail = String.fromEnvironment('SUPPORT_EMAIL');
