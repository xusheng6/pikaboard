import 'package:flutter/material.dart';
import '../engine/search_info.dart';
import '../models/move_notation.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';
import 'board_widget.dart';
import 'hover_preview.dart';

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

// Shared column widths so the header and every row line up. They are sized for
// unscaled text, so run them through [_w] to follow the font-size setting.
const double _kDepthWidth = 46;
const double _kScoreWidth = 64;
const double _kTimeWidth = 54;
const double _kColumnGap = 8;

/// Scales a fixed column width by the current text scale so wider text still
/// fits its column.
double _w(BuildContext context, double width) =>
    MediaQuery.textScalerOf(context).scale(width);

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
  /// Preview the position a move in a line leads to while it is hovered.
  final bool showPreview;

  /// Draw previews rotated, matching a board viewed from Black's side.
  final bool viewFromBlack;

  /// Rows to show, current-position lines first (deepest on top) followed by
  /// any stale previous-position lines.
  final List<AnalysisLine> lines;
  final BestMove? bestMove;

  /// Position the [bestMove] applies to.
  final Position position;

  /// True when [bestMove] was computed for a position the board has moved on
  /// from; it is then greyed out like the stale lines.
  final bool bestMoveStale;
  final DisplayLanguage language;
  final ScorePerspective scorePerspective;

  const AnalysisPanel({
    super.key,
    this.lines = const [],
    this.bestMove,
    required this.position,
    this.bestMoveStale = false,
    this.language = DisplayLanguage.simplified,
    this.scorePerspective = ScorePerspective.red,
    this.showPreview = true,
    this.viewFromBlack = false,
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

    // The table scrolls; the best move and the search stats stay pinned to the
    // bottom of the panel so they are always visible.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lines.isNotEmpty) ...[
                  const _HeaderRow(),
                  const Divider(height: 8),
                  for (final line in lines)
                    _LineRow(
                      line: line,
                      language: language,
                      scorePerspective: scorePerspective,
                      showPreview: showPreview,
                      viewFromBlack: viewFromBlack,
                    ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bestMove != null) ...[
                Opacity(
                  opacity: bestMoveStale ? 0.4 : 1,
                  child: Text(
                    'Best: ${MoveNotation.toNotation(bestMove!.move, position, language)}'
                    '${bestMove!.ponder != null ? '  Ponder: ${MoveNotation.toNotation(bestMove!.ponder!, MoveNotation.applyUciMove(position, bestMove!.move), language)}' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
                if (lines.isNotEmpty) const SizedBox(height: 4),
              ],
              if (lines.isNotEmpty) _statsRow(context),
            ],
          ),
        ),
      ],
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
      children: [
        SizedBox(
          width: _w(context, _kDepthWidth),
          child: const Text(
            'Depth',
            style: style,
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
        const SizedBox(width: _kColumnGap),
        SizedBox(
          width: _w(context, _kScoreWidth),
          child: const Text('Score', style: style),
        ),
        const SizedBox(width: _kColumnGap),
        SizedBox(
          width: _w(context, _kTimeWidth),
          child: const Text('Time', style: style),
        ),
        const SizedBox(width: _kColumnGap),
        const Expanded(child: Text('Line', style: style)),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  final AnalysisLine line;
  final DisplayLanguage language;
  final ScorePerspective scorePerspective;
  final bool showPreview;
  final bool viewFromBlack;

  const _LineRow({
    required this.line,
    required this.language,
    required this.scorePerspective,
    this.showPreview = true,
    this.viewFromBlack = false,
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
            width: _w(context, _kDepthWidth),
            child: Text(
              '${info.depth}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: _kColumnGap),
          SizedBox(
            width: _w(context, _kScoreWidth),
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
            width: _w(context, _kTimeWidth),
            child: Text(
              info.timeText,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const SizedBox(width: _kColumnGap),
          Expanded(
            child: showPreview
                ? _PvMoves(
                    pvText: info.pvText,
                    position: line.position,
                    language: language,
                    viewFromBlack: viewFromBlack,
                  )
                : Text(
                    MoveNotation.pvToNotation(
                      info.pvText,
                      line.position,
                      language,
                    ),
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

/// A line's moves, each hoverable to preview the position it leads to.
class _PvMoves extends StatelessWidget {
  final String pvText;
  final Position position;
  final DisplayLanguage language;
  final bool viewFromBlack;

  const _PvMoves({
    required this.pvText,
    required this.position,
    required this.language,
    this.viewFromBlack = false,
  });

  @override
  Widget build(BuildContext context) {
    final steps = MoveNotation.pvSteps(pvText, position, language);
    if (steps.isEmpty) return const SizedBox.shrink();

    // Wrapped rather than one string so each move can be hovered; clipped to
    // two lines like the plain text it replaces.
    return ClipRect(
      child: SizedBox(
        height: MediaQuery.textScalerOf(context).scale(38),
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          children: [
            for (var i = 0; i < steps.length; i++)
              HoverPreview(
                previewSize: MovePreviewCard.sizeFor(
                  rowCount: 0,
                  hasSubtitle: true,
                ),
                previewBuilder: (context) => MovePreviewCard(
                  title: steps[i].notation,
                  subtitle: 'after ${i + 1} of ${steps.length} in this line',
                  position: steps[i].after,
                  language: language,
                  viewFromBlack: viewFromBlack,
                  arrows: [
                    BoardArrow(
                      from: Position.uciToSquare(steps[i].uci.substring(0, 2))!,
                      to: Position.uciToSquare(steps[i].uci.substring(2, 4))!,
                      side: steps[i].before.sideToMove,
                      label: '',
                    ),
                  ],
                ),
                child: Text(
                  steps[i].notation,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
