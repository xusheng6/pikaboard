import 'dart:typed_data';

import '../models/game.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// Reader for CCBridge (象棋桥) game files: `.cbr` for a single game and
/// `.cbl` for a library holding many.
///
/// A library is a header, a table of summaries, and then the records
/// themselves — each byte-for-byte the same structure a `.cbr` holds, laid out
/// on 4 KB boundaries from offset 101952.
///
/// Both are fixed-offset structures with UTF-16LE text. Note that CCBridge
/// writes uninitialised memory into the gaps between fields, so anything not
/// documented below is genuinely meaningless: expect stack addresses and stray
/// UI strings in there, and never infer structure from them.
class CcbridgeFormat {
  const CcbridgeFormat._();

  static const String _libraryMagic = 'CCBridgeLibrary';
  static const String _recordMagic = 'CCBridge Record';

  /// The library's index: a fixed offset, then one fixed-size entry per slot.
  static const int _indexOffset = 66624;
  static const int _indexEntrySize = 276;

  /// Number of slots the index was built for, at offset 60.
  static const int _capacityOffset = 60;

  /// Records follow the index, each starting on a 4 KB boundary; a long game
  /// simply takes more than one.
  static const int _recordAlignment = 4096;

  // Field offsets within a record.
  static const int _title = 180;
  static const int _event = 692;
  static const int _round = 756;
  static const int _date = 884;
  static const int _site = 948;
  static const int _redPlayer = 1076;
  static const int _blackPlayer = 1300;
  static const int _annotator = 1652;
  static const int _result = 2076;
  static const int _firstMover = 2112;
  static const int _board = 2120;
  static const int _moves = 2214;

  static bool looksLikeLibrary(Uint8List bytes) =>
      _hasMagic(bytes, 0, _libraryMagic);

  static bool looksLikeRecord(Uint8List bytes) =>
      _hasMagic(bytes, 0, _recordMagic);

  static bool _hasMagic(Uint8List bytes, int offset, String magic) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// Every game in [bytes], which may be a library or a single record.
  static List<Game> parseAll(Uint8List bytes) {
    if (looksLikeRecord(bytes)) return [parseRecord(bytes, 0)];
    if (!looksLikeLibrary(bytes)) {
      throw const FormatException('Not a CCBridge file');
    }

    final libraryTitle = _string(bytes, 64, 512);
    final games = <Game>[];

    // Records begin after the index, whose size follows the slot count the
    // library was built for — so the first record is not at a fixed offset.
    final capacity = ByteData.sublistView(
      bytes,
    ).getUint32(_capacityOffset, Endian.little);
    var first = _indexOffset + capacity * _indexEntrySize;
    if (!_hasMagic(bytes, first, _recordMagic)) {
      // Trust the file over the arithmetic if they disagree.
      final found = _findFirstRecord(bytes);
      if (found == null) {
        throw const FormatException('CCBridge library holds no records');
      }
      first = found;
    }

    // A record can span several slots, so step by the slot size and take the
    // offsets that actually carry a record.
    for (
      var offset = first;
      offset + _moves < bytes.length;
      offset += _recordAlignment
    ) {
      if (!_hasMagic(bytes, offset, _recordMagic)) continue;
      final game = parseRecord(bytes, offset);
      if (libraryTitle.isNotEmpty && game.metadata.event.isEmpty) {
        game.metadata.event = libraryTitle;
      }
      games.add(game);
    }
    if (games.isEmpty) {
      throw const FormatException('CCBridge library holds no records');
    }
    return games;
  }

  /// Scan for the first record, for libraries whose index size does not add up.
  static int? _findFirstRecord(Uint8List bytes) {
    for (var offset = _indexOffset; offset + _moves < bytes.length; offset++) {
      if (_hasMagic(bytes, offset, _recordMagic)) return offset;
    }
    return null;
  }

  /// The single record beginning at [start].
  static Game parseRecord(Uint8List bytes, [int start = 0]) {
    if (!_hasMagic(bytes, start, _recordMagic)) {
      throw const FormatException('Not a CCBridge record');
    }
    if (start + _moves > bytes.length) {
      throw const FormatException('CCBridge record is truncated');
    }

    final position = _readPosition(bytes, start);
    final game = Game.fromPosition(
      position,
      metadata: GameMetadata(
        title: _string(bytes, start + _title, 128),
        event: _string(bytes, start + _event, 64),
        date: _string(bytes, start + _date, 64),
        site: _string(bytes, start + _site, 64),
        red: _string(bytes, start + _redPlayer, 64),
        black: _string(bytes, start + _blackPlayer, 64),
        annotator: _string(bytes, start + _annotator, 64),
        result: switch (bytes[start + _result]) {
          1 => GameResult.redWin,
          2 => GameResult.blackWin,
          3 => GameResult.draw,
          _ => GameResult.unknown,
        },
      ),
    );

    final round = _string(bytes, start + _round, 64);
    if (round.isNotEmpty && game.metadata.event.isNotEmpty) {
      game.metadata.event = '${game.metadata.event} · $round';
    }

    _readMoves(bytes, start + _moves, game.root);
    return game;
  }

