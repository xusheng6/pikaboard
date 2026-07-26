import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/engine/search_info.dart';
import 'package:app/models/move_notation.dart';
import 'package:app/models/piece.dart';
import 'package:app/models/position.dart';
import 'package:app/ui/analysis_panel.dart';

SearchInfo _line(int depth, {int scoreCp = 0, required String pv}) {
  return SearchInfo(
    depth: depth,
    selDepth: depth + 4,
    multiPV: 1,
    scoreCp: scoreCp,
    nodes: 1000 * depth,
    nps: 500000,
    timeMs: 100 * depth,
    hashfull: 50,
    pv: pv.split(' '),
  );
}

void main() {
  group('Simplified Chinese pieces', () {
    test('piece labels use simplified characters', () {
      expect(const Piece(PieceColor.red, PieceType.king).label, '帅');
      expect(const Piece(PieceColor.red, PieceType.knight).label, '马');
      expect(const Piece(PieceColor.red, PieceType.rook).label, '车');
      expect(const Piece(PieceColor.red, PieceType.cannon).label, '炮');
      expect(const Piece(PieceColor.black, PieceType.king).label, '将');

      // No traditional forms remain.
      final labels = [
        for (final c in PieceColor.values)
          for (final t in PieceType.values) Piece(c, t).label,
      ].join();
      for (final trad in ['帥', '馬', '車', '砲', '將']) {
        expect(
          labels.contains(trad),
          isFalse,
          reason: 'found traditional $trad',
        );
      }
    });

    test('move notation uses simplified characters', () {
      final start = Position.startPosition();
      final n = MoveNotation.toChinese('b0c2', start); // red knight advance
      expect(n.contains('马'), isTrue, reason: 'got $n');
      expect(n.contains('进'), isTrue, reason: 'got $n');
      expect(n.contains('馬'), isFalse);
    });
  });

  group('Score display', () {
    test('red perspective flips sign for black to move', () {
      final info = _line(10, scoreCp: 30, pv: 'h2e2');
      final red = formatScore(
        info,
        sideToMoveIsRed: true,
        redPerspective: true,
      );
      expect(red.text, '+30');
      expect(red.positive, isTrue);

      final black = formatScore(
        info,
        sideToMoveIsRed: false,
        redPerspective: true,
      );
      expect(black.text, '-30');
      expect(black.positive, isFalse);
    });

    test('side-to-move mode leaves the sign unchanged', () {
      final info = _line(10, scoreCp: 30, pv: 'h2e2');
      final black = formatScore(
        info,
        sideToMoveIsRed: false,
        redPerspective: false,
      );
      expect(black.text, '+30');
    });
  });

  group('AnalysisPanel table', () {
    testWidgets('renders header and one row per line', (tester) async {
      final start = Position.startPosition();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPanel(
              lines: [
                AnalysisLine(
                  info: _line(12, scoreCp: 40, pv: 'b0c2 b9c7'),
                  position: start,
                ),
                AnalysisLine(
                  info: _line(10, scoreCp: 25, pv: 'h2e2 h9g7'),
                  position: start,
                ),
              ],
              position: start,
            ),
          ),
        ),
      );

      // Column headers present.
      expect(find.text('Depth'), findsOneWidget);
      expect(find.text('Score'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Line'), findsOneWidget);

      // Both depth rows rendered.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);

      // Newest (deeper) line is above the older one.
      final y12 = tester.getTopLeft(find.text('12')).dy;
      final y10 = tester.getTopLeft(find.text('10')).dy;
      expect(y12, lessThan(y10));
    });

    testWidgets('stale lines render below current and are greyed', (
      tester,
    ) async {
      final start = Position.startPosition();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPanel(
              lines: [
                // Current line at low depth ...
                AnalysisLine(
                  info: _line(6, pv: 'b0c2'),
                  position: start,
                ),
                // ... must still sit above a deeper stale line.
                AnalysisLine(
                  info: _line(20, pv: 'h2e2'),
                  position: start,
                  stale: true,
                ),
              ],
              position: start,
            ),
          ),
        ),
      );

      final y6 = tester.getTopLeft(find.text('6')).dy;
      final y20 = tester.getTopLeft(find.text('20')).dy;
      expect(
        y6,
        lessThan(y20),
        reason: 'current (d6) should be above stale (d20)',
      );

      // The stale row is wrapped in a reduced-opacity widget.
      expect(find.byType(Opacity), findsWidgets);
    });

    testWidgets('shows prompt when empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPanel(position: Position.startPosition()),
          ),
        ),
      );
      expect(find.textContaining('Press Analyze'), findsOneWidget);
    });
  });
}
