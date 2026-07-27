import 'package:flutter/material.dart';

import '../models/piece.dart';
import '../models/settings.dart';

/// The pieces you can place while editing a position, with the actions that
/// only make sense there.
///
/// Picking a piece here arms it: the next square tapped on the board receives
/// it. With a board square selected instead, [onDelete] empties it.
class PiecePalette extends StatelessWidget {
  /// The piece armed for placing, if any.
  final Piece? selected;

  /// True when a square on the board is selected, so it can be emptied.
  final bool hasSelectedSquare;

  final ValueChanged<Piece?> onPick;
  final VoidCallback onDelete;

  /// Strip the board back to the two kings.
  final VoidCallback onClear;

  /// Restore the opening position.
  final VoidCallback onReset;

  /// Leave editing.
  final VoidCallback onDone;

  /// Match the board's orientation: viewed from Black, Black's pieces lead.
  final bool viewFromBlack;

  final DisplayLanguage language;

  const PiecePalette({
    super.key,
    required this.onPick,
    required this.onDelete,
    required this.onClear,
    required this.onReset,
    required this.onDone,
    this.selected,
    this.hasSelectedSquare = false,
    this.viewFromBlack = false,
    this.language = DisplayLanguage.simplified,
  });

  /// Back rank order, which is how players expect to find them.
  static const List<PieceType> _order = [
    PieceType.king,
    PieceType.advisor,
    PieceType.bishop,
    PieceType.knight,
    PieceType.rook,
    PieceType.cannon,
    PieceType.pawn,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(left: 8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
              child: Text(
                'Pieces',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final type in _order)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final colour
                              in viewFromBlack
                                  ? PieceColor.values.reversed
                                  : PieceColor.values)
                            _pieceButton(context, Piece(colour, type)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 12),
            Text(
              selected != null
                  ? 'Tap a square to place it'
                  : (hasSelectedSquare
                        ? 'Tap another square to move it'
                        : 'Pick a piece, or tap one on the board'),
              style: TextStyle(fontSize: 10, color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            _action(
              context,
              icon: Icons.backspace_outlined,
              label: 'Delete',
              onPressed: hasSelectedSquare ? onDelete : null,
            ),
            _action(
              context,
              icon: Icons.clear_all,
              label: 'Clear',
              onPressed: onClear,
            ),
            _action(
              context,
              icon: Icons.restart_alt,
              label: 'Reset',
              onPressed: onReset,
            ),
            _action(
              context,
              icon: Icons.check,
              label: 'Done',
              onPressed: onDone,
              filled: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pieceButton(BuildContext context, Piece piece) {
    final theme = Theme.of(context);
    final isSelected = selected == piece;
    // The chips are cream whatever the app theme is, so the piece colours
    // follow the board rather than the surface they sit on — and Black needs
    // real black to read against that cream.
    final colour = piece.color == PieceColor.red
        ? Colors.red.shade800
        : Colors.black;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        // Picking the armed piece again disarms it.
        onTap: () => onPick(isSelected ? null : piece),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFF8DC),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : colour,
              width: isSelected ? 3 : 2,
            ),
          ),
          child: Center(
            child: Text(
              piece.labelFor(language),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colour,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: child,
            ),
    );
  }
}
