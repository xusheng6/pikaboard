import 'package:flutter/material.dart';

import '../models/move_notation.dart';
import '../models/position.dart';
import '../models/settings.dart';

/// Shows the moves played so far (derived from the position history) as a
/// tappable, wrapping list. Tapping a move jumps to that position.
class MoveList extends StatelessWidget {
  /// Position history; [history].first is the initial position and each
  /// subsequent entry is the position after one ply.
  final List<Position> history;

  /// Index of the currently displayed position within [history].
  final int currentIndex;
  final DisplayLanguage language;

  /// Called with the history index to navigate to.
  final ValueChanged<int> onSelect;

  const MoveList({
    super.key,
    required this.history,
    required this.currentIndex,
    required this.onSelect,
    this.language = DisplayLanguage.simplified,
  });

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No moves yet.', style: TextStyle(color: Colors.grey)),
      );
    }

    final theme = Theme.of(context);
    final chips = <Widget>[];
    for (int i = 1; i < history.length; i++) {
      final before = history[i - 1];
      final uci = _moveUci(before, history[i]);
      final notation = uci == null
          ? '??'
          : MoveNotation.toNotation(uci, before, language);

      // Number each full move (a red ply + the following black ply).
      final isPairStart = (i - 1) % 2 == 0;
      final moveNumber = (i - 1) ~/ 2 + 1;
      final label = isPairStart ? '$moveNumber. $notation' : notation;
      final selected = i == currentIndex;

      chips.add(
        InkWell(
          onTap: () => onSelect(i),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? theme.colorScheme.onPrimaryContainer : null,
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(spacing: 4, runSpacing: 2, children: chips),
    );
  }

  /// Reconstruct the UCI move between two consecutive positions by finding the
  /// square a piece left and the square it arrived at.
  static String? _moveUci(Position before, Position after) {
    int? from;
    int? to;
    for (int sq = 0; sq < Position.squareCount; sq++) {
      final b = before.pieceAt(sq);
      final a = after.pieceAt(sq);
      if (b == a) continue;
      if (b != null && a == null) {
        from = sq; // piece left this square
      } else if (a != null) {
        to = sq; // piece arrived (move or capture)
      }
    }
    if (from == null || to == null) return null;
    return '${Position.squareToUci(from)}${Position.squareToUci(to)}';
  }
}
