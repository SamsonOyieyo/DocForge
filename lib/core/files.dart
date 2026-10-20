import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppFiles {
  const AppFiles._();

  static Directory? _cachedDefault;

  static Future<Directory> defaultOutputDirectory() async {
    if (_cachedDefault != null) return _cachedDefault!;
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, 'DocForge'));
    if (!directory.existsSync()) directory.createSync(recursive: true);
    _cachedDefault = directory;
    return directory;
  }

  static Future<Directory> ensureOutputDirectory(String? configured) async {
    final directory = configured != null && configured.trim().isNotEmpty
        ? Directory(configured)
        : await defaultOutputDirectory();
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return directory;
  }

  /// Opens a file with the OS default application.
  static Future<void> openFile(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  }

  /// Shows a file in Explorer/Finder/file manager.
  static Future<void> revealInFolder(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      await Process.run('xdg-open', [p.dirname(path)]);
    }
  }

  /// Returns a file name in [directory] that does not collide with an existing
  /// file, e.g. `report-compressed-2.pdf`.
  static String uniqueName(String directory, String name) {
    var candidate = p.join(directory, name);
    final extension = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var counter = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(directory, '$base-$counter$extension');
      counter++;
    }
    return p.basename(candidate);
  }

  static String humanBytes(int bytes) {    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String humanDate(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return 'Today $time';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $time';
  }

  static String extension(String path) =>
      p.extension(path).replaceFirst('.', '').toLowerCase();
}
