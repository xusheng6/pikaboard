import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/formats/game_io.dart';
import 'package:app/formats/xqf.dart';
import 'package:app/models/game.dart';
import 'package:app/models/position.dart';

/// A minimal but genuine XQF file: version 18, zero keys (which still passes
/// the checksum), the opening position, and a two-move main line with an
/// alternative first move — enough to exercise layout, flags and comments.
Uint8List _buildXqf({
  String title = '测试',
  String red = '红方',
  String black = '黑方',
  int result = 3,
}) {
  final bytes = Uint8List(1024);
  bytes[0] = 0x58; // 'X'
  bytes[1] = 0x51; // 'Q'
  bytes[2] = 18; // version
  bytes[3] = 0xFF; // key mask
  // Keys are all zero, so the checksum is already satisfied and the body is
  // stored plainly.

  // Standard opening layout, in XQF's 32 slots: file * 10 + rank.
  const layout = [
    0, 10, 20, 30, 40, 50, 60, 70, 80, // red back rank
    12, 72, // red cannons
    3, 23, 43, 63, 83, // red pawns
    9, 19, 29, 39, 49, 59, 69, 79, 89, // black back rank
    17, 77, // black cannons
    6, 26, 46, 66, 86, // black pawns
  ];
  for (var i = 0; i < 32; i++) {
    // Version >= 12 rotates the slots by KeyXY, which is zero here, leaving
    // the one-based shift XQStudio applies.
    bytes[16 + ((i - 1) % 32 + 32) % 32] = layout[i];
  }

  bytes[50] = 0; // red to move
  bytes[51] = result;

  void writeString(int offset, String value, int capacity) {
    // XQF stores GB18030, which is what the reader has to cope with.
    final encoded = gbk.encode(value);
    if (encoded.length > capacity) return;
    bytes[offset] = encoded.length;
    bytes.setRange(offset + 1, offset + 1 + encoded.length, encoded);
  }

  writeString(80, title, 63);
  writeString(304, red, 15);
  writeString(320, black, 15);

  // Body: root, then 1. h2e2 with 1. b0c2 as an alternative, then 1... h9g7.
  final body = <int>[];
  void node({
    required int from,
    required int to,
    bool child = false,
    bool sibling = false,
    String remark = '',
  }) {
    final remarkBytes = gbk.encode(remark);
    var tag = 0;
    if (child) tag |= 0x80;
    if (sibling) tag |= 0x40;
    if (remarkBytes.isNotEmpty) tag |= 0x20;
    body.addAll([(from + 0x18) & 0xFF, (to + 0x20) & 0xFF, tag, 0]);
    if (remarkBytes.isNotEmpty) {
      // Stored sizes carry the remark key, which is 767 even when the other
      // keys are zero: ((KeysSum * 256 + KeyXY) % 32000) + 767.
      final size = remarkBytes.length + 767;
      body.addAll([
        size & 0xFF,
        (size >> 8) & 0xFF,
        (size >> 16) & 0xFF,
        (size >> 24) & 0xFF,
      ]);
      body.addAll(remarkBytes);
    }
  }

  node(from: 0, to: 0, child: true, remark: 'start note'); // root
  node(from: 72, to: 42, child: true, sibling: true, remark: 'central cannon');
  node(from: 79, to: 67); // 1... h9g7 continues the main line
  node(from: 10, to: 22); // alternative first move: b0c2

  final file = Uint8List(1024 + body.length);
  file.setRange(0, 1024, bytes);
  file.setRange(1024, file.length, body);
  return file;
}

void main() {
  group('XQF', () {
    test('reads the layout, metadata and move tree', () {
      final game = XqfFormat.parse(_buildXqf());

      expect(game.initialPosition.toFen(), Position.startFen);
      expect(game.metadata.title, '测试');
      expect(game.metadata.red, '红方');
      expect(game.metadata.black, '黑方');
      expect(game.metadata.result, GameResult.draw);

      // The root remark becomes the note on the starting position.
      expect(game.root.comment, 'start note');

      // Main line first, alternative second.
      expect(game.root.children.length, 2);
      final mainline = game.root.children.first;
      expect(mainline.move, 'h2e2');
      expect(mainline.comment, 'central cannon');
      expect(mainline.children.single.move, 'h9g7');
      expect(game.root.children[1].move, 'b0c2');
      expect(game.root.children[1].children, isEmpty);
    });

    test('rejects files that are not XQF or fail their checksum', () {
      expect(
        () => XqfFormat.parse(Uint8List(1024)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => XqfFormat.parse(Uint8List.fromList([0x58, 0x51])),
        throwsA(isA<FormatException>()),
      );

      final badKeys = _buildXqf();
      badKeys[13] = 5; // breaks KeysSum + KeyXY + KeyXYf + KeyXYt == 0
      expect(() => XqfFormat.parse(badKeys), throwsA(isA<FormatException>()));

      expect(XqfFormat.looksLikeXqf(_buildXqf()), isTrue);
      expect(XqfFormat.looksLikeXqf(Uint8List(1024)), isFalse);
    });
  });

  group('GameIO', () {
    test('picks the format by content, not by name', () {
      final xqf = GameIO.decode(_buildXqf(), path: 'oddly-named.dat');
      expect(xqf.metadata.title, '测试');

      final native = Game.fromMoves(Position.startPosition(), ['b0c2']);
      native.root.children.first.comment = 'note';
      final encoded = Uint8List.fromList(
        utf8.encode(jsonEncode(native.toJson())),
      );
      final decoded = GameIO.decode(encoded, path: 'game.pbg');
      expect(decoded.root.children.first.comment, 'note');

      expect(
        () => GameIO.decode(Uint8List.fromList(utf8.encode('hello'))),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => GameIO.decode(Uint8List.fromList(utf8.encode('{"format":"x"}'))),
        throwsA(isA<FormatException>()),
      );
    });

    test('suggests a filename from what the game is about', () {
      final game = Game.fromPosition(Position.startPosition());
      expect(GameIO.suggestedFileName(game), 'game.pbg');

      game.metadata.red = 'A/B';
      game.metadata.black = 'C';
      expect(GameIO.suggestedFileName(game), 'A_B vs C.pbg');

      game.metadata.title = '中炮对屏风马';
      expect(GameIO.suggestedFileName(game), '中炮对屏风马.pbg');
    });
  });
}
