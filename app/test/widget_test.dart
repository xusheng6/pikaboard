import 'dart:convert';

import 'package:flutter/gestures.dart';
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
import 'package:app/ui/hover_preview.dart';
import 'package:app/ui/engine_output.dart';
import 'package:app/models/game.dart';
import 'package:app/ui/move_table.dart';
import 'package:app/ui/move_tree.dart';
import 'package:app/ui/variation_list.dart';
import 'package:app/ui/score_chart.dart';

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

  group('Stacked pieces', () {
    /// A board holding [count] pieces of one type stacked on file e.
    Position stack(PieceColor colour, PieceType type, List<String> squares) {
      var pos = Position.empty().withSideToMove(colour);
      for (final square in squares) {
        pos = pos.withPiece(Position.uciToSquare(square)!, Piece(colour, type));
      }
      return pos;
    }

    String notate(Position pos, String uci, [DisplayLanguage? lang]) =>
        MoveNotation.toNotation(uci, pos, lang ?? DisplayLanguage.simplified);

    test('the front/back marker comes before the piece', () {
      // Two black pawns on file e: e5 is the front one, e6 behind it.
      final pawns = stack(PieceColor.black, PieceType.pawn, ['e5', 'e6']);
      expect(notate(pawns, 'e5e4'), '前卒进1');
      expect(notate(pawns, 'e6e5'), '后卒进1');

      // And for Red, whose front is up the board.
      final rooks = stack(PieceColor.red, PieceType.rook, ['c3', 'c5']);
      expect(notate(rooks, 'c5c6'), '前车进一');
      expect(notate(rooks, 'c3c4'), '后车进一');
      expect(notate(rooks, 'c5d5'), '前车平六');
    });

    test('three on a file read front, middle, back', () {
      final pawns = stack(PieceColor.red, PieceType.pawn, ['e3', 'e4', 'e5']);
      expect(notate(pawns, 'e5e6'), '前兵进一');
      expect(notate(pawns, 'e4e5'), '中兵进一');
      expect(notate(pawns, 'e3e4'), '后兵进一');
    });

    test('four or more are counted from the front', () {
      final pawns = stack(PieceColor.red, PieceType.pawn, [
        'e2',
        'e3',
        'e4',
        'e5',
      ]);
      expect(notate(pawns, 'e5e6'), '一兵进一');
      expect(notate(pawns, 'e4e5'), '二兵进一');
      expect(notate(pawns, 'e3e4'), '三兵进一');
      expect(notate(pawns, 'e2e3'), '四兵进一');
    });

    test('traditional Chinese uses 後', () {
      final rooks = stack(PieceColor.red, PieceType.rook, ['c3', 'c5']);
      expect(notate(rooks, 'c3c4', DisplayLanguage.traditional), '後車進一');
    });

    test('a lone piece is still named by its file', () {
      final rook = stack(PieceColor.red, PieceType.rook, ['c3']);
      expect(notate(rook, 'c3c4'), '车七进一');
      expect(notate(rook, 'c3d3'), '车七平六');
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

    testWidgets('MultiPV lines are numbered and kept in engine order', (
      tester,
    ) async {
      final start = Position.startPosition();
      SearchInfo line(int depth, int pv, String moves) => SearchInfo(
        depth: depth,
        selDepth: depth,
        multiPV: pv,
        scoreCp: 40 - pv * 10,
        nodes: 1,
        nps: 1,
        timeMs: 1,
        hashfull: 0,
        pv: moves.split(' '),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPanel(
              lines: [
                AnalysisLine(info: line(12, 1, 'h2e2'), position: start),
                AnalysisLine(info: line(12, 2, 'b0c2'), position: start),
                AnalysisLine(info: line(12, 3, 'h0g2'), position: start),
              ],
              position: start,
              showPreview: false,
            ),
          ),
        ),
      );

      // The rank column appears, numbering the alternatives ...
      expect(find.text('#'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // ... and every line is shown rather than collapsing onto one depth.
      expect(find.text('12'), findsNWidgets(3));
      // Engine order is preserved down the table.
      expect(
        tester.getTopLeft(find.text('1')).dy,
        lessThan(tester.getTopLeft(find.text('3')).dy),
      );
    });

    testWidgets('only the latest iteration is drawn at full strength', (
      tester,
    ) async {
      final start = Position.startPosition();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPanel(
              lines: [
                // Latest word ...
                AnalysisLine(
                  info: _line(14, pv: 'h2e2'),
                  position: start,
                ),
                // ... an earlier iteration of the same search ...
                AnalysisLine(
                  info: _line(13, pv: 'h2e2'),
                  position: start,
                ),
                // ... and a line for a position already left behind.
                AnalysisLine(
                  info: _line(20, pv: 'b0c2'),
                  position: start,
                  stale: true,
                ),
              ],
              position: start,
              showPreview: false,
            ),
          ),
        ),
      );

      double opacityAround(String text) {
        final finder = find.ancestor(
          of: find.text(text),
          matching: find.byType(Opacity),
        );
        return finder.evaluate().isEmpty
            ? 1
            : tester.widget<Opacity>(finder.first).opacity;
      }

      expect(opacityAround('14'), 1, reason: 'the latest lines are solid');
      expect(opacityAround('13'), lessThan(1));
      expect(opacityAround('13'), greaterThan(opacityAround('20')));
    });

    testWidgets('a single-line search has no rank column', (tester) async {
      final start = Position.startPosition();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalysisPanel(
              lines: [
                AnalysisLine(
                  info: _line(12, pv: 'h2e2'),
                  position: start,
                ),
              ],
              position: start,
              showPreview: false,
            ),
          ),
        ),
      );
      expect(find.text('#'), findsNothing);
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

    test('the engine line count is kept, and kept sane', () {
      expect(const Settings().multiPv, 1);
      final round = Settings.fromJson(const Settings(multiPv: 4).toJson());
      expect(round.multiPv, 4);
      // A file asking for more lines than the panel can show is clamped.
      expect(Settings.fromJson({'multiPv': 999}).multiPv, 8);
      expect(Settings.fromJson({'multiPv': 0}).multiPv, 1);
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

  group('Board transforms', () {
    test('mirroring swaps files and leaves the side to move alone', () {
      // The opening position is symmetric, so mirroring is a no-op for it.
      final start = Position.startPosition();
      expect(start.mirrored().toFen(), start.toFen());

      // After a one-sided cannon move the mirror image differs.
      final afterMove = MoveNotation.applyUciMove(start, 'h2e2');
      final mirrored = afterMove.mirrored();
      expect(mirrored.toFen(), isNot(afterMove.toFen()));
      expect(mirrored.sideToMove, afterMove.sideToMove);
      // The cannon that stood on b2 is now on h2 and vice versa.
      expect(
        mirrored.pieceAt(Position.uciToSquare('h2')!),
        const Piece(PieceColor.red, PieceType.cannon),
      );
      expect(mirrored.pieceAt(Position.uciToSquare('b2')!), isNull);
      // Mirroring twice is the identity.
      expect(mirrored.mirrored().toFen(), afterMove.toFen());
    });

    test('flipping hands the position to the other side', () {
      final start = Position.startPosition();
      final flipped = start.flipped();
      // The armies swap colours, so the board looks the same but black moves.
      expect(flipped.toFen(), '${Position.startFen.split(' ').first} b');
      expect(flipped.sideToMove, PieceColor.black);

      // A red king on e0 becomes a black king on e9 — still inside a palace.
      final lone = Position.empty().withPiece(
        Position.uciToSquare('e0')!,
        const Piece(PieceColor.red, PieceType.king),
      );
      final loneFlipped = lone.flipped();
      expect(
        loneFlipped.pieceAt(Position.uciToSquare('e9')!),
        const Piece(PieceColor.black, PieceType.king),
      );
      expect(loneFlipped.pieceAt(Position.uciToSquare('e0')!), isNull);
      // Flipping twice is the identity.
      expect(lone.flipped().flipped().toFen(), lone.toFen());
    });

    test('transformed positions stay legal for the engine', () {
      final start = Position.startPosition();
      final afterMove = MoveNotation.applyUciMove(start, 'h2e2');
      // Black's knight move is legal in the mirror image too (mirrored file).
      expect(
        MoveRules.isLegal(
          afterMove.mirrored(),
          Position.uciToSquare('h9')!,
          Position.uciToSquare('g7')!,
        ),
        isTrue,
      );
      // After a flip the same army, now black, still has its opening moves.
      expect(
        MoveRules.isLegal(
          start.flipped(),
          Position.uciToSquare('b9')!,
          Position.uciToSquare('c7')!,
        ),
        isTrue,
      );
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

    test('engine output is matched against the position it claims', () {
      final start = Position.startPosition();
      // A move Red can play here belongs to this position ...
      expect(MoveRules.fitsPosition(start, 'h2e2'), isTrue);
      // ... while Black's reply does not, which is how trailing output from
      // the previous search is spotted before its score flips a sign.
      expect(MoveRules.fitsPosition(start, 'h9g7'), isFalse);
      // Nor does a move that is merely illegal, or malformed.
      expect(MoveRules.fitsPosition(start, 'a0a5'), isFalse);
      expect(MoveRules.fitsPosition(start, 'e4e5'), isFalse);
      expect(MoveRules.fitsPosition(start, 'xx'), isFalse);

      final afterMove = MoveNotation.applyUciMove(start, 'h2e2');
      expect(MoveRules.fitsPosition(afterMove, 'h9g7'), isTrue);
      expect(MoveRules.fitsPosition(afterMove, 'b0c2'), isFalse);
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
    /// Counts move markers drawn in [color]: a ring around an occupied square
    /// or a dot on an empty one (pieces use red/black borders of their own).
    int marksOf(WidgetTester tester, Color color) {
      return tester.widgetList<Container>(find.byType(Container)).where((c) {
        final d = c.decoration;
        if (d is! BoxDecoration) return false;
        return d.border?.top.color == color || d.color == color;
      }).length;
    }

    testWidgets('the last move played gets a ring or a dot', (tester) async {
      final start = Position.startPosition();

      Future<Size> markSize(int square) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BoardWidget(position: start, lastMoveFrom: square),
            ),
          ),
        );
        return tester.getSize(
          find.byWidgetPredicate((w) {
            final d = w is Container ? w.decoration : null;
            return d is BoxDecoration &&
                (d.border?.top.color == Colors.amber.shade700 ||
                    d.color == Colors.amber.shade700);
          }),
        );
      }

      final onPiece = await markSize(1); // b0, a knight
      final onEmpty = await markSize(20); // c2, empty
      // The dot is well inside the piece; the ring hugs its edge.
      expect(onEmpty.width, lessThan(onPiece.width / 2));
    });

    /// The arrows are painted rather than built, so they are located by their
    /// painter instead of by widget type.
    int arrowLayers(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((c) => c.painter.runtimeType.toString() == '_ArrowPainter')
        .length;

    testWidgets('engine moves are drawn as numbered arrows', (tester) async {
      const arrows = [
        BoardArrow(from: 1, to: 20, side: PieceColor.red, label: '1'),
        BoardArrow(from: 82, to: 65, side: PieceColor.black, label: '2'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoardWidget(
              position: Position.startPosition(),
              arrows: arrows,
              lastMoveFrom: 3,
            ),
          ),
        ),
      );

      expect(arrowLayers(tester), 1);
      // The last-move marker is still a widget of its own ...
      expect(marksOf(tester, Colors.amber.shade700), 1);
      // ... while the engine moves no longer add square markers.
      expect(marksOf(tester, Colors.green.shade600), 0);
      expect(marksOf(tester, Colors.blue.shade600), 0);
    });

    testWidgets('arrow equality drives repaints', (tester) async {
      const a = BoardArrow(from: 1, to: 20, side: PieceColor.red, label: '1');
      expect(
        a,
        const BoardArrow(from: 1, to: 20, side: PieceColor.red, label: '1'),
      );
      expect(
        a,
        isNot(
          const BoardArrow(from: 1, to: 20, side: PieceColor.black, label: '1'),
        ),
      );
      expect(
        a,
        isNot(
          const BoardArrow(from: 1, to: 20, side: PieceColor.red, label: '2'),
        ),
      );
    });

    testWidgets('viewFromBlack rotates the drawing, not the position', (
      tester,
    ) async {
      final start = Position.startPosition();

      Future<Offset> kingOffset({required bool flipped}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BoardWidget(position: start, viewFromBlack: flipped),
            ),
          ),
        );
        return tester.getCenter(find.text('帅')); // red king, on e0
      }

      final normal = await kingOffset(flipped: false);
      final rotated = await kingOffset(flipped: true);
      // Red's king moves from the bottom of the board to the top ...
      expect(rotated.dy, lessThan(normal.dy));
      // ... and the files mirror with it, though e is the centre file so its
      // x stays put. Check a corner piece instead.
      final leftRook = tester.getCenter(find.text('车').first);
      expect(leftRook.dx, greaterThan(normal.dx));
    });

    testWidgets('a bare board draws no indicators at all', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BoardWidget(position: Position.startPosition())),
        ),
      );
      expect(marksOf(tester, Colors.amber.shade700), 0);
      expect(arrowLayers(tester), 0);
    });
  });

  group('Score chart', () {
    /// Chart points for a line of scores, with optional labels and moves.
    List<ScorePoint> points(
      List<int?> scores, {
      List<String> labels = const [],
      List<String?> best = const [],
      List<String?> played = const [],
    }) {
      var position = Position.startPosition();
      return [
        for (var i = 0; i < scores.length; i++)
          ScorePoint(
            label: i < labels.length
                ? labels[i]
                : (i == 0 ? 'Start' : 'Ply $i'),
            position: position,
            cp: scores[i],
            bestMoveUci: i < best.length ? best[i] : null,
            bestMoveText: i < best.length && best[i] != null ? 'best$i' : null,
            playedMoveText: i < played.length ? played[i] : null,
            playedCp: i + 1 < scores.length ? scores[i + 1] : null,
          ),
      ];
    }

    test('scores are charted from Red\'s point of view', () {
      final info = _line(12, scoreCp: 40, pv: 'b0c2');
      expect(redCentipawns(info, sideToMoveIsRed: true), 40);
      // The engine scores from the side to move, so black-to-move flips.
      expect(redCentipawns(info, sideToMoveIsRed: false), -40);

      final mate = SearchInfo(
        depth: 20,
        selDepth: 24,
        multiPV: 1,
        scoreMate: 3,
        nodes: 1,
        nps: 1,
        timeMs: 1,
        hashfull: 0,
        pv: const ['b0c2'],
      );
      expect(redCentipawns(mate, sideToMoveIsRed: true), kMateCentipawns);
      expect(redCentipawns(mate, sideToMoveIsRed: false), -kMateCentipawns);

      final noScore = SearchInfo(
        depth: 1,
        selDepth: 1,
        multiPV: 1,
        nodes: 1,
        nps: 1,
        timeMs: 1,
        hashfull: 0,
        pv: const ['b0c2'],
      );
      expect(redCentipawns(noScore, sideToMoveIsRed: true), isNull);
    });

    testWidgets('prompts when nothing has been analysed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChart(points: points([null, null]), currentPly: 0),
          ),
        ),
      );
      expect(find.textContaining('No evaluations yet'), findsOneWidget);
    });

    testWidgets('plots what is known and reports the coverage', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChart(
              points: points([20, null, -140, 65]),
              currentPly: 2,
            ),
          ),
        ),
      );
      expect(find.text('3 of 4 positions'), findsOneWidget);
      // The score at the current ply is called out.
      expect(find.text('-140'), findsOneWidget);
    });

    test('the vertical range grows to fit, and mates do not stretch it', () {
      // A quiet game stays on a tight scale ...
      expect(ScoreChart.rangeFor([20, -35, 48]), 50);
      // ... and the range steps up only as far as it must.
      expect(ScoreChart.rangeFor([20, -120]), 200);
      expect(ScoreChart.rangeFor([20, 250, -80]), 300);
      expect(ScoreChart.rangeFor([1500]), 2000);
      // A forced mate pins to the edge instead of dragging the scale to 20000.
      expect(ScoreChart.rangeFor([20, kMateCentipawns]), 50);
      expect(
        ScoreChart.rangeFor([-kMateCentipawns]),
        ScoreChart.rangeSteps.first,
      );
      // Nothing analysed yet still gives a usable scale.
      expect(ScoreChart.rangeFor([null, null]), ScoreChart.rangeSteps.first);
      // The gutter must be wide enough for the largest label.
      expect(ScoreChart.padding.left, greaterThan(30));
    });

    testWidgets('hovering a point names the move and its exact score', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChart(
              points: points(
                [10, -25, 340],
                labels: ['Start', '1. 炮二平五', '1... 马8进7'],
              ),
              currentPly: 0,
            ),
          ),
        ),
      );

      final chart = find.byType(CustomPaint).last;
      final rect = tester.getRect(chart);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(Offset(rect.right - 16, rect.center.dy));
      await tester.pump();
      expect(find.text('1... 马8进7'), findsOneWidget);
      expect(find.textContaining('+340'), findsWidgets);

      // Moving to another point swaps the readout ...
      await mouse.moveTo(Offset(rect.center.dx, rect.center.dy));
      await tester.pump();
      expect(find.text('1. 炮二平五'), findsOneWidget);
      expect(find.textContaining('-25'), findsWidgets);

      // ... and leaving the chart dismisses it.
      await mouse.moveTo(const Offset(-50, -50));
      await tester.pump();
      expect(find.text('1. 炮二平五'), findsNothing);
    });

    testWidgets('the hover readout previews the board and compares moves', (
      tester,
    ) async {
      // A tall chart, so the preview earns its place.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: ScoreChart(
                points: points(
                  [40, -60, 20],
                  labels: ['Start', '1. 炮二平五', '1... 马8进7'],
                  best: ['h2e2', 'b9c7', null],
                  played: ['炮二平五', '马8进7', null],
                ),
                currentPly: 0,
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(CustomPaint).last);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(Offset(rect.left + 20, rect.center.dy));
      await tester.pump();

      // The engine's move and what was played are labelled apart ...
      expect(find.text('Best'), findsOneWidget);
      expect(find.text('Played'), findsOneWidget);
      expect(find.text('best0'), findsOneWidget);
      expect(find.text('炮二平五'), findsOneWidget);
      // ... with the score each leads to.
      expect(find.text('+40'), findsWidgets);
      expect(find.text('-60'), findsWidgets);
      // A board preview is drawn, with the engine's move on it.
      expect(find.byType(BoardWidget), findsOneWidget);
      final board = tester.widget<BoardWidget>(find.byType(BoardWidget));
      expect(board.arrows, hasLength(1));
      expect(board.arrows.single.side, PieceColor.red);
    });

    testWidgets('the readout stays inside the window, however small', (
      tester,
    ) async {
      // A panel far smaller than the card, so an in-panel card would be cut off.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 200,
                height: 110,
                child: ScoreChart(
                  points: points([40, -60], best: ['h2e2', null]),
                  currentPly: 0,
                ),
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(CustomPaint).last);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // Hover the bottom-right corner: the worst case for placement.
      await mouse.moveTo(Offset(rect.right - 4, rect.bottom - 4));
      await tester.pump();

      final card = find.byType(MovePreviewCard);
      expect(card, findsOneWidget);
      final cardRect = tester.getRect(card);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(cardRect.left, greaterThanOrEqualTo(0));
      expect(cardRect.top, greaterThanOrEqualTo(0));
      expect(cardRect.right, lessThanOrEqualTo(screen.width));
      expect(cardRect.bottom, lessThanOrEqualTo(screen.height));
      // It really is the full card, board and all.
      expect(find.byType(BoardWidget), findsOneWidget);
    });

    testWidgets('previews follow the board when it is viewed from Black', (
      tester,
    ) async {
      // One pointer for both passes: adding a second while the first is still
      // registered upsets the mouse tracker.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      Future<BoardWidget> hoverPreviewBoard({required bool flipped}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScoreChart(
                points: points([40, -60], best: ['h2e2', null]),
                currentPly: 0,
                viewFromBlack: flipped,
              ),
            ),
          ),
        );
        final rect = tester.getRect(find.byType(CustomPaint).last);
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await mouse.moveTo(Offset(rect.left + 10, rect.center.dy));
        await tester.pump();
        return tester.widget<BoardWidget>(find.byType(BoardWidget));
      }

      expect((await hoverPreviewBoard(flipped: false)).viewFromBlack, isFalse);
      expect((await hoverPreviewBoard(flipped: true)).viewFromBlack, isTrue);
    });

    testWidgets('offers whole-game analysis and reports its progress', (
      tester,
    ) async {
      var started = 0, cancelled = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChart(
              points: points([null, null, null]),
              currentPly: 0,
              onAnalyseGame: () => started++,
              onCancelAnalysis: () => cancelled++,
            ),
          ),
        ),
      );

      // With nothing analysed the prompt points at the button, which is there.
      expect(find.textContaining('No evaluations yet'), findsOneWidget);
      expect(find.byTooltip('Analyse the whole game'), findsOneWidget);
      await tester.tap(find.byTooltip('Analyse the whole game'));
      expect(started, 1);

      // While running it shows progress and offers to stop instead.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChart(
              points: points([12, null, null]),
              currentPly: 0,
              onAnalyseGame: () => started++,
              onCancelAnalysis: () => cancelled++,
              analysedCount: 1,
              analysisTotal: 3,
            ),
          ),
        ),
      );
      expect(find.text('analysing 1 of 3'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Analyse the whole game'), findsNothing);
      await tester.tap(find.byTooltip('Stop analysing'));
      expect(cancelled, 1);
    });

    testWidgets('tapping the chart jumps to that ply', (tester) async {
      var selected = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScoreChart(
              points: points([0, 50, 100, 150, 200]),
              currentPly: 0,
              onSelect: (ply) => selected = ply,
            ),
          ),
        ),
      );

      final chart = find.byType(CustomPaint).last;
      final rect = tester.getRect(chart);
      await tester.tapAt(Offset(rect.right - 14, rect.center.dy));
      expect(selected, 4, reason: 'a tap at the right edge is the last ply');

      await tester.tapAt(Offset(rect.left + 14, rect.center.dy));
      expect(selected, 0);
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

    testWidgets('log text follows the font size setting', (tester) async {
      final log = EngineLog()..add('info depth 12 pv b0c2');

      Future<double> heightAt(double scale) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: EngineOutputView(log: log)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        return tester.getSize(find.text('info depth 12 pv b0c2')).height;
      }

      final small = await heightAt(1.0);
      final large = await heightAt(2.0);
      expect(large, greaterThan(small));
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

  group('Game tree', () {
    test('replaying a move reuses its node, a new move branches', () {
      final game = Game.fromPosition(Position.startPosition());
      final first = game.root.addMove('b0c2');
      expect(identical(game.root.addMove('b0c2'), first), isTrue);
      expect(game.root.children.length, 1);

      final alternative = game.root.addMove('h2e2');
      expect(game.root.children.length, 2);
      expect(first.isMainline, isTrue);
      expect(alternative.isMainline, isFalse);

      // Promoting swaps which line the game reads through.
      alternative.promote();
      expect(alternative.isMainline, isTrue);
      expect(first.isMainline, isFalse);

      // Deleting detaches the subtree.
      alternative.remove();
      expect(game.root.children.length, 1);
      expect(game.root.children.single, first);
    });

    test(
      'the line through a node covers the whole game, not just its past',
      () {
        final game = Game.fromMoves(Position.startPosition(), [
          'h2e2',
          'h9g7',
          'b0c2',
          'b9c7',
        ]);
        final middle = game.root.children.first.children.first;

        // The chart plots this: a fixed-length line the cursor slides along,
        // rather than only the moves played so far.
        final line = middle.mainlineEnd.pathFromRoot;
        expect(line.length, 5); // root plus four moves
        expect(line[middle.ply], middle);
        expect(line.first.isRoot, isTrue);
        expect(line.last.children, isEmpty);

        // It stays the same length wherever you stand on that line.
        expect(game.root.mainlineEnd.pathFromRoot.length, line.length);
        expect(line.last.mainlineEnd.pathFromRoot.length, line.length);
      },
    );

    test('nodes know their ply, move number and side', () {
      final game = Game.fromMoves(Position.startPosition(), [
        'b0c2',
        'b9c7',
        'h2e2',
      ]);
      final path = game.root.mainlineEnd.pathFromRoot;
      expect(path.length, 4);
      expect(path.first.isRoot, isTrue);
      expect(path[1].ply, 1);
      expect(path[1].moveNumber, 1);
      expect(path[1].isRedMove, isTrue);
      expect(path[2].moveNumber, 1);
      expect(path[2].isRedMove, isFalse);
      expect(path[3].moveNumber, 2);
      expect(game.mainlineLength, 3);
    });

    test('a game round-trips through json with its branches and notes', () {
      final game = Game.fromMoves(Position.startPosition(), ['b0c2', 'b9c7']);
      game.root.children.first.comment = 'Knight out';
      game.root.addMove('h2e2').comment = 'Central cannon instead';
      game.metadata
        ..title = '测试对局'
        ..red = 'Red'
        ..black = 'Black'
        ..result = GameResult.draw;

      final restored = Game.fromJson(
        jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>,
      );
      expect(restored.initialPosition.toFen(), game.initialPosition.toFen());
      expect(restored.metadata.title, '测试对局');
      expect(restored.metadata.result, GameResult.draw);
      expect(restored.root.children.length, 2);
      expect(restored.root.children.first.comment, 'Knight out');
      expect(restored.root.children[1].comment, 'Central cannon instead');
      // Positions are replayed, not stored.
      expect(
        restored.root.mainlineEnd.position.toFen(),
        game.root.mainlineEnd.position.toFen(),
      );
    });
  });

  group('MoveTable', () {
    Game sampleGame() => Game.fromMoves(Position.startPosition(), [
      'h2e2',
      'h9g7',
      'b0c2',
      'b9c7',
      'h0g2',
    ]);

    testWidgets('pairs Red and Black on one numbered line', (tester) async {
      final game = sampleGame();
      final line = game.root.mainlineEnd.pathFromRoot;
      GameNode? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveTable(
              line: line,
              current: line[3],
              onSelect: (node) => selected = node,
              showPreview: false,
            ),
          ),
        ),
      );

      // Three numbered rows for five moves.
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsNothing);
      expect(find.text('3/5'), findsOneWidget); // third move of five

      // Red and Black of move 1 sit on the same row, Red on the left.
      final red = tester.getCenter(find.text('炮二平五'));
      final black = tester.getCenter(find.text('马8进7'));
      expect(red.dy, black.dy);
      expect(red.dx, lessThan(black.dx));

      await tester.tap(find.text('马8进7'));
      expect(selected, line[2]);
    });

    testWidgets('flags moves that carry a note or a branch', (tester) async {
      final game = sampleGame();
      game.root.children.first.comment = 'central cannon';
      game.root.addMove('b0c2'); // an alternative first move
      final line = game.root.mainlineEnd.pathFromRoot;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveTable(
              line: line,
              current: game.root,
              onSelect: (_) {},
              showPreview: false,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
      expect(find.byIcon(Icons.call_split), findsOneWidget);
    });
  });

  group('VariationList', () {
    testWidgets('lists continuations and alternatives, and switches lines', (
      tester,
    ) async {
      final game = Game.fromMoves(Position.startPosition(), ['h2e2', 'h9g7']);
      final first = game.root.children.first;
      final alternative = game.root.addMove('b0c2');
      first.addMove('b0c2'); // a second continuation after 1. 炮二平五
      GameNode? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VariationList(
              current: first,
              onSelect: (node) => selected = node,
            ),
          ),
        ),
      );

      expect(find.text('Continues with'), findsOneWidget);
      expect(find.text('Instead of this move'), findsOneWidget);
      // Both continuations and the alternative first move are offered.
      expect(find.textContaining('1... 马8进7'), findsOneWidget);
      expect(find.textContaining('1. 马八进七'), findsOneWidget);

      await tester.tap(find.textContaining('1. 马八进七'));
      expect(selected, alternative);
    });

    testWidgets('says so when there is nothing to branch to', (tester) async {
      final game = Game.fromPosition(Position.startPosition());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VariationList(current: game.root, onSelect: (_) {}),
          ),
        ),
      );
      expect(find.textContaining('No branches here'), findsOneWidget);
    });
  });

  group('MoveTree', () {
    testWidgets('previews follow the board orientation and can be turned off', (
      tester,
    ) async {
      final game = Game.fromMoves(Position.startPosition(), ['h2e2']);

      Future<void> pump({
        required bool flipped,
        required bool showPreview,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MoveTree(
                game: game,
                current: game.root,
                onSelect: (_) {},
                showPreview: showPreview,
                viewFromBlack: flipped,
              ),
            ),
          ),
        );
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await pump(flipped: true, showPreview: true);
      await mouse.moveTo(tester.getCenter(find.textContaining('1.')));
      await tester.pump();
      expect(find.byType(MovePreviewCard), findsOneWidget);
      expect(
        tester.widget<BoardWidget>(find.byType(BoardWidget)).viewFromBlack,
        isTrue,
      );

      // Turning the preview off leaves the move alone.
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await pump(flipped: true, showPreview: false);
      await mouse.moveTo(tester.getCenter(find.textContaining('1.')));
      await tester.pump();
      expect(find.byType(MovePreviewCard), findsNothing);
    });

    testWidgets('renders numbered moves and selects on tap', (tester) async {
      final game = Game.fromMoves(Position.startPosition(), ['b0c2', 'b9c7']);
      GameNode? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveTree(
              game: game,
              current: game.root.mainlineEnd,
              language: DisplayLanguage.simplified,
              onSelect: (node) => selected = node,
            ),
          ),
        ),
      );

      final firstMove = find.textContaining('1.');
      expect(firstMove, findsOneWidget);
      expect(tester.widget<Text>(firstMove).data, contains('马'));

      await tester.tap(firstMove);
      expect(selected, game.root.children.first);
    });

    testWidgets('variations are shown indented under the move they replace', (
      tester,
    ) async {
      final game = Game.fromMoves(Position.startPosition(), ['b0c2', 'b9c7']);
      final variation = game.root.addMove('h2e2');
      variation.addMove('h9g7');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveTree(game: game, current: game.root, onSelect: (_) {}),
          ),
        ),
      );

      // Both the main line's first move and its alternative are on screen ...
      final mainline = find.textContaining('1. 马');
      final alternative = find.textContaining('1. 炮');
      expect(mainline, findsOneWidget);
      expect(alternative, findsOneWidget);
      // ... with the variation indented to the right of the main line.
      expect(
        tester.getTopLeft(alternative).dx,
        greaterThan(tester.getTopLeft(mainline).dx),
      );
    });

    testWidgets('annotated moves are flagged', (tester) async {
      final game = Game.fromMoves(Position.startPosition(), ['b0c2']);
      game.root.children.first.comment = 'good';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveTree(game: game, current: game.root, onSelect: (_) {}),
          ),
        ),
      );
      expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
    });

    testWidgets('shows placeholder with no moves', (tester) async {
      final game = Game.fromPosition(Position.startPosition());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoveTree(game: game, current: game.root, onSelect: (_) {}),
          ),
        ),
      );
      expect(find.textContaining('No moves'), findsOneWidget);
    });
  });
}
