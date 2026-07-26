import 'package:flutter/material.dart';

import '../engine/search_info.dart';

/// A stored evaluation for one position: [cp] is centipawns from Red's point
/// of view, [depth] the search that produced it so deeper results can win.
class ScoreSample {
  final int cp;
  final int depth;

  const ScoreSample({required this.cp, required this.depth});
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
  final List<int?> centipawns;

  /// Ply currently shown on the board, marked on the chart.
  final int currentPly;

  /// Move description per ply, used by the hover readout. Shorter lists (or an
  /// empty one) simply fall back to the ply number.
  final List<String> plyLabels;

  /// Called with the ply to jump to when the chart is tapped.
  final ValueChanged<int>? onSelect;

  const ScoreChart({
    super.key,
    required this.centipawns,
    required this.currentPly,
    this.plyLabels = const [],
    this.onSelect,
  });

  /// Scores are clamped to this magnitude so one decisive position does not
  /// flatten the rest of the game.
  static const double clampCp = 1000;

  /// Gutter on the left holds the score labels.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(46, 16, 14, 12);

  /// Values that get a gridline and a label.
  static const List<double> gridValues = [1000, 500, 0, -500, -1000];

  @override
  State<ScoreChart> createState() => _ScoreChartState();
}

class _ScoreChartState extends State<ScoreChart> {
  int? _hoverPly;

  @override
  void didUpdateWidget(ScoreChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hoverPly != null && _hoverPly! >= widget.centipawns.length) {
      _hoverPly = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final centipawns = widget.centipawns;
    final known = centipawns.where((c) => c != null).length;
    if (known == 0) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No evaluations yet. Analyse a position and its score is plotted '
          'here; step through the game to fill the graph in.',
          style: TextStyle(color: theme.hintColor),
        ),
      );
    }

    final current = centipawns.isEmpty
        ? null
        : centipawns[widget.currentPly.clamp(0, centipawns.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Text(
                'Score (Red +)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$known of ${centipawns.length} positions',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
              const Spacer(),
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
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return MouseRegion(
                onHover: (event) => _setHover(event.localPosition, size),
                onExit: (_) => setState(() => _hoverPly = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: widget.onSelect == null
                      ? null
                      : (details) => widget.onSelect!(
                          plyAt(details.localPosition.dx, size.width),
                        ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ScorePainter(
                            centipawns: centipawns,
                            currentPly: widget.currentPly,
                            hoverPly: _hoverPly,
                            lineColor: theme.colorScheme.onSurface,
                            zeroLineColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                            gridColor: theme.dividerColor,
                            labelColor: theme.hintColor,
                            negativeFill: theme.colorScheme.onSurface
                                .withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                      if (_hoverPly != null && centipawns[_hoverPly!] != null)
                        _hoverCard(context, size, _hoverPly!),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _setHover(Offset local, Size size) {
    final ply = plyAt(local.dx, size.width);
    if (ply != _hoverPly) setState(() => _hoverPly = ply);
  }

  /// The ply nearest to a tap or pointer at [dx] within a chart [width] wide.
  int plyAt(double dx, double width) {
    final plotWidth = width - ScoreChart.padding.horizontal;
    if (widget.centipawns.length < 2 || plotWidth <= 0) return 0;
    final t = ((dx - ScoreChart.padding.left) / plotWidth).clamp(0.0, 1.0);
    return (t * (widget.centipawns.length - 1)).round();
  }

  /// Small readout naming the position under the pointer and its exact score.
  Widget _hoverCard(BuildContext context, Size size, int ply) {
    final theme = Theme.of(context);
    final cp = widget.centipawns[ply]!;
    final plot = _plotRect(size);
    final x = widget.centipawns.length < 2
        ? plot.center.dx
        : plot.left + plot.width * (ply / (widget.centipawns.length - 1));
    final y =
        plot.center.dy -
        (cp.clamp(-ScoreChart.clampCp, ScoreChart.clampCp) /
                ScoreChart.clampCp) *
            (plot.height / 2);

    const cardWidth = 150.0;
    final left = (x + 12).clamp(
      0.0,
      (size.width - cardWidth).clamp(0.0, size.width),
    );
    final top = (y - 52).clamp(0.0, (size.height - 48).clamp(0.0, size.height));

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.dividerColor),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                plyLabel(ply),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                scoreLabel(cp),
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: cp >= 0
                      ? Colors.red.shade600
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String plyLabel(int ply) {
    if (ply < widget.plyLabels.length) return widget.plyLabels[ply];
    return ply == 0 ? 'Start' : 'Ply $ply';
  }

  Rect _plotRect(Size size) => Rect.fromLTRB(
    ScoreChart.padding.left,
    ScoreChart.padding.top,
    size.width - ScoreChart.padding.right,
    size.height - ScoreChart.padding.bottom,
  );
}

/// Exact score for display: mates as M+/M-, everything else signed centipawns.
String scoreLabel(int cp) {
  if (cp.abs() >= kMateCentipawns) return cp > 0 ? 'M+' : 'M-';
  return '${cp >= 0 ? '+' : ''}$cp';
}

class _ScorePainter extends CustomPainter {
  final List<int?> centipawns;
  final int currentPly;
  final int? hoverPly;
  final Color lineColor;
  final Color zeroLineColor;
  final Color gridColor;
  final Color labelColor;
  final Color negativeFill;

  _ScorePainter({
    required this.centipawns,
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

    for (final value in ScoreChart.gridValues) {
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
        value == 0 ? '0' : '${value > 0 ? '+' : ''}${value.toInt()}',
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
    final clamped = cp.clamp(-ScoreChart.clampCp, ScoreChart.clampCp);
    return plot.center.dy - (clamped / ScoreChart.clampCp) * (plot.height / 2);
  }

  @override
  bool shouldRepaint(covariant _ScorePainter oldDelegate) =>
      oldDelegate.currentPly != currentPly ||
      oldDelegate.hoverPly != hoverPly ||
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
