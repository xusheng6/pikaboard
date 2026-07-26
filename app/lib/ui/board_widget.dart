import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';

/// A move drawn over the board as an arrow, numbered by its place in the
/// engine's line: "1" is the move to play now, "2" the expected reply.
///
/// [side] is the colour that plays the move and decides how it is drawn.
@immutable
class BoardArrow {
  final int from;
  final int to;
  final PieceColor side;
  final String label;

  /// How strongly to draw it, 1 for the engine's choice and less for the
  /// alternatives behind it.
  final double strength;

  const BoardArrow({
    required this.from,
    required this.to,
    required this.side,
    required this.label,
    this.strength = 1,
  });

  @override
  bool operator ==(Object other) =>
      other is BoardArrow &&
      other.from == from &&
      other.to == to &&
      other.side == side &&
      other.label == label &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(from, to, side, label, strength);
}

class BoardWidget extends StatelessWidget {
  final Position position;
  final int? selectedSquare;
  final int? lastMoveFrom;
  final int? lastMoveTo;

  /// Engine moves to draw as numbered arrows, in play order.
  final List<BoardArrow> arrows;

  /// Draw the board rotated 180°, i.e. seen from Black's side. Purely a view
  /// setting: the position, and therefore every square index, is unchanged.
  final bool viewFromBlack;
  final ValueChanged<int>? onSquareTap;
  final DisplayLanguage language;

