import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/engine/search_info.dart';
import 'package:app/models/move_notation.dart';
import 'package:app/models/piece.dart';
import 'package:app/models/position.dart';
import 'package:app/models/settings.dart';
import 'package:app/services/chessdb.dart';
import 'package:app/ui/analysis_panel.dart';
import 'package:app/models/move_rules.dart';
import 'package:app/ui/board_widget.dart';
import 'package:app/ui/engine_output.dart';
import 'package:app/ui/move_list.dart';

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
      // red knight advance
      final n = MoveNotation.toNotation(
        'b0c2',
        start,
        DisplayLanguage.simplified,
      );
      expect(n.contains('马'), isTrue, reason: 'got $n');
      expect(n.contains('进'), isTrue, reason: 'got $n');
      expect(n.contains('馬'), isFalse);
    });
  });

  group('Display language', () {
    test('piece labels vary by language', () {
      const knight = Piece(PieceColor.red, PieceType.knight);
      expect(knight.labelFor(DisplayLanguage.simplified), '马');
      expect(knight.labelFor(DisplayLanguage.traditional), '馬');
      expect(knight.labelFor(DisplayLanguage.english), 'H');
    });

    test('traditional notation uses traditional characters', () {
      final start = Position.startPosition();
      final n = MoveNotation.toNotation(
        'b0c2',
        start,
        DisplayLanguage.traditional,
      );
      expect(n.contains('馬'), isTrue, reason: 'got $n');
      expect(n.contains('進'), isTrue, reason: 'got $n');
    });

    test('english notation is the raw UCI move', () {
      final start = Position.startPosition();
      expect(
        MoveNotation.toNotation('b0c2', start, DisplayLanguage.english),
        'b0c2',
      );
      expect(
        MoveNotation.pvToNotation('b0c2 b9c7', start, DisplayLanguage.english),
        'b0c2 b9c7',
      );
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

    testWidgets('best move and search stats sit below the table', (
      tester,
    ) async {
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
              ],
              bestMove: const BestMove(move: 'b0c2', ponder: 'b9c7'),
              position: start,
            ),
          ),
        ),
      );

      final yRow = tester.getTopLeft(find.text('12')).dy;
      final best = find.textContaining('Best:');
      expect(best, findsOneWidget);
      expect(tester.widget<Text>(best).data, contains('Ponder:'));
      expect(tester.getTopLeft(best).dy, greaterThan(yRow));
      // The stats row is a RichText, so match on its plain text.
      final nps = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('NPS'),
      );
      expect(nps, findsOneWidget);
      expect(tester.getTopLeft(nps).dy, greaterThan(yRow));
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

  group('Settings', () {
    test('defaults to large text with every highlight on', () {
      const d = Settings();
      expect(d.fontSize, FontSizeSetting.large);
      expect(d.fontSize.scale, greaterThan(FontSizeSetting.medium.scale));
      expect(d.highlightLastMove, isTrue);
      expect(d.highlightBestMove, isTrue);
      expect(d.highlightPonderMove, isTrue);
    });

    test('json round-trip preserves the new fields', () {
      const s = Settings(
        fontSize: FontSizeSetting.small,
        highlightLastMove: false,
        highlightBestMove: true,
        highlightPonderMove: false,
      );
      final back = Settings.fromJson(s.toJson());
      expect(back.fontSize, FontSizeSetting.small);
      expect(back.highlightLastMove, isFalse);
      expect(back.highlightBestMove, isTrue);
      expect(back.highlightPonderMove, isFalse);
    });

    test('settings files written before these options keep the defaults', () {
      final s = Settings.fromJson({'theme': 'light'});
      expect(s.theme, ThemeSetting.light);
      expect(s.fontSize, FontSizeSetting.large);
      expect(s.highlightLastMove, isTrue);
      expect(s.highlightPonderMove, isTrue);
    });
  });

  group('Move rules', () {
    /// Builds a position from a sparse map of UCI square -> FEN piece char.
    Position board(
      Map<String, String> pieces, {
      PieceColor side = PieceColor.red,
    }) {
      var pos = Position.empty().withSideToMove(side);
      pieces.forEach((square, fenChar) {
        pos = pos.withPiece(
          Position.uciToSquare(square)!,
          Piece.fromFenChar(fenChar)!,
        );
      });
      return pos;
    }

    bool legal(Position pos, String uci) => MoveRules.isLegal(
      pos,
      Position.uciToSquare(uci.substring(0, 2))!,
      Position.uciToSquare(uci.substring(2))!,
    );

    test(
      'opening knight and cannon moves are legal, backwards pawn is not',
      () {
        final start = Position.startPosition();
        expect(legal(start, 'b0c2'), isTrue); // knight out
        expect(legal(start, 'h2e2'), isTrue); // cannon to the centre file
        expect(legal(start, 'a3a4'), isTrue); // pawn forward
        expect(legal(start, 'a3b3'), isFalse); // no sideways before the river
        expect(legal(start, 'a0a3'), isFalse); // rook blocked by its own pawn
        expect(
          legal(start, 'b9c7'),
          isFalse,
        ); // black may not move on red's turn
      },
    );

    test('knight is blocked by a piece on its leg', () {
      final blocked = board({'b0': 'N', 'b1': 'P'});
      expect(legal(blocked, 'b0c2'), isFalse);
      expect(legal(blocked, 'b0a2'), isFalse);
      // Sideways-first L-shapes are unaffected by that blocker.
      expect(legal(board({'b0': 'N'}), 'b0c2'), isTrue);
    });

    test('elephant needs a clear eye and may not cross the river', () {
      expect(legal(board({'c0': 'B'}), 'c0e2'), isTrue);
      expect(
        legal(board({'c0': 'B', 'd1': 'P'}), 'c0e2'),
        isFalse,
      ); // eye blocked
      expect(legal(board({'c4': 'B'}), 'c4e6'), isFalse); // would cross river
    });

    test('advisor and king stay inside the palace', () {
      expect(legal(board({'d0': 'A'}), 'd0e1'), isTrue);
      expect(legal(board({'d0': 'A'}), 'd0c1'), isFalse); // outside the palace
      expect(legal(board({'e0': 'K'}), 'e0e1'), isTrue);
      expect(legal(board({'e1': 'K'}), 'e1f1'), isTrue);
      expect(legal(board({'e1': 'K'}), 'e1e1'), isFalse);
      expect(legal(board({'f1': 'K'}), 'f1g1'), isFalse); // leaves the palace
    });

    test('cannon captures only over exactly one screen', () {
      // Cannon on e0, screen on e4, black rook on e9.
      final withScreen = board({'e0': 'C', 'e4': 'P', 'e9': 'r'});
      expect(legal(withScreen, 'e0e9'), isTrue);
      expect(legal(withScreen, 'e0e5'), isFalse); // empty square behind screen
      // No screen: it may slide but not capture.
      final noScreen = board({'e0': 'C', 'e9': 'r'});
      expect(legal(noScreen, 'e0e5'), isTrue);
      expect(legal(noScreen, 'e0e9'), isFalse);
      // Two screens block the capture.
      final twoScreens = board({'e0': 'C', 'e3': 'P', 'e4': 'p', 'e9': 'r'});
      expect(legal(twoScreens, 'e0e9'), isFalse);
    });

    test('pawns move sideways only after crossing the river', () {
      expect(legal(board({'a4': 'P'}), 'a4a5'), isTrue);
      expect(legal(board({'a4': 'P'}), 'a4b4'), isFalse);
      expect(legal(board({'a5': 'P'}), 'a5b5'), isTrue);
      expect(legal(board({'a5': 'P'}), 'a5a4'), isFalse); // never backwards
      final black = board({'a5': 'p'}, side: PieceColor.black);
      expect(legal(black, 'a5a4'), isTrue);
      expect(legal(black, 'a5a6'), isFalse);
    });

    test('a move may not expose or leave its own king in check', () {
      // Black rook on e9 pins the red advisor on e1 against the king on e0.
      final pinned = board({'e0': 'K', 'e1': 'A', 'e9': 'r'});
      expect(legal(pinned, 'e1d2'), isFalse);
      expect(MoveRules.isInCheck(pinned, PieceColor.red), isFalse);
      // Removing the blocker leaves the king attacked.
      final exposed = board({'e0': 'K', 'e9': 'r'});
      expect(MoveRules.isInCheck(exposed, PieceColor.red), isTrue);
    });

    test('kings may not face each other down an open file', () {
      // Red king e0, black king e9, one blocker between.
      final blocked = board({'e0': 'K', 'e5': 'P', 'e9': 'k'});
      expect(MoveRules.isInCheck(blocked, PieceColor.red), isFalse);
      expect(legal(blocked, 'e5f5'), isFalse); // stepping aside opens the file
      expect(legal(blocked, 'e5e6'), isTrue); // still on the file, still legal
    });

    test('legalDestinations lists every square a piece can reach', () {
      final lone = board({'e5': 'R'});
      // A rook alone on e5 reaches the whole file and rank: 9 + 8 squares.
      expect(
        MoveRules.legalDestinations(lone, Position.uciToSquare('e5')!).length,
        17,
      );
    });
  });

  group('BoardWidget highlights', () {
    /// Counts squares ringed in [color], the border used by the move
    /// highlights (pieces use red/black borders).
    int ringsOf(WidgetTester tester, Color color) {
      return tester.widgetList<Container>(find.byType(Container)).where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.border?.top.color == color;
      }).length;
    }

    testWidgets('best move is green and the ponder reply blue', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoardWidget(
              position: Position.startPosition(),
              highlightFrom: 1,
              highlightTo: 20,
              ponderFrom: 82,
              ponderTo: 65,
            ),
          ),
        ),
      );
      expect(ringsOf(tester, Colors.green.shade700), 2);
      expect(ringsOf(tester, Colors.blue.shade700), 2);
    });

    testWidgets('omitted squares draw no highlight', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BoardWidget(position: Position.startPosition())),
        ),
      );
      expect(ringsOf(tester, Colors.green.shade700), 0);
      expect(ringsOf(tester, Colors.blue.shade700), 0);
    });
  });

  group('Engine raw output', () {
    test('the log keeps the newest lines once it overflows', () {
      final log = EngineLog(maxLines: 10);
      for (var i = 0; i < 600; i++) {
        log.add('info depth $i');
      }
      expect(log.length, lessThanOrEqualTo(510));
      expect(log.lines.last, 'info depth 599');
      expect(log.droppedCount, greaterThan(0));
      log.clear();
      expect(log.length, 0);
      expect(log.droppedCount, 0);
      log.dispose();
    });

    testWidgets('renders lines newest-last and clears on demand', (
      tester,
    ) async {
      final log = EngineLog()
        ..add('> go infinite')
        ..add('info depth 1 score cp 20 pv b0c2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EngineOutputView(log: log)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('> go infinite'), findsOneWidget);
      expect(find.textContaining('info depth 1'), findsOneWidget);
      // Newest line sits below the older one.
      expect(
        tester.getTopLeft(find.textContaining('info depth 1')).dy,
        greaterThan(tester.getTopLeft(find.text('> go infinite')).dy),
      );

      await tester.tap(find.byTooltip('Clear log'));
      await tester.pump();
      expect(find.textContaining('No engine output'), findsOneWidget);
      log.dispose();
    });

    testWidgets('shows a placeholder while the engine is quiet', (
      tester,
    ) async {
      final log = EngineLog();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EngineOutputView(log: log)),
        ),
      );
      expect(find.textContaining('No engine output'), findsOneWidget);
      log.dispose();
    });
  });

  group('ChessDb parser', () {
    test('parses queryall moves and sorts by score', () {
      const body =
          'move:h2e2,score:6,rank:2,winrate:49.3,note:! (6-00)|'
          'move:b2e2,score:12,rank:2,winrate:52.8,note:! (12-00)';
      final moves = ChessDb.parseResponse(body);
      expect(moves.length, 2);
      // Sorted best-first.
      expect(moves.first.uci, 'b2e2');
      expect(moves.first.score, 12);
      expect(moves.first.winrate, 52.8);
      expect(moves.first.note, contains('12-00'));
    });

    test('returns empty on error/unknown responses', () {
      expect(ChessDb.parseResponse('unknown'), isEmpty);
      expect(ChessDb.parseResponse('invalid board'), isEmpty);
      expect(ChessDb.parseResponse('checkmate'), isEmpty);
      expect(ChessDb.parseResponse(''), isEmpty);
    });
  });

  group('MoveList', () {
    testWidgets('renders numbered moves and navigates on tap', (tester) async {
      final p0 = Position.startPosition();
      final p1 = MoveNotation.applyUciMove(p0, 'b0c2');
      final p2 = MoveNotation.applyUciMove(p1, 'b9c7');
      int? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveList(
              history: [p0, p1, p2],
              currentIndex: 2,
              language: DisplayLanguage.simplified,
              onSelect: (i) => selected = i,
            ),
          ),
        ),
      );

      // First move is numbered "1." and reconstructed as a knight move.
      final firstMove = find.textContaining('1.');
      expect(firstMove, findsOneWidget);
      expect(tester.widget<Text>(firstMove).data, contains('马'));

      // Tapping the first ply navigates to history index 1.
      await tester.tap(firstMove);
      expect(selected, 1);
    });

    testWidgets('shows placeholder with no moves', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveList(
              history: [Position.startPosition()],
              currentIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('No moves'), findsOneWidget);
    });
  });
}
