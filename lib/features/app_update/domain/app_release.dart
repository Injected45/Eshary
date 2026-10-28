/// One APK file of a release, for one processor type.
class ReleaseFile {
  const ReleaseFile({
    required this.url,
    required this.sha256,
    required this.size,
  });

  final String url;

  /// Lower-case hex SHA-256 of the file: the phone checks it before installing.
  final String sha256;
  final int size;

  factory ReleaseFile.fromJson(Map<String, dynamic> json) => ReleaseFile(
        url: json['url'] as String,
        sha256: (json['sha256'] as String).toLowerCase(),
        size: (json['size'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'url': url, 'sha256': sha256, 'size': size};
}

/// A published build of the app (the row of `app_releases`, see migration 0079,
/// as `latest_app_release()` returns it).
class AppRelease {
  const AppRelease({
    required this.buildNumber,
    required this.versionName,
    required this.mandatory,
    required this.minBuildNumber,
    required this.files,
    this.notes,
  });

  /// The newest active release.
  final int buildNumber;
  final String versionName;
  final String? notes;
  final bool mandatory;

  /// The newest active MANDATORY release: an app older than this must update
  /// even when the newest release is optional.
  final int minBuildNumber;

  /// By processor type: `arm64-v8a`, `armeabi-v7a`.
  final Map<String, ReleaseFile> files;

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final raw = (json['files'] as Map<String, dynamic>? ?? const {});
    return AppRelease(
      buildNumber: (json['buildNumber'] as num).toInt(),
      versionName: json['versionName'] as String,
      notes: json['notes'] as String?,
      mandatory: json['mandatory'] as bool? ?? true,
      minBuildNumber: (json['minBuildNumber'] as num?)?.toInt() ?? 0,
      files: {
        for (final e in raw.entries)
          e.key: ReleaseFile.fromJson(e.value as Map<String, dynamic>),
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'buildNumber': buildNumber,
        'versionName': versionName,
        'notes': notes,
        'mandatory': mandatory,
        'minBuildNumber': minBuildNumber,
        'files': {for (final e in files.entries) e.key: e.value.toJson()},
      };

  /// The file for this phone: the first of its processor types (best first)
  /// that the release has. Null when none fits (nothing can be installed).
  ReleaseFile? fileFor(List<String> abis) {
    for (final abi in abis) {
      final f = files[abi];
      if (f != null) return f;
    }
    return null;
  }
}

/// What the app must do about a release.
enum UpdateNeed {
  /// Up to date, no release, or not a distributed build.
  none,

  /// A newer release exists, but this build may keep working (it can be put off).
  optional,

  /// This build is older than the newest mandatory release: blocked until updated.
  required,
}

/// Decides from the installed build ([installedBuild], 0 = a debug run) and the
/// latest release. A later optional release never un-forces an older mandatory
/// one ([AppRelease.minBuildNumber]).
UpdateNeed updateNeed({
  required int installedBuild,
  required AppRelease? release,
}) {
  if (release == null || installedBuild <= 0) return UpdateNeed.none;
  if (installedBuild >= release.buildNumber) return UpdateNeed.none;
  if (installedBuild < release.minBuildNumber) return UpdateNeed.required;
  return UpdateNeed.optional;
}
