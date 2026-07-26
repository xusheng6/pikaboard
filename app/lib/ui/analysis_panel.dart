import 'package:flutter/material.dart';
import '../engine/search_info.dart';
import '../models/move_notation.dart';
import '../models/position.dart';

// Shared column widths so the header and every row line up.
const double _kDepthWidth = 34;
const double _kScoreWidth = 64;
const double _kTimeWidth = 54;
const double _kColumnGap = 8;

/// One row in the analysis table: a search line plus the position its moves
/// apply to. [stale] lines were computed for a previous board position and are
/// shown greyed out.
class AnalysisLine {
  final SearchInfo info;
  final Position position;
  final bool stale;

  const AnalysisLine({
    required this.info,
    required this.position,
    this.stale = false,
  });
}

class AnalysisPanel extends StatelessWidget {
  /// Rows to show, current-position lines first (deepest on top) followed by
  /// any stale previous-position lines.
  final List<AnalysisLine> lines;
  final BestMove? bestMove;

  /// Position the [bestMove] applies to.
  final Position position;

  const AnalysisPanel({
    super.key,
    this.lines = const [],
    this.bestMove,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty && bestMove == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Press Analyze to start engine analysis.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bestMove != null) ...[
            Text(
              'Best: ${MoveNotation.toChinese(bestMove!.move, position)}'
              '${bestMove!.ponder != null ? '  Ponder: ${MoveNotation.toChinese(bestMove!.ponder!, MoveNotation.applyUciMove(position, bestMove!.move))}' : ''}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (lines.isNotEmpty) ...[
            const _HeaderRow(),
            const Divider(height: 8),
            for (final line in lines) _LineRow(line: line),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey,
    );
    return Row(
      children: const [
        SizedBox(
          width: _kDepthWidth,
          child: Text('Depth', style: style, textAlign: TextAlign.right),
        ),
        SizedBox(width: _kColumnGap),
        SizedBox(
          width: _kScoreWidth,
          child: Text('Score', style: style),
        ),
        SizedBox(width: _kColumnGap),
        SizedBox(
          width: _kTimeWidth,
          child: Text('Time', style: style),
        ),
        SizedBox(width: _kColumnGap),
        Expanded(child: Text('Line', style: style)),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  final AnalysisLine line;

  const _LineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final info = line.info;
    final scoreColor = _isAdvantage(info)
        ? Colors.green.shade800
        : Colors.red.shade800;
    final bound = info.isLowerbound
        ? '≥'
        : info.isUpperbound
        ? '≤'
        : '';

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kDepthWidth,
            child: Text(
              '${info.depth}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: _kColumnGap),
          SizedBox(
            width: _kScoreWidth,
            child: Text(
              '$bound${info.scoreText}',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
          ),
          const SizedBox(width: _kColumnGap),
          SizedBox(
            width: _kTimeWidth,
            child: Text(
              info.timeText,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const SizedBox(width: _kColumnGap),
          Expanded(
            child: Text(
              MoveNotation.pvToChinese(info.pvText, line.position),
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    // Grey out lines that belong to a previous board position.
    return line.stale ? Opacity(opacity: 0.4, child: row) : row;
  }

  /// True when the score favors the side to move (green), else red.
  static bool _isAdvantage(SearchInfo info) {
    if (info.scoreMate != null) return info.scoreMate! > 0;
    return (info.scoreCp ?? 0) >= 0;
  }
}
