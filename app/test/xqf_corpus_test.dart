import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/formats/xqf.dart';
import 'package:app/models/game.dart';
import 'package:app/models/move_rules.dart';
import 'package:app/models/position.dart';

/// Parses a directory of real .XQF files and checks every recorded move is
/// legal, which validates the layout decoding, key derivation and tree walk
/// all at once. Point XQF_CORPUS at a directory to run it.
void main() {
  final corpus = Platform.environment['XQF_CORPUS'];

  test(
    'parses a corpus of real XQF files',
    () {
      final files = Directory(corpus!)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.xqf'))
          .toList();
      expect(files, isNotEmpty);

      var parsed = 0, failed = 0, moves = 0, illegal = 0, comments = 0;
      var branching = 0;
      final failures = <String>[];

      for (final file in files) {
        Game game;
        try {
          game = XqfFormat.parse(Uint8List.fromList(file.readAsBytesSync()));
          parsed++;
        } catch (e) {
          failed++;
          if (failures.length < 10) failures.add('${file.path}: $e');
          continue;
        }

        var stack = <GameNode>[game.root];
        while (stack.isNotEmpty) {
          final node = stack.removeLast();
          if (node.comment.isNotEmpty) comments++;
          if (node.children.length > 1) branching++;
          for (final child in node.children) {
            moves++;
            final from = Position.uciToSquare(child.move!.substring(0, 2))!;
            final to = Position.uciToSquare(child.move!.substring(2))!;
            if (!MoveRules.isPseudoLegal(node.position, from, to)) {
              illegal++;
              if (failures.length < 10) {
                failures.add(
                  '${file.path}: illegal ${child.move} at ply ${child.ply} '
                  'from ${node.position.toFen()}',
                );
              }
            }
            stack.add(child);
          }
        }
      }

      // ignore: avoid_print
      print(
        'XQF corpus: $parsed parsed, $failed failed, $moves moves '
        '($illegal illegal), $comments comments, $branching branch points\n'
        '${failures.join('\n')}',
      );

      expect(failed, 0, reason: 'every file should parse');
      expect(illegal, 0, reason: 'every recorded move should be legal');
    },
    skip: corpus == null
        ? 'set XQF_CORPUS to a directory of .XQF files'
        : false,
  );
}
