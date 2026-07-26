import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import '../models/game.dart';
import '../models/piece.dart';
import '../models/position.dart';

/// Reader for XQStudio's `.XQF` game files.
///
/// The format is a 1024-byte plaintext header followed by a move tree whose
/// bytes are obfuscated with a rolling 32-byte key derived from the header.
/// Layout, key derivation and tree shape all follow XQStudio's own
/// `XQFileRW.pas`; text is GB18030.
class XqfFormat {
  const XqfFormat._();

  static const int _headerSize = 1024;

  /// The literal XQStudio derives its stream key from.
  static const String _keyText = '[(C) Copyright Mr. Dong Shiwei.]';

  /// Piece for each of the 32 layout slots: red first, then black, each as
  /// 车马相士帅士相马车炮炮兵兵兵兵兵.
  static const List<PieceType> _slotTypes = [
    PieceType.rook,
    PieceType.knight,
    PieceType.bishop,
    PieceType.advisor,
    PieceType.king,
    PieceType.advisor,
    PieceType.bishop,
    PieceType.knight,
    PieceType.rook,
    PieceType.cannon,
    PieceType.cannon,
    PieceType.pawn,
    PieceType.pawn,
    PieceType.pawn,
    PieceType.pawn,
    PieceType.pawn,
  ];

  /// True when [bytes] look like an XQF file.
  static bool looksLikeXqf(Uint8List bytes) =>
      bytes.length >= _headerSize && bytes[0] == 0x58 && bytes[1] == 0x51;

  /// Parse an XQF file into a game.
  ///
  /// Throws [FormatException] when the file is not XQF, fails its key
  /// checksum, or is truncated.
  static Game parse(Uint8List bytes) {
    if (bytes.length < _headerSize) {
      throw const FormatException('XQF file is shorter than its header');
    }
    if (bytes[0] != 0x58 || bytes[1] != 0x51) {
      throw const FormatException('Not an XQF file (missing "XQ" signature)');
    }

    final version = bytes[2];
    final keyMask = bytes[3];
    final keyOr = bytes.sublist(8, 12);
    final keysSum = bytes[12];
    final keyXyRaw = bytes[13];
    final keyXyfRaw = bytes[14];
    final keyXytRaw = bytes[15];
    if ((keysSum + keyXyRaw + keyXyfRaw + keyXytRaw) & 0xFF != 0) {
      throw const FormatException('XQF key checksum is wrong');
    }

    // Versions up to 1.0 are unencrypted.
    var keyXy = 0, keyXyf = 0, keyXyt = 0, keyRemarkSize = 0;
    if (version > 10) {
      int scramble(int k) => (((((k * k) * 3 + 9) * 3 + 8) * 2 + 1) * 3 + 8);
      keyXy = (scramble(keyXyRaw) * keyXyRaw) & 0xFF;
      keyXyf = (scramble(keyXyfRaw) * keyXy) & 0xFF;
      keyXyt = (scramble(keyXytRaw) * keyXyf) & 0xFF;
      keyRemarkSize = ((keysSum * 256 + keyXyRaw) % 32000) + 767;
    }

    final position = _readPosition(bytes, version, keyXy);
    final metadata = _readMetadata(bytes);
    final game = Game.fromPosition(position, metadata: metadata);

    if (bytes.length > _headerSize) {
      final body = _decryptBody(
        bytes,
        keysSum,
        keyXyRaw,
        keyXyfRaw,
        keyXytRaw,
        keyMask,
        keyOr,
      );
      final reader = _NodeReader(
        body: body,
        version: version,
        keyXyf: keyXyf,
        keyXyt: keyXyt,
        keyRemarkSize: keyRemarkSize,
      );
      reader.readRoot(game.root);
    }

    return game;
  }

  /// The initial layout: 32 slots holding a board square, or 0xFF when the
  /// piece is off the board. From version 1.2 the array itself is rotated.
  static Position _readPosition(Uint8List bytes, int version, int keyXy) {
    final slots = List<int>.filled(32, 0xFF);
    for (var i = 0; i < 32; i++) {
      // XQStudio indexes from 1, hence the extra step in the rotation.
      final slot = version >= 12 ? (i + 1 + keyXy) % 32 : i;
      slots[slot] = bytes[16 + i];
    }

    var squares = List<Piece?>.filled(Position.squareCount, null);
    for (var i = 0; i < 32; i++) {
      final value = (slots[i] - keyXy) & 0xFF;
      if (value > 89) continue; // captured or unused
      // XY packs file into the tens digit and rank into the units, with rank 0
      // on Red's back rank — the same orientation this app uses.
      final file = value ~/ 10;
      final rank = value % 10;
      if (file > 8 || rank > 9) continue;
      final piece = Piece(
        i < 16 ? PieceColor.red : PieceColor.black,
        _slotTypes[i % 16],
      );
      squares[rank * Position.files + file] = piece;
    }

    // WhoPlay: 0 means Red starts.
    final sideToMove = bytes[50] == 1 ? PieceColor.black : PieceColor.red;
    return Position(squares: squares, sideToMove: sideToMove);
  }

  static GameMetadata _readMetadata(Uint8List bytes) {
    return GameMetadata(
      title: _pascalString(bytes, 80, 63),
      event: _pascalString(bytes, 208, 63),
      date: _pascalString(bytes, 272, 15),
      site: _pascalString(bytes, 288, 15),
      red: _pascalString(bytes, 304, 15),
      black: _pascalString(bytes, 320, 15),
      annotator: _pascalString(bytes, 464, 15),
      result: switch (bytes[51]) {
        1 => GameResult.redWin,
        2 => GameResult.blackWin,
        3 => GameResult.draw,
        _ => GameResult.unknown,
      },
    );
  }

