import 'dart:ffi';
import 'dart:io';
/// Host OS + ABI identifier used to pick an engine package.
///
/// The keys mirror the names in `engines_manifest.json` (`android-arm64-v8a`,
/// `windows-x64`, `macos-arm64`, `linux-x64`) so the CI workflow, the manifest
/// and the runtime agree without a translation table.
class EnginePlatform {
  const EnginePlatform({required this.os, required this.arch});

  /// `android`, `windows`, `macos`, `linux` or `ios`.
  final String os;

  /// `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`, `x64`, `arm64` or `ia32`.
  final String arch;

  String get key => '$os-$arch';

  bool get isAndroid => os == 'android';
  bool get isWindows => os == 'windows';

  /// Android 10 (API 29) removed `execve` permission for files in the app home
  /// directory, so a downloaded executable can only be *listed*, not executed,
  /// on a modern store build. See `docs/ENGINES_OTA.md`.
  bool get canExecuteFromAppStorage => !isAndroid;

  /// Engine archives contain Unix permissions; only POSIX hosts honour them.
  bool get needsChmod => isAndroid || os == 'linux' || os == 'macos';

  static EnginePlatform? _cached;

  static EnginePlatform get current => _cached ??= _detect();

  static EnginePlatform _detect() => forAbi(
        os: Platform.operatingSystem,
        abi: Abi.current(),
      );

  static EnginePlatform forAbi({required String os, required Abi abi}) =>
      fromAbiName(os: os, abiName: abi.toString());

  /// Pure mapping so every target can be unit-tested on one host.
  ///
  /// [abiName] is the `dart:ffi` spelling (`android_arm64`, `windows_x64`, …);
  /// string parsing avoids depending on the `Abi` constants, which differ
  /// between Dart SDK releases.
  static EnginePlatform fromAbiName({
    required String os,
    required String abiName,
  }) {
    final arch = abiName.contains('_') ? abiName.split('_').last : abiName;
    final normalized = switch ((os, arch)) {
      ('android', 'arm64') => 'arm64-v8a',
      ('android', 'arm') => 'armeabi-v7a',
      ('android', 'ia32') => 'x86',
      ('android', 'x64') => 'x86_64',
      ('windows', 'x64') => 'x64',
      ('windows', 'ia32') => 'ia32',
      ('windows', 'arm64') => 'arm64',
      ('macos', 'x64') => 'x64',
      ('macos', 'arm64') => 'arm64',
      (_, _) => arch,
    };
    return EnginePlatform(os: os, arch: normalized);
  }

  @override
  String toString() => key;
}
