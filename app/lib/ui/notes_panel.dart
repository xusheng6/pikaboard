import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/settings.dart';

/// Editor for the comment attached to the position on the board.
///
/// Keeps its own controller so typing does not fight with the rebuilds that
/// annotating triggers elsewhere; the text is only reset when the board moves
/// to a different node.
class NotesPanel extends StatefulWidget {
  final GameNode node;
  final DisplayLanguage language;
  final ValueChanged<String> onChanged;

  const NotesPanel({
    super.key,
    required this.node,
    required this.onChanged,
    this.language = DisplayLanguage.simplified,
  });

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.node.comment,
  );

  @override
  void didUpdateWidget(NotesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.node, widget.node)) {
      _controller.text = widget.node.comment;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Which position the note belongs to, in the reader's notation.
  String get _heading {
    final node = widget.node;
    final parent = node.parent;
    if (parent == null || node.move == null) return 'Starting position';
    final notation = MoveNotation.toNotation(
      node.move!,
      parent.position,
      widget.language,
    );
    return 'After ${node.moveNumber}${node.isRedMove ? '.' : '...'} $notation';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                _heading,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (widget.node.comment.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  tooltip: 'Clear note',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
                hintText: 'Notes on this position…',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
