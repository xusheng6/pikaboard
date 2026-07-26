import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/search_info.dart';
import '../models/position.dart';
import '../models/settings.dart';
import 'board_widget.dart';
import 'hover_preview.dart';

/// A stored evaluation for one position: [cp] is centipawns from Red's point
/// of view, [depth] the search that produced it so deeper results can win, and
/// [bestMove] the move the engine wanted, in UCI.
class ScoreSample {
  final int cp;
  final int depth;
  final String? bestMove;

  const ScoreSample({required this.cp, required this.depth, this.bestMove});
}

/// One plotted position: its score, and what the hover readout needs to
/// explain it.
class ScorePoint {
  /// How the move that reached this position reads, e.g. "3. 炮二平五".
  final String label;

  /// The position itself, drawn as a preview on hover.
  final Position position;

  /// Score from Red's point of view, null when the position is unanalysed.
  final int? cp;
  final int? depth;

  /// The engine's choice here, as a move and as notation.
  final String? bestMoveUci;
  final String? bestMoveText;

  /// The move actually played next in this line, and the score it led to.
  final String? playedMoveText;
  final int? playedCp;

  const ScorePoint({
    required this.label,
    required this.position,
    this.cp,
    this.depth,
    this.bestMoveUci,
    this.bestMoveText,
    this.playedMoveText,
    this.playedCp,
  });

  /// True when the game followed the engine's recommendation.
  bool get playedTheBest =>
      playedMoveText != null && playedMoveText == bestMoveText;
}

/// Mates are charted as a large magnitude rather than a real score; the chart
/// clamps anyway, so only the sign matters.
const int kMateCentipawns = 20000;

/// [info]'s score in centipawns from Red's point of view, or null when the
/// engine reported no score. The engine scores from the side to move, so
/// black-to-move values are negated.
int? redCentipawns(SearchInfo info, {required bool sideToMoveIsRed}) {
  final sign = sideToMoveIsRed ? 1 : -1;
  if (info.scoreMate != null) {
    return sign * (info.scoreMate! >= 0 ? kMateCentipawns : -kMateCentipawns);
  }
  if (info.scoreCp == null) return null;
  return sign * info.scoreCp!;
}

/// The game's evaluation over time, as a line chart.
///
/// [centipawns] is indexed by ply: entry i is the score of the position after
/// i plies from Red's point of view, or null where that position has not been
/// analysed. Above the centre line means Red stands better.
class ScoreChart extends StatefulWidget {
  /// One entry per ply of the line, in play order.
  final List<ScorePoint> points;

  /// Ply currently shown on the board, marked on the chart.
  final int currentPly;

  /// Called with the ply to jump to when the chart is tapped.
  final ValueChanged<int>? onSelect;

  /// Start analysing the whole line, filling the chart in.
  final VoidCallback? onAnalyseGame;

  /// Stop an analysis that is running.
  final VoidCallback? onCancelAnalysis;

  /// Plies analysed so far out of the total, while a run is in progress.
  final int? analysedCount;
  final int? analysisTotal;

  /// Show the board preview alongside the hover readout.
  final bool showPreview;
  final DisplayLanguage language;

  const ScoreChart({
    super.key,
    required this.points,
    required this.currentPly,
    this.onSelect,
    this.onAnalyseGame,
    this.onCancelAnalysis,
    this.analysedCount,
    this.analysisTotal,
    this.showPreview = true,
    this.language = DisplayLanguage.simplified,
  });

  bool get isAnalysing => analysedCount != null && analysisTotal != null;

  /// Gutter on the left holds the score labels.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(46, 16, 14, 12);

  /// Vertical ranges the chart will settle on, smallest first.
  static const List<double> rangeSteps = [
    50,
    100,
    200,
    300,
    500,
    800,
    1200,
    2000,
  ];

