import 'settings.dart';

enum PieceColor { red, black }

enum PieceType { king, advisor, bishop, knight, rook, cannon, pawn }

class Piece {
  final PieceColor color;
  final PieceType type;

  const Piece(this.color, this.type);

  /// Simplified-Chinese label (kept for convenience / tests).
  String get label => labelFor(DisplayLanguage.simplified);

  /// Display label for this piece in the given [lang].
  String labelFor(DisplayLanguage lang) {
    switch (lang) {
      case DisplayLanguage.english:
        // Color is conveyed by text color, so both sides share a letter.
        return _englishLetter;
      case DisplayLanguage.traditional:
        return color == PieceColor.red ? _redTraditional : _blackTraditional;
      case DisplayLanguage.simplified:
        return color == PieceColor.red ? _redSimplified : _blackSimplified;
    }
  }

  String get _englishLetter {
    switch (type) {
      case PieceType.king:
        return 'K';
      case PieceType.advisor:
        return 'A';
      case PieceType.bishop:
        return 'E'; // Elephant
      case PieceType.knight:
        return 'H'; // Horse
      case PieceType.rook:
        return 'R';
      case PieceType.cannon:
        return 'C';
      case PieceType.pawn:
        return 'P';
    }
  }

  String get _redSimplified {
    switch (type) {
      case PieceType.king:
        return '帅';
      case PieceType.advisor:
        return '仕';
      case PieceType.bishop:
        return '相';
      case PieceType.knight:
        return '马';
      case PieceType.rook:
        return '车';
      case PieceType.cannon:
        return '炮';
      case PieceType.pawn:
        return '兵';
    }
  }

  String get _blackSimplified {
    switch (type) {
      case PieceType.king:
        return '将';
      case PieceType.advisor:
        return '士';
      case PieceType.bishop:
        return '象';
      case PieceType.knight:
        return '马';
      case PieceType.rook:
        return '车';
      case PieceType.cannon:
        return '炮';
      case PieceType.pawn:
        return '卒';
    }
  }

  String get _redTraditional {
    switch (type) {
      case PieceType.king:
        return '帥';
      case PieceType.advisor:
        return '仕';
      case PieceType.bishop:
        return '相';
      case PieceType.knight:
        return '馬';
      case PieceType.rook:
        return '車';
      case PieceType.cannon:
        return '砲';
      case PieceType.pawn:
        return '兵';
    }
  }

  String get _blackTraditional {
    switch (type) {
      case PieceType.king:
        return '將';
      case PieceType.advisor:
        return '士';
      case PieceType.bishop:
        return '象';
      case PieceType.knight:
        return '馬';
      case PieceType.rook:
        return '車';
      case PieceType.cannon:
        return '砲';
      case PieceType.pawn:
        return '卒';
    }
  }

  /// FEN character for this piece.
  String get fenChar {
    String c;
    switch (type) {
      case PieceType.rook:
        c = 'r';
      case PieceType.knight:
        c = 'n';
      case PieceType.bishop:
        c = 'b';
      case PieceType.advisor:
        c = 'a';
      case PieceType.king:
        c = 'k';
      case PieceType.cannon:
        c = 'c';
      case PieceType.pawn:
        c = 'p';
    }
    return color == PieceColor.red ? c.toUpperCase() : c;
  }

  static Piece? fromFenChar(String c) {
    final color = c == c.toUpperCase() ? PieceColor.red : PieceColor.black;
    final lower = c.toLowerCase();
    PieceType? type;
    switch (lower) {
      case 'r':
        type = PieceType.rook;
      case 'n':
        type = PieceType.knight;
      case 'b':
        type = PieceType.bishop;
      case 'a':
        type = PieceType.advisor;
      case 'k':
        type = PieceType.king;
      case 'c':
        type = PieceType.cannon;
      case 'p':
        type = PieceType.pawn;
      default:
        return null;
    }
    return Piece(color, type);
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.color == color && other.type == type;

  @override
  int get hashCode => Object.hash(color, type);
}
