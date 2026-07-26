import 'piece.dart';
import 'position.dart';
import 'settings.dart';

/// Converts UCI moves to Xiangqi move notation (Chinese or plain UCI).
///
/// Red files are numbered 1-9 right-to-left (file i=1, file a=9) using 一二三四五六七八九.
/// Black files are numbered 1-9 right-to-left (file i=1, file a=9) using 1-9.
///
/// Format: [Piece][File] [Action][Destination]
/// - Action: 进 (advance), 退 (retreat), 平 (horizontal)
/// - For horizontal moves, destination is the target file number.
/// - For vertical/diagonal moves, destination is the number of steps
///   (for Rook/Cannon/Pawn/King) or the target file (for Knight/Bishop/Advisor).
///
/// When two identical pieces share the same file, 前/後 replaces the file number.
class MoveNotation {
  static const _redNumerals = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
  static const _blackNumerals = [
    '',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  ];

  /// Convert a UCI move to notation for [lang] given the current position.
  /// English uses the raw UCI coordinates; Chinese uses full move notation.
  /// Returns the UCI move unchanged if conversion fails.
  static String toNotation(
    String uci,
    Position position,
    DisplayLanguage lang,
  ) {
    if (lang == DisplayLanguage.english) return uci;
    if (uci.length < 4) return uci;
    final back = lang == DisplayLanguage.traditional ? '後' : '后';
    final advance = lang == DisplayLanguage.traditional ? '進' : '进';

    final from = Position.uciToSquare(uci.substring(0, 2));
    final to = Position.uciToSquare(uci.substring(2, 4));
    if (from == null || to == null) return uci;

    final piece = position.pieceAt(from);
    if (piece == null) return uci;

    final fromFile = from % Position.files;
    final fromRank = from ~/ Position.files;
    final toFile = to % Position.files;
    final toRank = to ~/ Position.files;

    final isRed = piece.color == PieceColor.red;
    final numerals = isRed ? _redNumerals : _blackNumerals;

    // Red files: right-to-left from Red's perspective (i=1, a=9)
    // Black files: right-to-left from Black's perspective (a=1, i=9)
    int fileToNum(int file) => isRed ? (9 - file) : (file + 1);

    // Piece character
    String pieceName = piece.labelFor(lang);

    // Check for duplicate pieces of same type and color on the same file
    String fileOrPosition = numerals[fileToNum(fromFile)];
    if (_hasDuplicateOnSameFile(position, piece, fromFile)) {
      // Determine 前(front) or 後(back)
      // "Front" means closer to the opponent. For Red, higher rank = front.
      // For Black, lower rank = front.
      final others = _findSameTypeOnFile(position, piece, fromFile);
      if (others.length == 2) {
        // Simple case: 2 pieces, use 前/後
        final otherRank =
            others.firstWhere((sq) => sq != from) ~/ Position.files;
        final isFront = isRed ? (fromRank > otherRank) : (fromRank < otherRank);
        fileOrPosition = isFront ? '前' : back;
      } else {
        // 3+ identical pieces on the same file (e.g., 3 pawns)
        // Sort by rank: for Red, highest rank first (front); for Black, lowest rank first
        others.sort((a, b) {
          final ra = a ~/ Position.files;
          final rb = b ~/ Position.files;
          return isRed ? rb.compareTo(ra) : ra.compareTo(rb);
        });
        final index = others.indexOf(from);
        if (others.length == 3) {
          fileOrPosition = ['前', '中', back][index];
        } else {
          // For 4-5 pawns, use ordinal numbers
          fileOrPosition = numerals[index + 1];
          // Replace piece name with file indicator
          pieceName = piece.labelFor(lang);
        }
      }
    }

    // Action and destination
    String action;
    String destination;

    if (fromRank == toRank) {
      // Horizontal move
      action = '平';
      destination = numerals[fileToNum(toFile)];
    } else {
      // Vertical or diagonal move
      final isAdvance = isRed ? (toRank > fromRank) : (toRank < fromRank);
      action = isAdvance ? advance : '退';

      // For pieces that move diagonally (Knight, Bishop, Advisor),
      // destination is the target file number.
      // For pieces that move straight (Rook, Cannon, King, Pawn),
      // destination is the number of steps.
      if (piece.type == PieceType.knight ||
          piece.type == PieceType.bishop ||
          piece.type == PieceType.advisor) {
        destination = numerals[fileToNum(toFile)];
      } else {
        destination = numerals[(toRank - fromRank).abs()];
      }
    }

    return '$pieceName$fileOrPosition$action$destination';
  }

  /// Convert a PV string (space-separated UCI moves) to notation for [lang].
  /// Applies moves sequentially to track position changes.
  static String pvToNotation(
    String pvText,
    Position startPosition,
    DisplayLanguage lang,
  ) {
    if (pvText.trim().isEmpty) return '';
    if (lang == DisplayLanguage.english) return pvText.trim();

    final moves = pvText.trim().split(RegExp(r'\s+'));
    final result = <String>[];
    var pos = startPosition;

    for (final uci in moves) {
      result.add(toNotation(uci, pos, lang));
      // Apply the move to track position for subsequent moves
      pos = applyUciMove(pos, uci);
    }

    return result.join(' ');
  }

  static bool _hasDuplicateOnSameFile(
    Position position,
    Piece piece,
    int file,
  ) {
    return _findSameTypeOnFile(position, piece, file).length > 1;
  }

  static List<int> _findSameTypeOnFile(
    Position position,
    Piece piece,
    int file,
  ) {
    final result = <int>[];
    for (int rank = 0; rank < Position.ranks; rank++) {
      final sq = rank * Position.files + file;
      final p = position.pieceAt(sq);
      if (p != null && p.color == piece.color && p.type == piece.type) {
        result.add(sq);
      }
    }
    return result;
  }

  /// Apply a UCI move to a position, returning the new position.
  static Position applyUciMove(Position pos, String uci) {
    if (uci.length < 4) return pos;
    final from = Position.uciToSquare(uci.substring(0, 2));
    final to = Position.uciToSquare(uci.substring(2, 4));
    if (from == null || to == null) return pos;

    final piece = pos.pieceAt(from);
    if (piece == null) return pos;

    final newPos = pos.withPiece(from, null).withPiece(to, piece);
    // Toggle side to move
    final nextSide = pos.sideToMove == PieceColor.red
        ? PieceColor.black
        : PieceColor.red;
    return newPos.withSideToMove(nextSide);
  }
}
