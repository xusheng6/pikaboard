import 'package:flutter/material.dart';
import '../engine/search_info.dart';
import '../models/move_notation.dart';
import '../models/position.dart';

class AnalysisPanel extends StatelessWidget {
  final SearchInfo? info;
  final BestMove? bestMove;
  final Position position;

  const AnalysisPanel({
    super.key,
    this.info,
    this.bestMove,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    if (info == null && bestMove == null) {
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
          if (info != null) ...[
            // Score and depth row
            Row(
              children: [
                _ScoreChip(info: info!),
                const SizedBox(width: 8),
                Text(
                  'Depth ${info!.depth}/${info!.selDepth}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  info!.timeText,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Stats row
            Row(
              children: [
                _StatLabel('Nodes', info!.nodesText),
                const SizedBox(width: 16),
                _StatLabel('NPS', info!.npsText),
                const SizedBox(width: 16),
                _StatLabel('Hash', '${(info!.hashfull / 10).toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 6),
            // PV line in Chinese notation
            if (info!.pv.isNotEmpty)
              Text(
                MoveNotation.pvToChinese(info!.pvText, position),
                style: const TextStyle(fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          if (bestMove != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Best: ${MoveNotation.toChinese(bestMove!.move, position)}'
                '${bestMove!.ponder != null ? '  Ponder: ${MoveNotation.toChinese(bestMove!.ponder!, _applyMove(position, bestMove!.move))}' : ''}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Position _applyMove(Position pos, String uci) {
  return MoveNotation.applyUciMove(pos, uci);
}

class _ScoreChip extends StatelessWidget {
  final SearchInfo info;

  const _ScoreChip({required this.info});

  @override
  Widget build(BuildContext context) {
    final isPositive = (info.scoreCp ?? 0) >= 0 && (info.scoreMate ?? 1) > 0;
    final bound = info.isLowerbound
        ? '\u2265'
        : info.isUpperbound
            ? '\u2264'
            : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPositive ? Colors.green.shade400 : Colors.red.shade400,
        ),
      ),
      child: Text(
        '$bound${info.scoreText}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          fontFamily: 'monospace',
          color: isPositive ? Colors.green.shade900 : Colors.red.shade900,
        ),
      ),
    );
  }
}

class _StatLabel extends StatelessWidget {
  final String label;
  final String value;

  const _StatLabel(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: Colors.black87),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: Colors.grey),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
