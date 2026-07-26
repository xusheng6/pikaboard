import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/formats/game_export.dart';
import 'package:app/formats/xqg.dart';
import 'package:app/models/game.dart';
import 'package:app/models/position.dart';

void main() {
  group('Annotator .xqg import', () {
    // Rows run top-down here: "7774" is h2e2 and "0726" is h9g7. The
    // variation replaces the first move with h0g2, b9c7.
    final sample = {
      'format': 'xiangqi_annotator_v5',
      'initial_fen': Position.startFen,
      'moves': ['7774', '0726'],
      'comments': {
        '-1': 'Opening position',
        '0': 'Central cannon. Instead {variant1} is quieter.',
      },
      'variations': {
        '0': [
          {
            'start_fen': Position.startFen,
            'moves': ['9776', '0127'],
          },
        ],
      },
    };

    test('rebuilds the main line from row/column moves', () {
      final game = XqgFormat.parse(sample);
      expect(game.initialPosition.toFen(), Position.startFen);

      final first = game.root.children.first;
      expect(first.move, 'h2e2');
      expect(first.children.first.move, 'h9g7');
      expect(game.root.comment, 'Opening position');
    });

    test('variations become branches and their references are spelled out', () {
      final game = XqgFormat.parse(sample);

      // The alternative hangs off the same position as the move it replaces.
      expect(game.root.children.length, 2);
      final alternative = game.root.children[1];
      expect(alternative.move, 'h0g2');

      // The {variant1} reference is replaced by the moves it stood for.
      final comment = game.root.children.first.comment;
      expect(comment, contains('【变着1:'));
      expect(comment, isNot(contains('{variant1}')));
      expect(comment, contains('马'));
    });

    test('detects the format and survives a truncated move list', () {
      expect(XqgFormat.looksLikeXqg(sample), isTrue);
      expect(XqgFormat.looksLikeXqg({'format': 'pikaboard_game_v1'}), isFalse);

      final broken = Map<String, dynamic>.from(sample)
        ..['moves'] = ['7774', 'zzzz', '0726'];
      final game = XqgFormat.parse(broken);
      // Everything before the bad move is kept.
      expect(game.root.children.first.children, isEmpty);

      expect(
        () => XqgFormat.parse({'format': 'xiangqi_annotator_v5'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads the real annotator file when one is present', () {
      const path =
          '/Users/xusheng/xiangqi_endgame_mine/xiangqi_annotator/games';
      final directory = Directory(path);
      if (!directory.existsSync()) {
        markTestSkipped('annotator games directory not present');
        return;
      }
      final files = directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xqg'))
          .toList();
      if (files.isEmpty) {
        markTestSkipped('no .xqg files to read');
        return;
      }

      for (final file in files) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final game = XqgFormat.parse(json);
        expect(game.mainlineLength, greaterThan(0));
        final notes = <String>[];
        var node = game.root;
        while (true) {
          if (node.comment.isNotEmpty) notes.add(node.comment);
          if (node.children.isEmpty) break;
          node = node.children.first;
        }
        expect(notes, isNotEmpty, reason: '${file.path} should carry notes');
        expect(
          notes.every((n) => !n.contains('{variant')),
          isTrue,
          reason: 'variation references should be expanded',
        );
      }
    });
  });

  group('Export', () {
    Game annotatedGame() {
      final game = Game.fromMoves(Position.startPosition(), ['h2e2', 'h9g7']);
      game.root.comment = 'Initial thoughts';
      game.root.children.first.comment = 'Central cannon.$kBoardMarker Strong.';
      game.root.addMove('b0c2');
      game.metadata
        ..title = '测试对局'
        ..red = '红方'
        ..black = '黑方'
        ..result = GameResult.redWin;
      return game;
    }

    test('text export keeps the annotator layout', () {
      final text = GameExport.toText(annotatedGame());
      expect(text, contains('测试对局'));
      expect(text, contains('红方: 红方    黑方: 黑方'));
      expect(text, contains('初始局面 FEN: ${Position.startFen}'));
      expect(text, contains('【初始局面注释】'));
      // Board markers degrade to the placeholder the annotator used.
      expect(text, contains('[screenshot]'));
      expect(text, isNot(contains(kBoardMarker)));
      expect(text, contains('变着:'));
      expect(text, contains('结果: 红胜'));
    });

    test('html export draws diagrams where the markers are', () {
      final html = GameExport.toHtml(annotatedGame());
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<title>测试对局</title>'));
      // One diagram for the starting position, one for the [board] marker.
      expect('<svg'.allMatches(html).length, 2);
      expect(html, contains('楚河'));
      // Pieces are drawn, and the notes come through.
      expect(html, contains('>车<'));
      expect(html, contains('Central cannon.'));
      expect(html, contains('变着:'));
    });

    test('html escapes text that would break the markup', () {
      final game = Game.fromPosition(Position.startPosition());
      game.metadata.title = '<script>&"';
      game.root.comment = 'a < b & c';
      final html = GameExport.toHtml(game);
      expect(html, contains('&lt;script&gt;&amp;&quot;'));
      expect(html, contains('a &lt; b &amp; c'));
      expect(html, isNot(contains('<script>')));
    });
  });
}
