import 'dart:convert';
import 'dart:io';

/// One candidate move returned by the chessdb.cn cloud database.
class ChessDbMove {
  final String uci;

  /// Centipawn score from the side-to-move's perspective.
  final int score;
  final int rank;
  final String note;
  final double? winrate;

  const ChessDbMove({
    required this.uci,
    required this.score,
    required this.rank,
    required this.note,
    this.winrate,
  });
}

/// Client for the chessdb.cn Chinese-chess cloud database.
/// See https://www.chessdb.cn/cloudbook_api.html
class ChessDb {
  static const _base = 'https://www.chessdb.cn/chessdb.php';

  /// Query all known candidate moves for [fen] (a Xiangqi FEN with side to
  /// move, e.g. "rnbakabnr/9/... w"). Returns an empty list if the position
  /// is unknown or the request fails.
  static Future<List<ChessDbMove>> queryAll(String fen) async {
    final uri = Uri.parse(
      '$_base?action=queryall&board=${Uri.encodeComponent(fen)}',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) return const [];
      final body = await response.transform(utf8.decoder).join();
      return parseResponse(body);
    } catch (_) {
      return const [];
    } finally {
      client.close();
    }
  }

  /// Parse a `queryall` response body. The format is a `|`-separated list of
  /// moves, each a comma-separated set of `key:value` fields, the first being
  /// `move:<uci>`. Exposed for testing.
  static List<ChessDbMove> parseResponse(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('unknown') ||
        trimmed.startsWith('nobestmove') ||
        trimmed.startsWith('invalid') ||
        trimmed.startsWith('checkmate') ||
        trimmed.startsWith('stalemate')) {
      return const [];
    }

    final moves = <ChessDbMove>[];
    for (final part in trimmed.split('|')) {
      final fields = <String, String>{};
      for (final kv in part.split(',')) {
        final idx = kv.indexOf(':');
        if (idx <= 0) continue;
        fields[kv.substring(0, idx).trim()] = kv.substring(idx + 1).trim();
      }
      final uci = fields['move'];
      if (uci == null || uci.isEmpty) continue;
      moves.add(
        ChessDbMove(
          uci: uci,
          score: int.tryParse(fields['score'] ?? '') ?? 0,
          rank: int.tryParse(fields['rank'] ?? '') ?? 0,
          note: fields['note'] ?? '',
          winrate: double.tryParse(fields['winrate'] ?? ''),
        ),
      );
    }
    // Higher score is better for the side to move.
    moves.sort((a, b) => b.score.compareTo(a.score));
    return moves;
  }
}