  /// The range that fits [scores]: the smallest step covering every ordinary
  /// score. Mates are ignored here and pinned to the edge instead, so one
  /// forced win cannot flatten the rest of the game.
  static double rangeFor(Iterable<int?> scores) {
    var largest = 0.0;
    for (final cp in scores) {
      if (cp == null || cp.abs() >= kMateCentipawns) continue;
      final magnitude = cp.abs().toDouble();
      if (magnitude > largest) largest = magnitude;
    }
    for (final step in rangeSteps) {
      if (largest <= step) return step;
    }
    return rangeSteps.last;
  }

  @override
  State<ScoreChart> createState() => _ScoreChartState();
}

class _ScoreChartState extends State<ScoreChart> {
  int? _hoverPly;

  // The readout lives in the app overlay so the panel cannot clip it.
  final _previewController = OverlayPortalController();
  Offset _pointer = Offset.zero;

  List<int?> get _scores => [for (final point in widget.points) point.cp];

  @override
  void didUpdateWidget(ScoreChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hoverPly != null && _hoverPly! >= widget.points.length) {
      _hoverPly = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centipawns = _scores;
    final known = centipawns.where((c) => c != null).length;
    final range = ScoreChart.rangeFor(centipawns);

    final current = centipawns.isEmpty
        ? null
        : centipawns[widget.currentPly.clamp(0, centipawns.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
          child: Row(
            children: [
              // The heading and coverage share whatever the score and buttons
              // leave, so a narrow panel truncates them instead of overflowing.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Score (Red +)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.isAnalysing
                            ? 'analysing ${widget.analysedCount} of ${widget.analysisTotal}'
                            : '$known of ${centipawns.length} positions',
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (current != null || !widget.isAnalysing)
                Text(
                  current == null
                      ? 'ply ${widget.currentPly}'
                      : scoreLabel(current),
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: current == null
                        ? theme.hintColor
                        : (current >= 0
                              ? Colors.red.shade600
                              : theme.colorScheme.onSurface),
                  ),
                ),
              if (widget.isAnalysing && widget.onCancelAnalysis != null)
                IconButton(
                  onPressed: widget.onCancelAnalysis,
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  tooltip: 'Stop analysing',
                  visualDensity: VisualDensity.compact,
                )
              else if (widget.onAnalyseGame != null)
                IconButton(
                  onPressed: widget.onAnalyseGame,
                  icon: const Icon(Icons.auto_graph, size: 20),
                  tooltip: 'Analyse the whole game',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        if (widget.isAnalysing && widget.analysisTotal! > 0)
          LinearProgressIndicator(
            value: widget.analysedCount! / widget.analysisTotal!,
            minHeight: 2,
          ),
        if (known == 0)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No evaluations yet. Analyse the whole game with the button '
                'above, or analyse positions as you step through — every '
                'score lands here.',
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return OverlayPortal(
                  controller: _previewController,
                  overlayChildBuilder: (overlayContext) => placePreview(
                    screen: MediaQuery.sizeOf(overlayContext),
                    pointer: _pointer,
                    size: _cardSize(),
                    child: _hoverCard(overlayContext),
                  ),
                  child: MouseRegion(
                    onHover: (event) => _setHover(event, size),
                    onExit: (_) => _clearHover(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: widget.onSelect == null
                          ? null
                          : (details) => widget.onSelect!(
                              plyAt(details.localPosition.dx, size.width),
                            ),
                      child: CustomPaint(
                        painter: _ScorePainter(
                          centipawns: centipawns,
                          range: range,
                          currentPly: widget.currentPly,
                          hoverPly: _hoverPly,
                          lineColor: theme.colorScheme.onSurface,
                          zeroLineColor: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                          gridColor: theme.dividerColor,
                          labelColor: theme.hintColor,
                          negativeFill: theme.colorScheme.onSurface.withValues(
                            alpha: 0.18,
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _setHover(PointerHoverEvent event, Size size) {
    final ply = plyAt(event.localPosition.dx, size.width);
    setState(() {
      _hoverPly = ply;
      _pointer = event.position;
    });
    final hasScore =
        ply < widget.points.length && widget.points[ply].cp != null;
    if (hasScore) {
      if (!_previewController.isShowing) _previewController.show();
    } else if (_previewController.isShowing) {
      _previewController.hide();
    }
  }

  void _clearHover() {
    setState(() => _hoverPly = null);
    if (_previewController.isShowing) _previewController.hide();
  }

  /// The ply nearest to a tap or pointer at [dx] within a chart [width] wide.
  int plyAt(double dx, double width) {
    final plotWidth = width - ScoreChart.padding.horizontal;
    if (widget.points.length < 2 || plotWidth <= 0) return 0;
    final t = ((dx - ScoreChart.padding.left) / plotWidth).clamp(0.0, 1.0);
    return (t * (widget.points.length - 1)).round();
  }

  /// Rows the readout shows under the board, so its size is known before it
  /// is built.
  List<PreviewRow> _previewRows(ScorePoint point) => [
    if (point.bestMoveText != null)
      PreviewRow(
        label: 'Best',
        text: point.bestMoveText!,
        colour: Colors.green.shade600,
        trailing: point.cp == null ? null : scoreLabel(point.cp!),
      ),
    if (point.playedMoveText != null && !point.playedTheBest)
      PreviewRow(
        label: 'Played',
        text: point.playedMoveText!,
        colour: Colors.amber.shade700,
        trailing: point.playedCp == null ? null : scoreLabel(point.playedCp!),
      )
    else if (point.playedTheBest)
      PreviewRow(
        label: 'Played',
        text: "the engine's move",
        colour: Colors.amber.shade700,
      ),
  ];

  Size _cardSize() {
    final ply = _hoverPly;
    if (ply == null || ply >= widget.points.length) {
      return MovePreviewCard.sizeFor(rowCount: 0, hasSubtitle: true);
    }
    return MovePreviewCard.sizeFor(
      rowCount: widget.showPreview
          ? _previewRows(widget.points[ply]).length
          : 0,
      hasSubtitle: true,
    );
  }

  /// Readout for the position under the pointer: what it is, what it is worth,
  /// how it looks, and how the move played compares with the engine's choice.
  Widget _hoverCard(BuildContext context) {
    final ply = _hoverPly!;
    final point = widget.points[ply];
    final depth = point.depth;
    return MovePreviewCard(
      title: point.label,
      subtitle:
          '${point.cp == null ? '' : 'score ${scoreLabel(point.cp!)}'}'
          '${depth == null ? '' : '   depth $depth'}',
      position: point.position,
      language: widget.language,
      arrows: [
        if (point.bestMoveUci != null && point.bestMoveUci!.length >= 4)
          BoardArrow(
            from: Position.uciToSquare(point.bestMoveUci!.substring(0, 2))!,
            to: Position.uciToSquare(point.bestMoveUci!.substring(2, 4))!,
            side: point.position.sideToMove,
            label: '1',
          ),
      ],
      rows: _previewRows(point),
    );
  }
}

/// Exact score for display: mates as M+/M-, everything else signed centipawns.
String scoreLabel(int cp) {
  if (cp.abs() >= kMateCentipawns) return cp > 0 ? 'M+' : 'M-';
  return '${cp >= 0 ? '+' : ''}$cp';
}

class _ScorePainter extends CustomPainter {
  final List<int?> centipawns;
  final double range;
  final int currentPly;
  final int? hoverPly;
  final Color lineColor;
  final Color zeroLineColor;
  final Color gridColor;
  final Color labelColor;
  final Color negativeFill;

  _ScorePainter({
    required this.centipawns,
    required this.range,
    required this.currentPly,
    required this.hoverPly,
    required this.lineColor,
    required this.zeroLineColor,
    required this.gridColor,
    required this.labelColor,
    required this.negativeFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = ScoreChart.padding;
    final plot = Rect.fromLTRB(
      pad.left,
      pad.top,
      size.width - pad.right,
      size.height - pad.bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final zeroY = _y(0, plot);

    // Gridlines follow the range in use: the edges and their halves.
    for (final value in [range, range / 2, 0.0, -range / 2, -range]) {
      final y = _y(value, plot);
      final isZero = value == 0;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          // The zero line is the one that matters, so it is drawn solid and
          // heavier than the rest.
          ..color = isZero ? zeroLineColor : gridColor.withValues(alpha: 0.45)
          ..strokeWidth = isZero ? 1.8 : 1,
      );
      _label(
        canvas,
        value == 0 ? '0' : '${value > 0 ? '+' : ''}${value.round()}',
        Offset(plot.left - 6, y),
        isZero,
      );
    }

    // Known points, connected straight across any unanalysed plies.
    final points = <Offset>[];
    for (var ply = 0; ply < centipawns.length; ply++) {
      final cp = centipawns[ply];
      if (cp == null) continue;
      points.add(Offset(_x(ply, plot), _y(cp.toDouble(), plot)));
    }
    if (points.isEmpty) return;

    if (points.length > 1) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        line.lineTo(p.dx, p.dy);
      }

      // Fill between the line and the centre, split at the zero line so Red's
      // advantage reads red and Black's reads dark.
      final area = Path.from(line)
        ..lineTo(points.last.dx, zeroY)
        ..lineTo(points.first.dx, zeroY)
        ..close();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(plot.left, plot.top, plot.right, zeroY));
      canvas.drawPath(area, Paint()..color = Colors.red.withValues(alpha: 0.3));
      canvas.restore();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(plot.left, zeroY, plot.right, plot.bottom));
      canvas.drawPath(area, Paint()..color = negativeFill);
      canvas.restore();

      canvas.drawPath(
        line,
        Paint()
          ..color = lineColor.withValues(alpha: 0.9)
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    for (final p in points) {
      canvas.drawCircle(p, 2.5, Paint()..color = lineColor);
    }

    // Where the board currently sits.
    final x = _x(currentPly, plot);
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = Colors.orange.shade600
        ..strokeWidth = 1.5,
    );
    final cp = currentPly < centipawns.length ? centipawns[currentPly] : null;
    if (cp != null) {
      canvas.drawCircle(
        Offset(x, _y(cp.toDouble(), plot)),
        4,
        Paint()..color = Colors.orange.shade700,
      );
    }

    // The point under the pointer, ringed to match the readout.
    final hovered = hoverPly;
    if (hovered != null &&
        hovered < centipawns.length &&
        centipawns[hovered] != null) {
      final center = Offset(
        _x(hovered, plot),
        _y(centipawns[hovered]!.toDouble(), plot),
      );
      canvas.drawCircle(center, 5, Paint()..color = lineColor);
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset rightCenter, bool emphasised) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: emphasised ? lineColor : labelColor,
          fontSize: 10,
          fontWeight: emphasised ? FontWeight.bold : FontWeight.normal,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        rightCenter.dx - painter.width,
        rightCenter.dy - painter.height / 2,
      ),
    );
  }

  double _x(int ply, Rect plot) {
    if (centipawns.length < 2) return plot.center.dx;
    return plot.left + plot.width * (ply / (centipawns.length - 1));
  }

  double _y(double cp, Rect plot) {
    // Mates land on the edge rather than dragging the scale out to 20000.
    final clamped = cp.clamp(-range, range);
    return plot.center.dy - (clamped / range) * (plot.height / 2);
  }

  @override
  bool shouldRepaint(covariant _ScorePainter oldDelegate) =>
      oldDelegate.currentPly != currentPly ||
      oldDelegate.hoverPly != hoverPly ||
      oldDelegate.range != range ||
      oldDelegate.lineColor != lineColor ||
      !_sameScores(oldDelegate.centipawns, centipawns);

  static bool _sameScores(List<int?> a, List<int?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
