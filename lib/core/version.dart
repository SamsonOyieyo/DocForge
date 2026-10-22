import 'dart:math' as math;

/// Compares dotted versions such as `12.4.2`, `10.05.0`, `1.2.0-rc1` or
/// `v1.0.0+42`.
///
/// Returns a negative number when [a] is older, `0` when equal and a positive
/// number when [a] is newer. Unparsable versions fall back to a stable string
/// comparison so a publisher with an exotic tag cannot crash an updater.
int compareVersions(String a, String b) {
  if (a == b) return 0;
  final left = _ParsedVersion.parse(a);
  final right = _ParsedVersion.parse(b);
  if (left == null || right == null) {
    return a.compareTo(b) > 0 ? 1 : -1;
  }

  final length = math.max(left.numbers.length, right.numbers.length);
  for (var i = 0; i < length; i++) {
    final x = i < left.numbers.length ? left.numbers[i] : 0;
    final y = i < right.numbers.length ? right.numbers[i] : 0;
    if (x != y) return x.compareTo(y);
  }

  // A release is newer than any of its pre-releases (`1.0.0 > 1.0.0-rc1`).
  final x = left.prerelease;
  final y = right.prerelease;
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y) == 0 ? 0 : (x.compareTo(y) > 0 ? 1 : -1);
}

bool isNewerVersion(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.prerelease);

  final List<int> numbers;
  final String? prerelease;

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.\-]+))?(?:\+[0-9A-Za-z.\-]+)?$',
  );

  static _ParsedVersion? parse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    return _ParsedVersion([
      for (final part in match.group(1)!.split('.')) int.parse(part),
    ], match.group(2));
  }
}
