/// Product metadata shared by the About UI, the update checker and packaging.
///
/// [version] is the single Dart-side source of truth. It is kept in sync with
/// `pubspec.yaml` and `installer/docforge.iss` by `tool/bump_version.py`, and a
/// unit test fails when the three drift apart.
class AppInfo {
  const AppInfo._();

  static const String name = 'DocForge';
  static const String version = '1.0.1';
  static const String platform = 'Windows';

  static const String repository = 'SamsonOyieyo/DocForge';
  static const String repositoryUrl = 'https://github.com/$repository';
  static const String releasesUrl = '$repositoryUrl/releases';
  static const String releaseListApi =
      'https://api.github.com/repos/$repository/releases?per_page=20';
  static const String checksumsAsset = 'SHA256SUMS.txt';
  static const String installerPrefix = 'DocForge-Setup-';
  static const String userAgent = 'DocForge/$version ($repositoryUrl)';

  /// Release tag created for [version] (`v1.0.0`).
  static String get releaseTag => 'v$version';

  static String get displayVersion => 'v$version';
}
