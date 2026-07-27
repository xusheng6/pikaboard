import 'move_notation.dart';
import 'position.dart';

/// A line taken from the engine and walked through without committing it.
///
/// The moves are a snapshot: an engine's principal variation is rewritten as
/// the search deepens, and a line that shifted underfoot while being read
/// would be worse than useless.
class ExploredLine {
  /// Where the line begins — the position the engine was searching.
  final Position start;

  /// The line's moves in UCI, as they read when it was picked up.
  final List<String> moves;

  /// How many of those moves have been played, 0 being the start position.
  final int index;

  const ExploredLine({
    required this.start,
    required this.moves,
    this.index = 0,
  });

  /// The position after [index] moves.
  Position get position {
    var position = start;
    for (var i = 0; i < index && i < moves.length; i++) {
      position = MoveNotation.applyUciMove(position, moves[i]);
    }
    return position;
  }

  /// The move that led here, or null at the start of the line.
  String? get lastMove =>
      index > 0 && index <= moves.length ? moves[index - 1] : null;

  /// The move to play next, or null at the end of the line.
  String? get nextMove => index < moves.length ? moves[index] : null;

  /// The move after that, drawn as the expected reply.
  String? get replyMove => index + 1 < moves.length ? moves[index + 1] : null;

  bool get canStepForward => index < moves.length;
  bool get canStepBack => index > 0;

  ExploredLine at(int newIndex) => ExploredLine(
    start: start,
    moves: moves,
    index: newIndex.clamp(0, moves.length),
  );

  ExploredLine get forward => at(index + 1);
  ExploredLine get back => at(index - 1);
}
