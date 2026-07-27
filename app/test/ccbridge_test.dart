import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/formats/ccbridge.dart';
import 'package:app/formats/game_io.dart';
import 'package:app/models/game.dart';
import 'package:app/models/position.dart';

/// Board bytes for the opening position, in CCBridge's own encoding: one byte
/// per square, top row first, colour in the high nibble and piece in the low.
Uint8List _openingBoard() {
  final board = Uint8List(90);
  void put(int row, int col, int code) => board[row * 9 + col] = code;

  const backRank = [1, 2, 3, 4, 5, 4, 3, 2, 1]; // 车马象士将士象马车
  for (var col = 0; col < 9; col++) {
    put(0, col, 0x20 | backRank[col]); // Black's back rank is row 0
    put(9, col, 0x10 | backRank[col]);
  }
  put(2, 1, 0x26); // cannons
  put(2, 7, 0x26);
  put(7, 1, 0x16);
  put(7, 7, 0x16);
  for (final col in [0, 2, 4, 6, 8]) {
    put(3, col, 0x27); // pawns
    put(6, col, 0x17);
  }
  return board;
}

/// A square as CCBridge indexes it: row 0 is Black's back rank.
int _index(String uci) {
  final square = Position.uciToSquare(uci)!;
  final rank = square ~/ Position.files;
  final file = square % Position.files;
  return (9 - rank) * 9 + file;
}

Uint8List _utf16(String text, int size) {
  final bytes = Uint8List(size);
  for (var i = 0; i < text.length && i * 2 + 1 < size; i++) {
    bytes[i * 2] = text.codeUnitAt(i) & 0xFF;
    bytes[i * 2 + 1] = text.codeUnitAt(i) >> 8;
  }
  return bytes;
}

/// One move of the stream: flags, then the two squares.
List<int> _move(
  String? uci, {
  bool ends = false,
  bool branches = false,
  String comment = '',
}) {
  var flags = 0;
  if (ends) flags |= 0x01;
  if (branches) flags |= 0x02;
  if (comment.isNotEmpty) flags |= 0x04;
  final out = <int>[
    flags,
    0,
    uci == null ? 0 : _index(uci.substring(0, 2)),
    uci == null ? 0 : _index(uci.substring(2)),
  ];
  if (comment.isNotEmpty) {
    final text = _utf16(comment, comment.length * 2);
    final size = text.length;
    out.addAll([
      size & 0xFF,
      (size >> 8) & 0xFF,
      (size >> 16) & 0xFF,
      size >> 24,
    ]);
    out.addAll(text);
  }
  return out;
}

/// A `.cbr`: the record structure on its own.
Uint8List buildRecord({
  String title = '测试棋谱',
  String red = '红方',
  String black = '黑方',
  int result = 1,
  List<int>? moves,
}) {
  final bytes = Uint8List(4096);
  bytes.setRange(0, 15, 'CCBridge Record'.codeUnits);
  bytes[19] = 0x02;
  bytes.setRange(180, 180 + 128, _utf16(title, 128));
  bytes.setRange(1076, 1076 + 64, _utf16(red, 64));
  bytes.setRange(1300, 1300 + 64, _utf16(black, 64));
  bytes[2076] = result;
  bytes[2112] = 1; // Red moves first
  bytes.setRange(2120, 2210, _openingBoard());
  final stream =
      moves ??
      [
        ..._move(null), // the opening record, which carries no move
        ..._move('h2e2'),
        ..._move('h9g7', ends: true),
      ];
  bytes.setRange(2214, 2214 + stream.length, stream);
  return bytes;
}

/// A `.cbl` wrapping [records], with the index sized for [capacity] slots.
Uint8List buildLibrary(
  List<Uint8List> records, {
  int capacity = 128,
  String name = '测试棋库',
}) {
  const indexOffset = 66624;
  const entrySize = 276;
  final first = indexOffset + capacity * entrySize;
  final bytes = Uint8List(first + records.length * 4096);
  bytes.setRange(0, 15, 'CCBridgeLibrary'.codeUnits);
  bytes[60] = capacity & 0xFF;
  bytes[61] = (capacity >> 8) & 0xFF;
  bytes.setRange(64, 64 + 512, _utf16(name, 512));
  for (var i = 0; i < records.length; i++) {
    bytes.setRange(
      first + i * 4096,
      first + i * 4096 + records[i].length,
      records[i],
    );
  }
  return bytes;
}

