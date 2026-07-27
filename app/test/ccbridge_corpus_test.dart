import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/formats/ccbridge.dart';
import 'package:app/models/game.dart';
import 'package:app/models/move_rules.dart';
import 'package:app/models/position.dart';

/// Parses real CCBridge libraries and checks every recorded move is legal,
/// which validates the board decoding and the move-stream walk together.
void main() {
  final corpus = Platform.environment['CCB_CORPUS'];

  test(
    'parses a corpus of real CCBridge files',
    () {
      final files = Directory(corpus!)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => RegExp(r'\.cb[lr]$', caseSensitive: false).hasMatch(f.path),
          )
          .toList();
      expect(files, isNotEmpty);

      var libraries = 0, games = 0, failed = 0, moves = 0, illegal = 0;
      var comments = 0, branches = 0;
      final notes = <String>[];

      for (final file in files) {
        List<Game> parsed;
        try {
          parsed = CcbridgeFormat.parseAll(
            Uint8List.fromList(file.readAsBytesSync()),
          );
          libraries++;
        } catch (e) {
          failed++;
          if (notes.length < 8) notes.add('${file.path}: $e');
          continue;
        }

        for (final game in parsed) {
          games++;
          final stack = <GameNode>[game.root];
          while (stack.isNotEmpty) {
            final node = stack.removeLast();
            if (node.comment.isNotEmpty) comments++;
            if (node.children.length > 1) branches++;
            for (final child in node.children) {
              moves++;
              final from = Position.uciToSquare(child.move!.substring(0, 2))!;
              final to = Position.uciToSquare(child.move!.substring(2))!;
              if (!MoveRules.isPseudoLegal(node.position, from, to)) {
                illegal++;
                if (notes.length < 8) {
                  notes.add(
                    '${file.path.split('/').last} "${game.metadata.title}": '
                    'illegal ${child.move} at ply ${child.ply} from ${node.position.toFen()}',
                  );
                }
              }
              stack.add(child);
            }
          }
        }
      }

      // ignore: avoid_print
      print(
        'CCBridge: $libraries files, $games games, $failed failed, '
        '$moves moves ($illegal illegal), $comments comments, $branches branches\n'
        '${notes.join('\n')}',
      );
      expect(failed, 0);
      expect(illegal, 0);
    },
    skip: corpus == null ? 'set CCB_CORPUS' : false,
  );
}
