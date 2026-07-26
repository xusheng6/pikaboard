import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/position.dart';
import '../models/settings.dart';

/// Reader for the Python annotator's `.xqg` files.
///
/// Those store a single main line plus comments keyed by move index, and
/// variations that live *inside* the comment text as `{variant1}` references.
/// Importing turns each variation into a real branch of the tree and rewrites
/// the reference into the readable form the annotator displayed,
/// 【变着1: 炮二平五, 马8进7】, so the note still stands on its own.
class XqgFormat {
  const XqgFormat._();

  /// Board rows run top-down in this format, so rank 9 is row 0.
  static int _square(int row, int col) => (9 - row) * Position.files + col;

  /// A move as `r1c1r2c2`.
  static String? _uci(String compact) {
    if (compact.length != 4) return null;
    final digits = compact.split('').map(int.tryParse).toList();
    if (digits.any((d) => d == null)) return null;
    final from = _square(digits[0]!, digits[1]!);
    final to = _square(digits[2]!, digits[3]!);
    if (from < 0 || from >= Position.squareCount) return null;
    if (to < 0 || to >= Position.squareCount) return null;
    return '${Position.squareToUci(from)}${Position.squareToUci(to)}';
  }

  static bool looksLikeXqg(Map<String, dynamic> json) =>
      (json['format'] as String? ?? '').startsWith('xiangqi_annotator');

  static Game parse(
    Map<String, dynamic> json, {
    DisplayLanguage language = DisplayLanguage.simplified,
  }) {
    final fen = json['initial_fen'] as String?;
    if (fen == null) {
      throw const FormatException('Annotator file has no initial_fen');
    }
    final game = Game.fromPosition(
      Position.fromFen(fen),
      metadata: GameMetadata(title: json['title'] as String? ?? ''),
    );

    // The main line, indexed by move so comments and variations can find it.
    final byIndex = <int, GameNode>{-1: game.root};
    var node = game.root;
    final moves = (json['moves'] as List<dynamic>? ?? const []);
    for (var i = 0; i < moves.length; i++) {
      final uci = _uci(moves[i] as String? ?? '');
      if (uci == null) break;
      if (node.position.pieceAt(Position.uciToSquare(uci.substring(0, 2))!) ==
          null) {
        break; // the line does not fit the position; keep what parsed
      }
      node = node.addMove(uci);
      byIndex[i] = node;
    }

    // Variations branch from the position *before* the move they annotate, so
    // they hang off that move's parent.
    final variations = <int, List<List<String>>>{};
    final rawVariations =
        json['variations'] as Map<String, dynamic>? ?? const {};
    rawVariations.forEach((key, value) {
      final index = int.tryParse(key);
      if (index == null || value is! List) return;
      final lines = <List<String>>[];
      for (final variation in value) {
        if (variation is! Map) continue;
        final branchNode = byIndex[index];
        final parent = branchNode?.parent ?? byIndex[index - 1] ?? game.root;
        final uciMoves = <String>[];
        var cursor = parent;
        for (final move in (variation['moves'] as List<dynamic>? ?? const [])) {
          final uci = _uci(move as String? ?? '');
          if (uci == null) break;
          final from = Position.uciToSquare(uci.substring(0, 2));
          if (from == null || cursor.position.pieceAt(from) == null) break;
          uciMoves.add(MoveNotation.toNotation(uci, cursor.position, language));
          cursor = cursor.addMove(uci);
        }
        lines.add(uciMoves);
      }
      variations[index] = lines;
    });

    // Comments, with their variation references expanded in place.
    final comments = json['comments'] as Map<String, dynamic>? ?? const {};
    comments.forEach((key, value) {
      final index = int.tryParse(key);
      final target = index == null ? null : byIndex[index];
      if (target == null || value is! String) return;
      target.comment = _expandReferences(value, variations[index] ?? const []);
    });

    return game;
  }

  /// Replace `{variantN}` with the moves that variation contains.
  static String _expandReferences(String comment, List<List<String>> lines) {
    return comment.replaceAllMapped(RegExp(r'\{variant(\d+)\}'), (match) {
      final number = int.tryParse(match.group(1) ?? '') ?? 0;
      if (number < 1 || number > lines.length) return match.group(0)!;
      return '【变着$number: ${lines[number - 1].join(', ')}】';
    });
  }
}
