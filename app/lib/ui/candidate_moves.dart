import 'package:flutter/material.dart';

import '../models/move_notation.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';
import '../services/chessdb.dart';

/// Shows candidate moves for the current position from the chessdb.cn cloud
/// database. Refetches whenever the position changes; tapping a move plays it.
class CandidateMoves extends StatefulWidget {
  final Position position;
  final DisplayLanguage language;
  final ScorePerspective scorePerspective;
  final void Function(String uci)? onPlay;

  const CandidateMoves({
    super.key,
    required this.position,
    this.language = DisplayLanguage.simplified,
    this.scorePerspective = ScorePerspective.red,
    this.onPlay,
  });

  @override
  State<CandidateMoves> createState() => _CandidateMovesState();
}

class _CandidateMovesState extends State<CandidateMoves> {
  List<ChessDbMove> _moves = const [];
  bool _loading = false;
  String? _fetchedFen;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(CandidateMoves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position.toFen() != _fetchedFen) _fetch();
  }

  Future<void> _fetch() async {
    final fen = widget.position.toFen();
    _fetchedFen = fen;
    final id = ++_requestId;
    setState(() => _loading = true);
    final moves = await ChessDb.queryAll(fen);
    if (!mounted || id != _requestId) return;
    setState(() {
      _moves = moves;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Cloud (chessdb.cn)',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                InkWell(
                  onTap: _fetch,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.refresh, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (!_loading && _moves.isEmpty)
            Text(
              'No cloud moves for this position.',
              style: TextStyle(color: theme.disabledColor, fontSize: 13),
            )
          else
            for (final m in _moves) _row(m),
        ],
      ),
    );
  }

  Widget _row(ChessDbMove m) {
    final sideIsRed = widget.position.sideToMove == PieceColor.red;
    final flip = widget.scorePerspective == ScorePerspective.red && !sideIsRed;
    final shownScore = flip ? -m.score : m.score;
    final scoreColor = shownScore >= 0
        ? Colors.green.shade600
        : Colors.red.shade600;
    final notation = MoveNotation.toNotation(
      m.uci,
      widget.position,
      widget.language,
    );

    return InkWell(
      onTap: widget.onPlay == null ? null : () => widget.onPlay!(m.uci),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(76),
              child: Text(
                notation,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: MediaQuery.textScalerOf(context).scale(56),
              child: Text(
                '${shownScore >= 0 ? '+' : ''}$shownScore',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  if (m.winrate != null) '${m.winrate!.toStringAsFixed(1)}%',
                  if (m.note.isNotEmpty) m.note,
                ].join('  '),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
