import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'settings.dart';

/// Loads and saves [Settings] as a JSON file in the app documents directory.
class SettingsStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/settings.json');
  }

  static Future<Settings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const Settings();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return Settings.fromJson(map);
    } catch (_) {
      return const Settings();
    }
  }

  static Future<void> save(Settings settings) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    } catch (_) {
      // Persisting settings is best-effort; ignore write failures.
    }
  }
}
