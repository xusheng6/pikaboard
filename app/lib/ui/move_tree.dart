import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/position.dart';
import '../models/settings.dart';
import 'board_widget.dart';
import 'hover_preview.dart';

/// The moves of a game, main line first with variations nested under the move
/// they branch from.
///
/// Reads like a printed game score: the main line flows as wrapped text, and
/// each alternative is indented beneath the move it replaces.
class MoveTree extends StatelessWidget {
  final Game game;

  /// Node currently shown on the board; highlighted here.
  final GameNode current;
  final DisplayLanguage language;
  final ValueChanged<GameNode> onSelect;

  /// Called to drop a variation from the game.
  final ValueChanged<GameNode>? onDelete;

  /// Called to make a variation the main line.
  final ValueChanged<GameNode>? onPromote;

  /// Preview the position a move leads to while it is hovered.
  final bool showPreview;

  /// Score for a position, shown in the preview when one is known.
  final String? Function(GameNode node)? scoreLabelFor;

  const MoveTree({
    super.key,
    required this.game,
    required this.current,
    required this.onSelect,
    this.onDelete,
    this.onPromote,
    this.showPreview = true,
    this.scoreLabelFor,
    this.language = DisplayLanguage.simplified,
  });

  @override
  Widget build(BuildContext context) {
    if (game.root.children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Text('No moves yet.', style: TextStyle(color: Colors.grey)),
            if (game.root.comment.isNotEmpty) ...[
              const SizedBox(width: 8),
              _chip(context, game.root, label: 'Start'),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _lineWidgets(context, game.root, depth: 0),
      ),
    );
  }

  /// Widgets for the line continuing from [from]: a wrapped run of moves, with
  /// an indented block wherever the line branches.
  List<Widget> _lineWidgets(
    BuildContext context,
    GameNode from, {
    required int depth,
  }) {
    final widgets = <Widget>[];
    var run = <Widget>[];

    void flushRun() {
      if (run.isEmpty) return;
      widgets.add(Wrap(spacing: 2, runSpacing: 2, children: run));
      run = <Widget>[];
    }

    var node = from;
    while (node.children.isNotEmpty) {
      final mainline = node.children.first;
      run.add(_chip(context, mainline));

      if (node.children.length > 1) {
        // Alternatives to the move just added, indented under it.
        flushRun();
        for (final variation in node.children.skip(1)) {
          widgets.add(
            Padding(
              padding: EdgeInsets.only(
                left: 12.0 * (depth + 1),
                top: 2,
                bottom: 2,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 2,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        children: [_chip(context, variation)],
                      ),
                      ..._lineWidgets(context, variation, depth: depth + 1),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }
      node = mainline;
    }

    flushRun();
    return widgets;
  }

  Widget _chip(BuildContext context, GameNode node, {String? label}) {
    final theme = Theme.of(context);
    final selected = identical(node, current);
    final text = label ?? _moveLabel(node);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? theme.colorScheme.onPrimaryContainer : null,
            ),
          ),
          if (node.comment.isNotEmpty) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.chat_bubble,
              size: 9,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );

    final canEdit = !node.isRoot && (onDelete != null || onPromote != null);
    final tappable = InkWell(
      onTap: () => onSelect(node),
      onLongPress: canEdit ? () => _showActions(context, node) : null,
      onSecondaryTap: canEdit ? () => _showActions(context, node) : null,
      borderRadius: BorderRadius.circular(4),
      child: chip,
    );

    if (!showPreview || node.isRoot) return tappable;
    final score = scoreLabelFor?.call(node);
    return HoverPreview(
      previewSize: MovePreviewCard.sizeFor(
        rowCount: 0,
        hasSubtitle: score != null || node.comment.isNotEmpty,
      ),
      previewBuilder: (context) => MovePreviewCard(
        title: _moveLabel(node),
        subtitle: score != null
            ? 'score $score'
            : (node.comment.isEmpty ? null : node.comment),
        position: node.position,
        language: language,
        arrows: [
          if (node.move != null && node.parent != null)
            BoardArrow(
              from: Position.uciToSquare(node.move!.substring(0, 2))!,
              to: Position.uciToSquare(node.move!.substring(2, 4))!,
              side: node.parent!.position.sideToMove,
              label: '',
            ),
        ],
      ),
      child: tappable,
    );
  }

  /// Move number plus notation, e.g. "3. 炮二平五" or "3... 马8进7". Black moves
  /// only repeat the number when they open a line.
  String _moveLabel(GameNode node) {
    final parent = node.parent;
    if (parent == null || node.move == null) return 'Start';
    final notation = MoveNotation.toNotation(
      node.move!,
      parent.position,
      language,
    );
    if (node.isRedMove) return '${node.moveNumber}. $notation';
    // A black move needs its number when it starts a line or follows a branch.
    final startsLine = parent.isRoot || parent.children.length > 1;
    return startsLine ? '${node.moveNumber}... $notation' : notation;
  }

  void _showActions(BuildContext context, GameNode node) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_moveLabel(node)),
              subtitle: Text(
                node.isMainline ? 'On the main line' : 'In a variation',
              ),
            ),
            const Divider(height: 1),
            if (onPromote != null && !node.isMainline)
              ListTile(
                leading: const Icon(Icons.vertical_align_top),
                title: const Text('Promote to main line'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onPromote!(node);
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete from here'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete!(node);
                },
              ),
          ],
        ),
      ),
    );
  }
}