  const BoardWidget({
    super.key,
    required this.position,
    this.selectedSquare,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.arrows = const [],
    this.viewFromBlack = false,
    this.onSquareTap,
    this.language = DisplayLanguage.simplified,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 10,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellW = constraints.maxWidth / 9;
          final cellH = constraints.maxHeight / 10;
          final pieceSize = cellW * 0.88;

          return Stack(
            children: [
              // Board background and grid
              Positioned.fill(
                child: CustomPaint(painter: _BoardPainter(language: language)),
              ),
              // Pieces and tap targets
              for (int rank = 0; rank < Position.ranks; rank++)
                for (int file = 0; file < Position.files; file++)
                  _buildSquare(rank, file, cellW, cellH, pieceSize),
              // Engine arrows sit above the pieces so a move is readable even
              // when both of its squares are occupied.
              if (arrows.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ArrowPainter(
                        arrows: arrows,
                        viewFromBlack: viewFromBlack,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSquare(
    int rank,
    int file,
    double cellW,
    double cellH,
    double pieceSize,
  ) {
    // Display: rank 9 at top (y=0), rank 0 at bottom — or the 180° rotation of
    // that when viewing from Black's side. The grid itself is symmetric, so
    // only the pieces need repositioning.
    final displayRow = viewFromBlack ? rank : Position.ranks - 1 - rank;
    final displayCol = viewFromBlack ? Position.files - 1 - file : file;
    final square = rank * Position.files + file;
    final piece = position.pieceAt(square);
    final isSelected = selectedSquare == square;
    final isLastFrom = lastMoveFrom == square;
    final isLastTo = lastMoveTo == square;

    return Positioned(
      left: displayCol * cellW,
      top: displayRow * cellH,
      width: cellW,
      height: cellH,
      child: GestureDetector(
        onTap: () => onSquareTap?.call(square),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The move just played; engine moves are drawn as arrows instead.
              if (isLastFrom || isLastTo)
                _marker(Colors.amber.shade700, pieceSize, piece != null),
              // Piece
              if (piece != null)
                _PieceWidget(
                  piece: piece,
                  size: pieceSize,
                  isSelected: isSelected,
                  language: language,
                ),
              // Selection ring (on top of piece)
              if (isSelected)
                Container(
                  width: pieceSize + 4,
                  height: pieceSize + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.shade600, width: 3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A move marker in [color]: a slim ring hugging the piece when the square is
  /// occupied, otherwise just the small centre dot.
  static Widget _marker(Color color, double pieceSize, bool occupied) {
    if (occupied) {
      return Container(
        width: pieceSize + 4,
        height: pieceSize + 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      );
    }
    return Container(
      width: pieceSize * 0.34,
      height: pieceSize * 0.34,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Draws the engine's line: a thin arrow per move, in the colour of the side
/// playing it, ending in a numbered dot on the destination square.
class _ArrowPainter extends CustomPainter {
  final List<BoardArrow> arrows;
  final bool viewFromBlack;

  _ArrowPainter({required this.arrows, required this.viewFromBlack});

  static const _red = Color(0xFFC62828);
  static const _black = Color(0xFF212121);

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / Position.files;
    final cellH = size.height / Position.ranks;
    final seenDestinations = <int, int>{};

    for (final arrow in arrows) {
      final color = arrow.side == PieceColor.red ? _red : _black;
      final from = _center(arrow.from, cellW, cellH);
      final to = _center(arrow.to, cellW, cellH);
      final direction = to - from;
      if (direction.distance == 0) continue;
      final unit = direction / direction.distance;

      // When two moves end on the same square (a recapture, say) pull the
      // later dot back along its own arrow so both numbers stay readable.
      final duplicates = seenDestinations.update(
        arrow.to,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      final dotCenter = to - unit * (cellW * 0.4 * duplicates);

      _drawArrow(canvas, from, dotCenter, unit, color, cellW, arrow.strength);
      _drawDot(canvas, dotCenter, color, cellW, arrow.label, arrow.strength);
    }
  }

  Offset _center(int square, double cellW, double cellH) {
    final rank = square ~/ Position.files;
    final file = square % Position.files;
    final row = viewFromBlack ? rank : Position.ranks - 1 - rank;
    final col = viewFromBlack ? Position.files - 1 - file : file;
    return Offset((col + 0.5) * cellW, (row + 0.5) * cellH);
  }

  void _drawArrow(
    Canvas canvas,
    Offset from,
    Offset to,
    Offset unit,
    Color color,
    double cellW,
    double strength,
  ) {
    // Start clear of the moving piece and stop at the edge of the dot.
    final start = from + unit * (cellW * 0.36);
    final end = to - unit * (cellW * 0.2);
    if ((end - start).dx * unit.dx + (end - start).dy * unit.dy <= 0) return;

    final headLength = cellW * 0.24 * (0.7 + 0.3 * strength);
    final headBase = end - unit * headLength;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85 * strength)
      ..strokeWidth = cellW * 0.07 * (0.6 + 0.4 * strength)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, headBase, paint);

    final perpendicular = Offset(-unit.dy, unit.dx) * (headLength * 0.45);
    final head = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(headBase.dx + perpendicular.dx, headBase.dy + perpendicular.dy)
      ..lineTo(headBase.dx - perpendicular.dx, headBase.dy - perpendicular.dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()..color = color.withValues(alpha: 0.85 * strength),
    );
  }

  void _drawDot(
    Canvas canvas,
    Offset center,
    Color color,
    double cellW,
    String label,
    double strength,
  ) {
    final radius = cellW * 0.18 * (0.8 + 0.2 * strength);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.55 + 0.45 * strength),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 1.4,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.viewFromBlack != viewFromBlack ||
      !listEquals(oldDelegate.arrows, arrows);
}

class _PieceWidget extends StatelessWidget {
  final Piece piece;
  final double size;
  final bool isSelected;
  final DisplayLanguage language;

  const _PieceWidget({
    required this.piece,
    required this.size,
    this.isSelected = false,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final isRed = piece.color == PieceColor.red;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? const Color(0xFFFFF3C0) : const Color(0xFFFFF8DC),
        border: Border.all(
          color: isRed ? Colors.red.shade800 : Colors.black87,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isSelected ? 0.5 : 0.3),
            blurRadius: isSelected ? 4 : 2,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          piece.labelFor(language),
          style: TextStyle(
            fontSize: size * 0.55,
            fontWeight: FontWeight.bold,
            color: isRed ? Colors.red.shade800 : Colors.black87,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final DisplayLanguage language;

  _BoardPainter({required this.language});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 9;
    final cellH = size.height / 10;
    final halfCellW = cellW / 2;
    final halfCellH = cellH / 2;

    // Board background
    final bgPaint = Paint()..color = const Color(0xFFDEB887); // burlywood
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Grid offset: center of each cell
    // Files run left-right, ranks run top-bottom
    // Top-left cell center is at (halfCellW, halfCellH)

    double cx(int file) => halfCellW + file * cellW;
    double cy(int displayRow) => halfCellH + displayRow * cellH;

    // Horizontal lines (10 ranks)
    for (int row = 0; row < 10; row++) {
      canvas.drawLine(
        Offset(cx(0), cy(row)),
        Offset(cx(8), cy(row)),
        linePaint,
      );
    }

    // Vertical lines (9 files)
    for (int file = 0; file < 9; file++) {
      // Full vertical lines only for edge files (0 and 8)
      // Inner files break at the river (between row 4 and row 5)
      if (file == 0 || file == 8) {
        canvas.drawLine(
          Offset(cx(file), cy(0)),
          Offset(cx(file), cy(9)),
          linePaint,
        );
      } else {
        // Top half (Black's side: rows 0-4)
        canvas.drawLine(
          Offset(cx(file), cy(0)),
          Offset(cx(file), cy(4)),
          linePaint,
        );
        // Bottom half (Red's side: rows 5-9)
        canvas.drawLine(
          Offset(cx(file), cy(5)),
          Offset(cx(file), cy(9)),
          linePaint,
        );
      }
    }

    // Palace diagonals
    // Black palace: files 3-5, rows 0-2 (display)
    canvas.drawLine(Offset(cx(3), cy(0)), Offset(cx(5), cy(2)), linePaint);
    canvas.drawLine(Offset(cx(5), cy(0)), Offset(cx(3), cy(2)), linePaint);
    // Red palace: files 3-5, rows 7-9 (display)
    canvas.drawLine(Offset(cx(3), cy(7)), Offset(cx(5), cy(9)), linePaint);
    canvas.drawLine(Offset(cx(5), cy(7)), Offset(cx(3), cy(9)), linePaint);

    // River text (traditional uses 漢; simplified and English use 汉)
    final riverText = language == DisplayLanguage.traditional
        ? '楚  河          漢  界'
        : '楚  河          汉  界';
    final riverPaint = TextPainter(
      text: TextSpan(
        text: riverText,
        style: TextStyle(
          fontSize: cellH * 0.45,
          color: Colors.black54,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    riverPaint.layout();
    riverPaint.paint(
      canvas,
      Offset(
        (size.width - riverPaint.width) / 2,
        cy(4) + (cellH - riverPaint.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.language != language;
}
