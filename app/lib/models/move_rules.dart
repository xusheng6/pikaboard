import 'piece.dart';
import 'position.dart';

/// Xiangqi movement rules.
///
/// [isPseudoLegal] answers "may this piece move like that?" and [isLegal] adds
/// the position-level constraints: you may not leave (or place) your own king
/// in check, and the two kings may not face each other down an open file.
class MoveRules {
  const MoveRules._();

  static int _rank(int square) => square ~/ Position.files;
  static int _file(int square) => square % Position.files;
  static int _square(int rank, int file) => rank * Position.files + file;

  /// The palace is files d-f (3-5) on each side's back three ranks.
  static bool _inPalace(PieceColor color, int rank, int file) {
    if (file < 3 || file > 5) return false;
    return color == PieceColor.red ? rank <= 2 : rank >= 7;
  }

  /// Red owns ranks 0-4, black ranks 5-9; the river runs between them.
  static bool _ownHalf(PieceColor color, int rank) =>
      color == PieceColor.red ? rank <= 4 : rank >= 5;

  /// Number of pieces strictly between two squares sharing a rank or file,
  /// or -1 when they share neither.
  static int _countBetween(Position pos, int from, int to) {
    final fr = _rank(from), ff = _file(from);
    final tr = _rank(to), tf = _file(to);
    var count = 0;
    if (fr == tr) {
      final lo = ff < tf ? ff : tf;
      final hi = ff < tf ? tf : ff;
      for (var f = lo + 1; f < hi; f++) {
        if (pos.pieceAt(_square(fr, f)) != null) count++;
      }
      return count;
    }
    if (ff == tf) {
      final lo = fr < tr ? fr : tr;
      final hi = fr < tr ? tr : fr;
      for (var r = lo + 1; r < hi; r++) {
        if (pos.pieceAt(_square(r, ff)) != null) count++;
      }
      return count;
    }
    return -1;
  }

  /// True when the piece on [from] may move to [to] by its own movement rules,
  /// ignoring whether the move exposes its king.
  static bool isPseudoLegal(Position pos, int from, int to) {
    if (from == to) return false;
    if (to < 0 || to >= Position.squareCount) return false;
    final piece = pos.pieceAt(from);
    if (piece == null) return false;
    final target = pos.pieceAt(to);
    if (target != null && target.color == piece.color) return false;

    final fr = _rank(from), ff = _file(from);
    final tr = _rank(to), tf = _file(to);
    final dr = tr - fr, df = tf - ff;
    final adr = dr.abs(), adf = df.abs();

    switch (piece.type) {
      case PieceType.king:
        // One orthogonal step, never leaving the palace.
        return _inPalace(piece.color, tr, tf) && adr + adf == 1;

      case PieceType.advisor:
        // One diagonal step, never leaving the palace.
        return _inPalace(piece.color, tr, tf) && adr == 1 && adf == 1;

      case PieceType.bishop:
        // Two diagonal steps, may not cross the river, and its "eye" (the
        // square it steps over) must be empty.
        if (adr != 2 || adf != 2) return false;
        if (!_ownHalf(piece.color, tr)) return false;
        return pos.pieceAt(_square(fr + dr ~/ 2, ff + df ~/ 2)) == null;

      case PieceType.knight:
        // L-shape, blocked by a piece on the square adjacent along the long
        // leg of the move.
        if (!((adr == 2 && adf == 1) || (adr == 1 && adf == 2))) return false;
        final legRank = fr + (adr == 2 ? dr ~/ 2 : 0);
        final legFile = ff + (adf == 2 ? df ~/ 2 : 0);
        return pos.pieceAt(_square(legRank, legFile)) == null;

      case PieceType.rook:
        if (dr != 0 && df != 0) return false;
        return _countBetween(pos, from, to) == 0;

      case PieceType.cannon:
        // Slides like a rook, but a capture needs exactly one screen piece in
        // between.
        if (dr != 0 && df != 0) return false;
        final between = _countBetween(pos, from, to);
        return target == null ? between == 0 : between == 1;

      case PieceType.pawn:
        final forward = piece.color == PieceColor.red ? 1 : -1;
        if (dr == forward && df == 0) return true;
        // Sideways steps unlock only after crossing the river; never backwards.
        final crossed = _ownHalf(piece.color, fr) == false;
        return crossed && dr == 0 && adf == 1;
    }
  }

  /// The position after playing [from]→[to], with the side to move flipped.
  static Position applyMove(Position pos, int from, int to) {
    final piece = pos.pieceAt(from);
    return pos
        .withPiece(from, null)
        .withPiece(to, piece)
        .withSideToMove(
          pos.sideToMove == PieceColor.red ? PieceColor.black : PieceColor.red,
        );
  }

  static int? _kingSquare(Position pos, PieceColor color) {
    for (var sq = 0; sq < Position.squareCount; sq++) {
      final p = pos.pieceAt(sq);
      if (p != null && p.type == PieceType.king && p.color == color) return sq;
    }
    return null;
  }

  /// True when [color]'s king is attacked, including by the opposing king down
  /// an otherwise empty file (the "flying general" rule).
  ///
  /// A position missing that king cannot be in check — half-built setup
  /// positions are simply not judged.
  static bool isInCheck(Position pos, PieceColor color) {
    final kingSquare = _kingSquare(pos, color);
    if (kingSquare == null) return false;

    final enemy = color == PieceColor.red ? PieceColor.black : PieceColor.red;
    final enemyKing = _kingSquare(pos, enemy);
    if (enemyKing != null &&
        _file(kingSquare) == _file(enemyKing) &&
        _countBetween(pos, kingSquare, enemyKing) == 0) {
      return true;
    }

    for (var sq = 0; sq < Position.squareCount; sq++) {
      final p = pos.pieceAt(sq);
      if (p == null || p.color != enemy) continue;
      if (isPseudoLegal(pos, sq, kingSquare)) return true;
    }
    return false;
  }

  /// True when the side to move may play [from]→[to].
  static bool isLegal(Position pos, int from, int to) {
    final piece = pos.pieceAt(from);
    if (piece == null || piece.color != pos.sideToMove) return false;
    if (!isPseudoLegal(pos, from, to)) return false;
    return !isInCheck(applyMove(pos, from, to), piece.color);
  }

  /// True when [uci] could be played in [pos].
  ///
  /// Used to spot engine output that belongs to a position the app has already
  /// moved on from: a search's last lines can arrive after the next search has
  /// been started, and crediting them to the wrong position flips the score's
  /// sign.
  static bool fitsPosition(Position pos, String uci) {
    if (uci.length < 4) return false;
    final from = Position.uciToSquare(uci.substring(0, 2));
    final to = Position.uciToSquare(uci.substring(2, 4));
    if (from == null || to == null) return false;
    final piece = pos.pieceAt(from);
    if (piece == null || piece.color != pos.sideToMove) return false;
    return isPseudoLegal(pos, from, to);
  }

  /// Every square the piece on [from] may legally move to.
  static List<int> legalDestinations(Position pos, int from) {
    return [
      for (var to = 0; to < Position.squareCount; to++)
        if (isLegal(pos, from, to)) to,
    ];
  }
}