void main() {
  group('CCBridge record', () {
    test('reads the board, the metadata and the moves', () {
      final game = CcbridgeFormat.parseRecord(buildRecord());

      expect(game.initialPosition.toFen(), Position.startFen);
      expect(game.metadata.title, '测试棋谱');
      expect(game.metadata.red, '红方');
      expect(game.metadata.black, '黑方');
      expect(game.metadata.result, GameResult.redWin);

      final first = game.root.children.single;
      expect(first.move, 'h2e2');
      expect(first.children.single.move, 'h9g7');
    });

    test('the opening record carries the game comment, not a move', () {
      final game = CcbridgeFormat.parseRecord(
        buildRecord(
          moves: [
            ..._move(null, comment: 'opening note'),
            ..._move('h2e2', ends: true),
          ],
        ),
      );
      expect(game.root.comment, 'opening note');
      // It must not become a null move of its own.
      expect(game.root.children.single.move, 'h2e2');
    });

    test('a branching flag makes the moves after the line an alternative', () {
      final game = CcbridgeFormat.parseRecord(
        buildRecord(
          moves: [
            ..._move(null),
            // 1. 炮二平五, which has an alternative recorded later
            ..._move('h2e2', branches: true),
            ..._move('h9g7', ends: true),
            // ... that alternative: 1. 马八进七
            ..._move('h0g2', ends: true),
          ],
        ),
      );

      expect(game.root.children.length, 2);
      expect(game.root.children.first.move, 'h2e2');
      expect(game.root.children[1].move, 'h0g2');
      expect(game.root.children.first.children.single.move, 'h9g7');
    });

    test('comments attach to the move they follow', () {
      final game = CcbridgeFormat.parseRecord(
        buildRecord(
          moves: [
            ..._move(null),
            ..._move('h2e2', comment: '中炮'),
            ..._move('h9g7', ends: true, comment: '屏风马'),
          ],
        ),
      );
      final first = game.root.children.single;
      expect(first.comment, '中炮');
      expect(first.children.single.comment, '屏风马');
    });

    test('rejects files that are not CCBridge', () {
      expect(
        () => CcbridgeFormat.parseRecord(Uint8List(4096)),
        throwsA(isA<FormatException>()),
      );
      expect(CcbridgeFormat.looksLikeRecord(buildRecord()), isTrue);
      expect(CcbridgeFormat.looksLikeLibrary(buildRecord()), isFalse);
    });
  });

  group('CCBridge library', () {
    test('finds every record after an index sized by the slot count', () {
      final library = buildLibrary([
        buildRecord(title: '第一局'),
        buildRecord(title: '第二局'),
        buildRecord(title: '第三局'),
      ]);

      final games = CcbridgeFormat.parseAll(library);
      expect(games.map((g) => g.metadata.title), ['第一局', '第二局', '第三局']);
      // The library's name stands in for an event when the record has none.
      expect(games.first.metadata.event, '测试棋库');
    });

    test('the first record moves with the index size', () {
      // A library built for more slots pushes its records further out; the
      // reader has to compute where they start rather than assume.
      final games = CcbridgeFormat.parseAll(
        buildLibrary([buildRecord(title: '大棋库')], capacity: 140),
      );
      expect(games.single.metadata.title, '大棋库');
    });

    test('opens through GameIO by content, whatever the file is called', () {
      final games = GameIO.decodeAll(
        buildLibrary([buildRecord(title: '甲'), buildRecord(title: '乙')]),
        path: 'mystery.dat',
      );
      expect(games.length, 2);
      expect(GameIO.decode(buildRecord(title: '单局')).metadata.title, '单局');
      expect(GameIO.readableExtensions, containsAll(['cbl', 'cbr']));
    });
  });
}
