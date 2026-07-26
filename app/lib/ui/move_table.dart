import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/position.dart';
import '../models/settings.dart';
import 'board_widget.dart';
import 'hover_preview.dart';

/// The game score as a column of numbered moves, Red and Black side by side —
/// the shape a printed record has, and what fits beside the board.
///
/// It shows the line the board is on; branching off it is done from the
/// variation list rather than by nesting here.
class MoveTable extends StatefulWidget {
  /// Root-first nodes of the current line, including the root.
  final List<GameNode> line;
  final GameNode current;
  final DisplayLanguage language;
  final ValueChanged<GameNode> onSelect;

  /// Preview the position a move leads to while it is hovered.
  final bool showPreview;
  final bool viewFromBlack;

  /// Score for a position, shown in the preview when one is known.
  final String? Function(GameNode node)? scoreLabelFor;

  const MoveTable({
    super.key,
    required this.line,
    required this.current,
    required this.onSelect,
    this.language = DisplayLanguage.simplified,
    this.showPreview = true,
    this.viewFromBlack = false,
    this.scoreLabelFor,
  });

  @override
  State<MoveTable> createState() => _MoveTableState();
}

class _MoveTableState extends State<MoveTable> {
  final _scrollController = ScrollController();

  static const double _rowHeight = 26;

  @override
  void didUpdateWidget(MoveTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.current, widget.current)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Keep the move being viewed on screen as the game is stepped through.
  void _revealCurrent() {
    if (!_scrollController.hasClients) return;
    final row = (widget.current.ply - 1) ~/ 2;
    final scale = MediaQuery.textScalerOf(context).scale(_rowHeight);
    final target = row * scale;
    final viewport = _scrollController.position.viewportDimension;
    final offset = _scrollController.offset;
    if (target < offset || target + scale > offset + viewport) {
      _scrollController.animateTo(
        (target - viewport / 2 + scale).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moves = widget.line.skip(1).toList();
    final rows = (moves.length + 1) ~/ 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Text(
                'Moves',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.current.ply}/${moves.length}',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: moves.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'No moves yet.',
                    style: TextStyle(color: theme.hintColor, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: rows,
                  itemExtent: MediaQuery.textScalerOf(
                    context,
                  ).scale(_rowHeight),
                  itemBuilder: (context, row) {
                    final red = moves[row * 2];
                    final black = row * 2 + 1 < moves.length
                        ? moves[row * 2 + 1]
                        : null;
                    return Row(
                      children: [
                        SizedBox(
                          width: MediaQuery.textScalerOf(context).scale(26),
                          child: Text(
                            '${row + 1}.',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: _cell(red)),
                        Expanded(
                          child: black == null
                              ? const SizedBox()
                              : _cell(black),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _cell(GameNode node) {
    final theme = Theme.of(context);
    final selected = identical(node, widget.current);
    final parent = node.parent;
    final notation = parent == null || node.move == null
        ? ''
        : MoveNotation.toNotation(node.move!, parent.position, widget.language);

    final cell = Container(
      margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              notation,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? theme.colorScheme.onPrimaryContainer : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // A move that carries a note or branches says so, since neither is
          // visible in a flat table.
          if (node.comment.isNotEmpty)
            Icon(
              Icons.chat_bubble,
              size: 8,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.primary,
            ),
          if (parent != null && parent.children.length > 1)
            Icon(
              Icons.call_split,
              size: 11,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.hintColor,
            ),
        ],
      ),
    );

    final tappable = InkWell(
      onTap: () => widget.onSelect(node),
      borderRadius: BorderRadius.circular(3),
      child: cell,
    );

    if (!widget.showPreview || parent == null || node.move == null) {
      return tappable;
    }
    final score = widget.scoreLabelFor?.call(node);
    return HoverPreview(
      previewSize: MovePreviewCard.sizeFor(
        rowCount: 0,
        hasSubtitle: score != null || node.comment.isNotEmpty,
      ),
      previewBuilder: (context) => MovePreviewCard(
        title: '${node.moveNumber}${node.isRedMove ? '.' : '...'} $notation',
        subtitle: score != null
            ? 'score $score'
            : (node.comment.isEmpty ? null : node.comment),
        position: node.position,
        language: widget.language,
        viewFromBlack: widget.viewFromBlack,
        arrows: [
          BoardArrow(
            from: Position.uciToSquare(node.move!.substring(0, 2))!,
            to: Position.uciToSquare(node.move!.substring(2, 4))!,
            side: parent.position.sideToMove,
            label: '',
          ),
        ],
      ),
      child: tappable,
    );
  }
}
