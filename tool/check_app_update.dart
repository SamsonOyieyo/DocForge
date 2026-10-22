// Checks the public GitHub release feed with the same code the app uses.
//
// Usage:
//   dart run tool/check_app_update.dart
//
// Useful after publishing a release to confirm the updater can see the
// installer and its SHA256SUMS.txt asset.

import 'dart:io';

import 'package:docforge/core/app_info.dart';
import 'package:docforge/core/app_update.dart';

Future<void> main() async {
  final service = AppUpdateService();
  try {
    final release = await service.latestRelease();
    if (release == null) {
      stdout.writeln(
        'No ${AppInfo.name} release with a Windows installer was found.',
      );
      return;
    }
    stdout.writeln('Installed: ${AppInfo.version}');
    stdout.writeln('Latest:    ${release.version}');
    stdout.writeln(
      'Installer: ${release.assetName} (${release.assetSize} bytes)',
    );
    stdout.writeln(
      'Checksums: ${release.checksumsUrl ?? 'missing (updates will be refused)'}',
    );
    stdout.writeln(
      release.isNewerThanCurrent
          ? 'An update is available.'
          : 'Already up to date.',
    );
  } on AppUpdateException catch (error) {
    stderr.writeln('Update check failed: ${error.message}');
    exitCode = 1;
  }
}
