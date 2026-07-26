import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/game.dart';
import 'xqf.dart';

/// Loading and saving games.
///
/// Reads XQStudio's `.XQF` and this app's own JSON; writes JSON only, since it
/// is the one format that can hold everything the app records.
class GameIO {
  const GameIO._();

  /// Extension for the app's own format.
  static const String nativeExtension = 'pbg';

  /// Extensions offered when opening a file.
  static const List<String> readableExtensions = [
    'xqf',
    nativeExtension,
    'json',
  ];

  static Future<Game> load(String path) async {
    final bytes = await File(path).readAsBytes();
    return decode(bytes, path: path);
  }

  /// Parse [bytes], choosing the format by content rather than by extension so
  /// oddly-named files still open.
  static Game decode(Uint8List bytes, {String path = ''}) {
    if (XqfFormat.looksLikeXqf(bytes)) return XqfFormat.parse(bytes);

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw FormatException('Unrecognised game file: ${path.split('/').last}');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Game file is not an object');
    }
    if (json['format'] == Game.formatId) return Game.fromJson(json);
    throw FormatException('Unsupported game format: ${json['format']}');
  }

  static Future<void> save(String path, Game game) async {
    final encoder = const JsonEncoder.withIndent('  ');
    await File(path).writeAsString(encoder.convert(game.toJson()), flush: true);
  }

  /// A filename for [game] derived from what it is about.
  static String suggestedFileName(Game game) {
    final metadata = game.metadata;
    var name = metadata.title;
    if (name.isEmpty &&
        (metadata.red.isNotEmpty || metadata.black.isNotEmpty)) {
      name = '${metadata.red} vs ${metadata.black}';
    }
    if (name.isEmpty) name = 'game';
    name = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    return '$name.$nativeExtension';
  }
}
