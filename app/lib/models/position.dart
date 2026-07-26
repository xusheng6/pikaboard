import 'piece.dart';

/// Xiangqi position representation.
///
/// The board is 9 files (a-i) x 10 ranks (0-9).
/// Square index = rank * 9 + file (0-89).
/// Rank 0 is the bottom (Red's back rank), rank 9 is the top (Black's back rank).
/// FEN lists ranks from 9 (top) to 0 (bottom).
class Position {
  static const int files = 9;
  static const int ranks = 10;
  static const int squareCount = 90;
  static const String startFen =
      'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w';

  /// Pieces on the board, indexed by square (0-89). null means empty.
  final List<Piece?> squares;

  /// Side to move.
  final PieceColor sideToMove;

  Position({required this.squares, required this.sideToMove});

  factory Position.empty() {
    return Position(
      squares: List.filled(squareCount, null),
      sideToMove: PieceColor.red,
    );
  }

  factory Position.startPosition() {
    return Position.fromFen(startFen);
  }

  factory Position.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final boardPart = parts[0];
    final sidePart = parts.length > 1 ? parts[1] : 'w';

    final squares = List<Piece?>.filled(squareCount, null);
    final fenRanks = boardPart.split('/');

    // FEN ranks go from rank 9 (top) to rank 0 (bottom)
    for (int i = 0; i < fenRanks.length && i < ranks; i++) {
      final rank = ranks - 1 - i; // rank 9 first in FEN
      int file = 0;
      for (final c in fenRanks[i].split('')) {
        if (file >= files) break;
        final digit = int.tryParse(c);
        if (digit != null) {
          file += digit;
        } else {
          final piece = Piece.fromFenChar(c);
          if (piece != null) {
            squares[rank * files + file] = piece;
          }
          file++;
        }
      }
    }

    final sideToMove = sidePart == 'b' ? PieceColor.black : PieceColor.red;
    return Position(squares: squares, sideToMove: sideToMove);
  }

  String toFen() {
    final sb = StringBuffer();

    // Ranks from 9 (top) to 0 (bottom)
    for (int rank = ranks - 1; rank >= 0; rank--) {
      int emptyCount = 0;
      for (int file = 0; file < files; file++) {
        final piece = squares[rank * files + file];
        if (piece == null) {
          emptyCount++;
        } else {
          if (emptyCount > 0) {
            sb.write(emptyCount);
            emptyCount = 0;
          }
          sb.write(piece.fenChar);
        }
      }
      if (emptyCount > 0) {
        sb.write(emptyCount);
      }
      if (rank > 0) sb.write('/');
    }

    sb.write(sideToMove == PieceColor.red ? ' w' : ' b');
    return sb.toString();
  }

  /// Get piece at a square index.
  Piece? pieceAt(int square) {
    if (square < 0 || square >= squareCount) return null;
    return squares[square];
  }

  /// Create a copy with a piece placed/removed at a square.
  Position withPiece(int square, Piece? piece) {
    final newSquares = List<Piece?>.of(squares);
    newSquares[square] = piece;
    return Position(squares: newSquares, sideToMove: sideToMove);
  }

  /// Create a copy with toggled side to move.
  Position withSideToMove(PieceColor color) {
    return Position(squares: List<Piece?>.of(squares), sideToMove: color);
  }

  /// Convert square index to UCI notation (e.g., 0 -> "a0", 9 -> "a1").
  static String squareToUci(int square) {
    final file = square % files;
    final rank = square ~/ files;
    return '${String.fromCharCode('a'.codeUnitAt(0) + file)}$rank';
  }

  /// Convert UCI notation to square index.
  static int? uciToSquare(String uci) {
    if (uci.length < 2) return null;
    final file = uci.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(uci.substring(1));
    if (rank == null ||
        file < 0 ||
        file >= files ||
        rank < 0 ||
        rank >= ranks) {
      return null;
    }
    return rank * files + file;
  }
}