  /// A Delphi ShortString: one length byte followed by GB18030 text.
  static String _pascalString(Uint8List bytes, int offset, int capacity) {
    final length = bytes[offset].clamp(0, capacity);
    if (length == 0) return '';
    final raw = bytes.sublist(offset + 1, offset + 1 + length);
    try {
      return gbk.decode(raw).trim();
    } on FormatException {
      return '';
    }
  }

  /// Undo the rolling-key obfuscation over everything after the header.
  static Uint8List _decryptBody(
    Uint8List bytes,
    int keysSum,
    int keyXy,
    int keyXyf,
    int keyXyt,
    int keyMask,
    List<int> keyOr,
  ) {
    final keyBytes = [
      (keysSum & keyMask) | keyOr[0],
      (keyXy & keyMask) | keyOr[1],
      (keyXyf & keyMask) | keyOr[2],
      (keyXyt & keyMask) | keyOr[3],
    ];
    final streamKey = List<int>.generate(
      32,
      (i) => _keyText.codeUnitAt(i) & keyBytes[i % 4],
    );

    final body = Uint8List(bytes.length - _headerSize);
    for (var i = 0; i < body.length; i++) {
      // The key runs against the absolute file position.
      final key = streamKey[(_headerSize + i) % 32];
      body[i] = (bytes[_headerSize + i] - key) & 0xFF;
    }
    return body;
  }
}

/// Walks the move tree stored after the header.
///
/// Each record is a move plus flags: bit 0x80 marks a continuation, 0x40 an
/// alternative to the move itself — left-child / right-sibling, which maps
/// onto [GameNode.children] with the first child as the main line.
class _NodeReader {
  final Uint8List body;
  final int version;
  final int keyXyf;
  final int keyXyt;
  final int keyRemarkSize;

  int _offset = 0;

  /// Moves that could not be replayed, so callers can tell a partial read.
  int skipped = 0;

  _NodeReader({
    required this.body,
    required this.version,
    required this.keyXyf,
    required this.keyXyt,
    required this.keyRemarkSize,
  });

  /// The first record describes the starting position itself.
  void readRoot(GameNode root) {
    final record = _readRecord();
    if (record == null) return;
    root.comment = record.remark;
    if (record.hasChild) _readInto(root);
    // A sibling of the root can only mean another first move.
    if (record.hasSibling) _readInto(root);
  }

  /// Read one record and hang it under [parent].
  void _readInto(GameNode parent) {
    final record = _readRecord();
    if (record == null) return;

    final from = _square(record.from);
    final to = _square(record.to);
    final movable =
        from != null && to != null && parent.position.pieceAt(from) != null;

    // An unplayable move ends this line rather than corrupting the tree.
    final node = movable
        ? parent.addMove(
            '${Position.squareToUci(from)}${Position.squareToUci(to)}',
          )
        : null;
    if (node == null) {
      skipped++;
    } else {
      node.comment = record.remark;
    }

    if (record.hasChild && node != null) _readInto(node);
    if (record.hasSibling) _readInto(parent);
  }

  static int? _square(int xy) {
    final file = xy ~/ 10;
    final rank = xy % 10;
    if (file > 8 || rank > 9) return null;
    return rank * Position.files + file;
  }

  _NodeRecord? _readRecord() {
    if (_offset + 4 > body.length) return null;
    var from = body[_offset];
    var to = body[_offset + 1];
    var tag = body[_offset + 2];
    _offset += 4;

    var remarkSize = 0;
    if (version <= 0x0A) {
      // Older files pack the flags differently and always store a size.
      var flags = 0;
      if (tag & 0xF0 != 0) flags |= 0x80;
      if (tag & 0x0F != 0) flags |= 0x40;
      tag = flags;
      remarkSize = _readUint32();
    } else {
      tag &= 0xE0;
      if (tag & 0x20 != 0) remarkSize = _readUint32();
    }

    from = (from - 0x18 - keyXyf) & 0xFF;
    to = (to - 0x20 - keyXyt) & 0xFF;

    var remark = '';
    if (remarkSize > 0) {
      final size = (remarkSize - keyRemarkSize) & 0xFFFFFFFF;
      if (size > 0 && _offset + size <= body.length) {
        try {
          remark = gbk.decode(body.sublist(_offset, _offset + size)).trim();
        } on FormatException {
          remark = '';
        }
        _offset += size;
      }
    }

    return _NodeRecord(
      from: from,
      to: to,
      hasChild: tag & 0x80 != 0,
      hasSibling: tag & 0x40 != 0,
      remark: remark,
    );
  }

  int _readUint32() {
    if (_offset + 4 > body.length) return 0;
    final value =
        body[_offset] |
        (body[_offset + 1] << 8) |
        (body[_offset + 2] << 16) |
        (body[_offset + 3] << 24);
    _offset += 4;
    return value;
  }
}

class _NodeRecord {
  final int from;
  final int to;
  final bool hasChild;
  final bool hasSibling;
  final String remark;

  const _NodeRecord({
    required this.from,
    required this.to,
    required this.hasChild,
    required this.hasSibling,
    required this.remark,
  });
}
