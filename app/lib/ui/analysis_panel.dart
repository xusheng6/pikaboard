import 'package:flutter/material.dart';
import '../engine/search_info.dart';
import '../models/move_notation.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';

/// Formats [info]'s score for display.
///
/// The engine reports scores from the side-to-move's perspective. When
/// [redPerspective] is true the value is flipped for black-to-move positions
/// so that positive always means red is better; otherwise it is shown as-is
/// from the side to move. Returns the text and whether it is non-negative
/// (used to pick the color).
({String text, bool positive}) formatScore(
  SearchInfo info, {
  required bool sideToMoveIsRed,
  required bool redPerspective,
}) {
  final flip = redPerspective && !sideToMoveIsRed;
  if (info.scoreMate != null) {
    final m = flip ? -info.scoreMate! : info.scoreMate!;
    return (text: 'M${m > 0 ? '+' : ''}$m', positive: m > 0);
  }
  final cp = flip ? -(info.scoreCp ?? 0) : (info.scoreCp ?? 0);
  return (text: '${cp >= 0 ? '+' : ''}$cp', positive: cp >= 0);
}

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
  final DisplayLanguage language;
  final ScorePerspective scorePerspective;

  const AnalysisPanel({
    super.key,
    this.lines = const [],
    this.bestMove,
    required this.position,
    this.language = DisplayLanguage.simplified,
    this.scorePerspective = ScorePerspective.red,
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
              'Best: ${MoveNotation.toNotation(bestMove!.move, position, language)}'
              '${bestMove!.ponder != null ? '  Ponder: ${MoveNotation.toNotation(bestMove!.ponder!, MoveNotation.applyUciMove(position, bestMove!.move), language)}' : ''}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (lines.isNotEmpty) ...[
            _statsRow(context),
            const SizedBox(height: 4),
            const _HeaderRow(),
            const Divider(height: 8),
            for (final line in lines)
              _LineRow(
                line: line,
                language: language,
                scorePerspective: scorePerspective,
              ),
          ],
        ],
      ),
    );
  }

  /// The line used for the summary stats: the newest current-position line,
  /// falling back to the newest line overall.
  SearchInfo? _statsInfo() {
    for (final l in lines) {
      if (!l.stale) return l.info;
    }
    return lines.isEmpty ? null : lines.first.info;
  }

  Widget _statsRow(BuildContext context) {
    final info = _statsInfo();
    if (info == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 16,
      runSpacing: 2,
      children: [
        _Stat('NPS', info.npsText),
        _Stat('Nodes', info.nodesText),
        _Stat('Hash', '${(info.hashfull / 10).toStringAsFixed(1)}%'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          TextSpan(
            text: value,
            style: DefaultTextStyle.of(
              context,
            ).style.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
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
  final DisplayLanguage language;
  final ScorePerspective scorePerspective;

  const _LineRow({
    required this.line,
    required this.language,
    required this.scorePerspective,
  });

  @override
  Widget build(BuildContext context) {
    final info = line.info;
    final score = formatScore(
      info,
      sideToMoveIsRed: line.position.sideToMove == PieceColor.red,
      redPerspective: scorePerspective == ScorePerspective.red,
    );
    final scoreColor = score.positive
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
              '$bound${score.text}',
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
              MoveNotation.pvToNotation(info.pvText, line.position, language),
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
}
