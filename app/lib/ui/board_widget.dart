import 'package:flutter/material.dart';
import '../models/piece.dart';
import '../models/position.dart';

class BoardWidget extends StatelessWidget {
  final Position position;
  final int? selectedSquare;
  final int? highlightFrom;
  final int? highlightTo;
  final int? lastMoveFrom;
  final int? lastMoveTo;
  final ValueChanged<int>? onSquareTap;

  const BoardWidget({
    super.key,
    required this.position,
    this.selectedSquare,
    this.highlightFrom,
    this.highlightTo,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.onSquareTap,
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
                child: CustomPaint(
                  painter: _BoardPainter(),
                ),
              ),
              // Pieces and tap targets
              for (int rank = 0; rank < Position.ranks; rank++)
                for (int file = 0; file < Position.files; file++)
                  _buildSquare(rank, file, cellW, cellH, pieceSize),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSquare(
      int rank, int file, double cellW, double cellH, double pieceSize) {
    // Display: rank 9 at top (y=0), rank 0 at bottom
    final displayRow = Position.ranks - 1 - rank;
    final square = rank * Position.files + file;
    final piece = position.pieceAt(square);
    final isSelected = selectedSquare == square;
    final isHighlightFrom = highlightFrom == square;
    final isHighlightTo = highlightTo == square;
    final isLastFrom = lastMoveFrom == square;
    final isLastTo = lastMoveTo == square;

    return Positioned(
      left: file * cellW,
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
              // Last move played highlight
              if (isLastFrom || isLastTo)
                Container(
                  width: pieceSize + 2,
                  height: pieceSize + 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
              // Best move highlight (behind piece)
              if (isHighlightFrom || isHighlightTo)
                Container(
                  width: pieceSize + 6,
                  height: pieceSize + 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isHighlightFrom
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.4),
                    border: Border.all(color: Colors.green.shade700, width: 2.5),
                  ),
                ),
              // Piece
              if (piece != null) _PieceWidget(
                piece: piece,
                size: pieceSize,
                isSelected: isSelected,
              ),
              // Selection ring (on top of piece)
              if (isSelected)
                Container(
                  width: pieceSize + 4,
                  height: pieceSize + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.orange.shade600,
                      width: 3,
                    ),
                  ),
                ),
              // Empty square highlight for best move destination
              if (isHighlightTo && piece == null)
                Container(
                  width: pieceSize * 0.4,
                  height: pieceSize * 0.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.shade600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PieceWidget extends StatelessWidget {
  final Piece piece;
  final double size;
  final bool isSelected;

  const _PieceWidget({
    required this.piece,
    required this.size,
    this.isSelected = false,
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
          piece.label,
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

    // River text
    final riverPaint = TextPainter(
      text: TextSpan(
        text: '楚  河          漢  界',
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
