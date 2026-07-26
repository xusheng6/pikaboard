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
class ScoreChart extends StatelessWidget {
  final List<int?> centipawns;

  /// Ply currently shown on the board, marked on the chart.
  final int currentPly;

  /// Called with the ply to jump to when the chart is tapped.
  final ValueChanged<int>? onSelect;

  const ScoreChart({
    super.key,
    required this.centipawns,
    required this.currentPly,
    this.onSelect,
  });

  /// Scores are clamped to this magnitude so one decisive position does not
  /// flatten the rest of the game.
  static const double clampCp = 1000;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(12, 16, 12, 12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        : centipawns[currentPly.clamp(0, centipawns.length - 1)];

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
                current == null ? 'ply $currentPly' : _label(current),
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
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: onSelect == null
                    ? null
                    : (details) => onSelect!(
                        _plyAt(details.localPosition.dx, constraints.maxWidth),
                      ),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _ScorePainter(
                    centipawns: centipawns,
                    currentPly: currentPly,
                    lineColor: theme.colorScheme.onSurface,
                    gridColor: theme.dividerColor,
                    negativeFill: theme.colorScheme.onSurface.withValues(
                      alpha: 0.18,
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

  static String _label(int cp) {
    if (cp.abs() >= kMateCentipawns) return cp > 0 ? 'M+' : 'M-';
    return '${cp >= 0 ? '+' : ''}$cp';
  }

  /// The ply nearest to a tap at [dx] within a chart [width] wide.
  int _plyAt(double dx, double width) {
    final plotWidth = width - _padding.horizontal;
    if (centipawns.length < 2 || plotWidth <= 0) return 0;
    final t = ((dx - _padding.left) / plotWidth).clamp(0.0, 1.0);
    return (t * (centipawns.length - 1)).round();
  }
}

class _ScorePainter extends CustomPainter {
  final List<int?> centipawns;
  final int currentPly;
  final Color lineColor;
  final Color gridColor;
  final Color negativeFill;

  _ScorePainter({
    required this.centipawns,
    required this.currentPly,
    required this.lineColor,
    required this.gridColor,
    required this.negativeFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = ScoreChart._padding;
    final plot = Rect.fromLTRB(
      pad.left,
      pad.top,
      size.width - pad.right,
      size.height - pad.bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final zeroY = plot.center.dy;

    // Centre line plus a quiet gridline at ±500cp.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(plot.left, zeroY),
      Offset(plot.right, zeroY),
      grid..color = gridColor,
    );
    for (final cp in [-500.0, 500.0]) {
      final y = _y(cp, plot);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..color = gridColor.withValues(alpha: 0.4)
          ..strokeWidth = 1,
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