  /// The 90 board squares, one byte each.
  ///
  /// Squares run left to right, top row first — Black's back rank — while this
  /// app counts ranks from Red's, so the row is flipped. A piece is a colour
  /// digit and a type: 1x for Red, 2x for Black.
  static Position _readPosition(Uint8List bytes, int start) {
    final squares = List<Piece?>.filled(Position.squareCount, null);
    for (var index = 0; index < 90; index++) {
      final value = bytes[start + _board + index];
      if (value == 0) continue;
      // The codes read as decimal but are packed in hex: 0x11 is Red's rook,
      // 0x27 Black's pawn.
      final colour = value >> 4;
      final type = _pieceTypes[value & 0x0F];
      if (type == null || (colour != 1 && colour != 2)) continue;
      final rank = 9 - (index ~/ 9);
      final file = index % 9;
      squares[rank * Position.files + file] = Piece(
        colour == 1 ? PieceColor.red : PieceColor.black,
        type,
      );
    }
    // 01 means Red moves first, 02 Black.
    final side = bytes[start + _firstMover] == 2
        ? PieceColor.black
        : PieceColor.red;
    return Position(squares: squares, sideToMove: side);
  }

  /// Piece types by the low nibble of a board byte.
  static const Map<int, PieceType> _pieceTypes = {
    1: PieceType.rook,
    2: PieceType.knight,
    3: PieceType.bishop,
    4: PieceType.advisor,
    5: PieceType.king,
    6: PieceType.cannon,
    7: PieceType.pawn,
  };

  /// Walk the move stream, which is four bytes per move plus optional comment.
  ///
  /// The first byte is a set of flags: 4 means a comment follows the record, 2
  /// means this move has an alternative recorded later, and 1 ends the line.
  /// When a line ends, reading continues with the most recent move that
  /// advertised an alternative — so the moves after that point are siblings of
  /// it, not continuations.
  ///
  /// The stream opens with a record for the starting position rather than a
  /// move: its square bytes are zero and only its flags and comment mean
  /// anything.
  static void _readMoves(Uint8List bytes, int offset, GameNode root) {
    var cursor = offset;
    var node = root;
    // Moves that said an alternative follows; the newest is resumed first.
    final pending = <GameNode>[];

    while (cursor + 4 <= bytes.length) {
      final isOpening = cursor == offset;
      final flags = bytes[cursor];
      final from = _square(bytes[cursor + 2]);
      final to = _square(bytes[cursor + 3]);
      cursor += 4;

      String comment = '';
      if (flags & 0x04 != 0) {
        if (cursor + 4 > bytes.length) break;
        final length = ByteData.sublistView(
          bytes,
        ).getUint32(cursor, Endian.little);
        cursor += 4;
        if (length > 0 && cursor + length <= bytes.length) {
          comment = _decodeUtf16(bytes, cursor, length);
        }
        cursor += length;
      }

      if (isOpening) {
        if (comment.isNotEmpty) node.comment = comment;
      } else if (from != null &&
          to != null &&
          node.position.pieceAt(from) != null) {
        node = node.addMove(
          '${Position.squareToUci(from)}${Position.squareToUci(to)}',
        );
        node.comment = comment;
      } else if (comment.isNotEmpty && node.comment.isEmpty) {
        // A comment with no playable move belongs to the position itself.
        node.comment = comment;
      }

      // An alternative to this move appears once the line has run out.
      if (flags & 0x02 != 0) pending.add(node.parent ?? root);

      if (flags & 0x01 != 0) {
        if (pending.isEmpty) return;
        node = pending.removeLast();
      }
    }
  }

  /// A board index as one of this app's squares.
  static int? _square(int index) {
    if (index > 89) return null;
    final rank = 9 - (index ~/ 9);
    final file = index % 9;
    return rank * Position.files + file;
  }

  /// A fixed-width UTF-16LE field, up to its first NUL.
  static String _string(Uint8List bytes, int offset, int size) {
    if (offset + size > bytes.length) return '';
    return _decodeUtf16(bytes, offset, size).trim();
  }

  static String _decodeUtf16(Uint8List bytes, int offset, int size) {
    final units = <int>[];
    for (var i = 0; i + 1 < size; i += 2) {
      final unit = bytes[offset + i] | (bytes[offset + i + 1] << 8);
      if (unit == 0) break;
      units.add(unit);
    }
    if (units.isEmpty) return '';
    try {
      return String.fromCharCodes(units);
    } on ArgumentError {
      return '';
    }
  }
}
