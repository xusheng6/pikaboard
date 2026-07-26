import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/settings.dart';

/// The branches available around the position on the board: which moves carry
/// on from here, and which other moves were tried instead of the one played.
///
/// This is how you leave the line the move table shows — the table stays flat,
/// and switching lines happens here.
class VariationList extends StatelessWidget {
  final GameNode current;
  final DisplayLanguage language;
  final ValueChanged<GameNode> onSelect;

  /// Make a variation the main line, or drop it.
  final ValueChanged<GameNode>? onPromote;
  final ValueChanged<GameNode>? onDelete;

  const VariationList({
    super.key,
    required this.current,
    required this.onSelect,
    this.onPromote,
    this.onDelete,
    this.language = DisplayLanguage.simplified,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final continuations = current.children;
    final alternatives = current.parent == null
        ? const <GameNode>[]
        : current.parent!.children
              .where((child) => !identical(child, current))
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            'Variations',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: continuations.isEmpty && alternatives.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'No branches here. Play a different move from this '
                    'position and it is recorded as one.',
                    style: TextStyle(color: theme.hintColor, fontSize: 12),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    if (continuations.isNotEmpty)
                      _sectionLabel(theme, 'Continues with'),
                    for (var i = 0; i < continuations.length; i++)
                      _row(
                        context,
                        continuations[i],
                        isMainline: i == 0,
                        showActions: i > 0,
                      ),
                    if (alternatives.isNotEmpty)
                      _sectionLabel(theme, 'Instead of this move'),
                    for (final node in alternatives)
                      _row(
                        context,
                        node,
                        isMainline: identical(
                          node,
                          current.parent!.children.first,
                        ),
                        showActions: true,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: theme.hintColor,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _row(
    BuildContext context,
    GameNode node, {
    required bool isMainline,
    required bool showActions,
  }) {
    final theme = Theme.of(context);
    final parent = node.parent;
    final notation = parent == null || node.move == null
        ? ''
        : MoveNotation.toNotation(node.move!, parent.position, language);

    // A couple of following moves, so a branch is recognisable at a glance.
    final preview = <String>[];
    var cursor = node;
    while (preview.length < 3 && cursor.children.isNotEmpty) {
      final next = cursor.children.first;
      preview.add(
        MoveNotation.toNotation(next.move!, cursor.position, language),
      );
      cursor = next;
    }

    return InkWell(
      onTap: () => onSelect(node),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            Icon(
              isMainline ? Icons.subdirectory_arrow_right : Icons.call_split,
              size: 13,
              color: isMainline ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${node.moveNumber}${node.isRedMove ? '.' : '...'} $notation',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isMainline
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (preview.isNotEmpty)
                    Text(
                      preview.join(' '),
                      style: TextStyle(fontSize: 11, color: theme.hintColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (node.comment.isNotEmpty)
              Icon(
                Icons.chat_bubble,
                size: 9,
                color: theme.colorScheme.primary,
              ),
            if (showActions && onPromote != null && !isMainline)
              IconButton(
                onPressed: () => onPromote!(node),
                icon: const Icon(Icons.vertical_align_top, size: 15),
                tooltip: 'Promote to main line',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            if (showActions && onDelete != null)
              IconButton(
                onPressed: () => onDelete!(node),
                icon: const Icon(Icons.delete_outline, size: 15),
                tooltip: 'Delete this branch',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
          ],
        ),
      ),
    );
  }
}
