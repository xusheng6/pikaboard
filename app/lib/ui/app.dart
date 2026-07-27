import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../formats/game_export.dart';
import '../formats/game_io.dart';
import '../engine/pikafish_engine.dart';
import '../engine/search_info.dart';
import '../models/explored_line.dart';
import '../models/game.dart';
import '../models/move_notation.dart';
import '../models/move_rules.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';
import '../models/settings_store.dart';
import 'board_widget.dart';
import 'analysis_panel.dart';
import 'candidate_moves.dart';
import 'engine_output.dart';
import 'move_table.dart';
import 'move_tree.dart';
import 'notes_panel.dart';
import 'piece_palette.dart';
import 'score_chart.dart';
import 'settings_page.dart';
import 'variation_list.dart';

class PikaboardApp extends StatefulWidget {
  const PikaboardApp({super.key});

  @override
  State<PikaboardApp> createState() => _PikaboardAppState();
}

class _PikaboardAppState extends State<PikaboardApp> {
  Settings _settings = const Settings();

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  void _update(Settings next) {
    setState(() => _settings = next);
    SettingsStore.save(next);
  }

  ThemeMode get _themeMode {
    switch (_settings.theme) {
      case ThemeSetting.light:
        return ThemeMode.light;
      case ThemeSetting.dark:
        return ThemeMode.dark;
      case ThemeSetting.auto:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pikaboard',
      theme: ThemeData(
        colorSchemeSeed: Colors.red.shade800,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.red.shade800,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      // Apply the font-size preference to every route, including settings.
      builder: (context, child) {
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: _settings.fontSize.scale,
          maxScaleFactor: _settings.fontSize.scale,
          child: child!,
        );
      },
      home: PikaboardScreen(settings: _settings, onSettingsChanged: _update),
    );
  }
}

class PikaboardScreen extends StatefulWidget {
  final Settings settings;
  final ValueChanged<Settings> onSettingsChanged;

  const PikaboardScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<PikaboardScreen> createState() => _PikaboardScreenState();
}

class _PikaboardScreenState extends State<PikaboardScreen> {
  final _engine = PikafishEngine();
  final _fenController = TextEditingController();

  // Everything the engine says, shown verbatim in the Raw tab.
  final _engineLog = EngineLog();

  // The game being studied and the node currently on the board. Every line
  // ever played is kept, so stepping back and playing something else records a
  // variation rather than discarding what was there.
  late Game _game;
  late GameNode _current;

  Position get _position => _current.position;

  /// Root-first nodes leading to the position on the board.
  List<GameNode> get _path => _current.pathFromRoot;

  /// The whole line the board is on, start to finish.
  ///
  /// The score chart plots this rather than just the moves played so far, so
  /// stepping through the game slides the cursor along a fixed graph instead
  /// of redrawing a shorter one each time.
  List<GameNode> get _line => _current.mainlineEnd.pathFromRoot;

  int? _selectedSquare;
  bool _isAnalyzing = false;
  bool _engineReady = false;
  bool _restartPending = false; // true when stop() is called for a restart

  // Bumped per restart so an older one cannot resume over a newer one.
  int _searchGeneration = 0;
  bool _isSetupMode = false;

  // View-only board rotation; leaves the position untouched.
  bool _viewFromBlack = false;

  // The piece armed from the palette while editing; the next square tapped
  // receives it.
  Piece? _palettePiece;

  // An engine line being walked through. Nothing is recorded while it is set;
  // the game is exactly where it was when the line was picked up.
  ExploredLine? _exploring;

  // The node the walked line branches from, when the game has one to graft it
  // onto.
  GameNode? _exploreAnchor;

  // The search result the walked line came from, for its depth and score.
  SearchInfo? _exploringInfo;

  // Where the game was loaded from or last saved to, when that is a file we
  // can write back to.
  String? _currentFilePath;

  // True while a file is being dragged over the window.
  bool _dragging = false;

  // Whole-game analysis: how far it has got, and how to stop it.
  int? _batchDone;
  int? _batchTotal;
  bool _batchCancelled = false;

  /// Seconds the engine gets per position; remembered between runs.
  int _secondsPerMove = 3;

  BestMove? _latestBestMove;

  // The position the engine is currently searching. Search output is tied to
  // this so its moves render in the right notation and so lines can be marked
  // stale once the board moves on.
  Position? _enginePosition;

  // Current search lines, keyed by the iteration and the line number within
  // it, so each row is the latest word on that line and MultiPV searches keep
  // their alternatives apart instead of overwriting one another.
  final Map<({int depth, int multiPv}), SearchInfo> _curLines = {};

  // Lines from the previous searched position, shown greyed below the current
  // ones until the next hard reset.
  List<AnalysisLine> _staleLines = [];

  // Evaluations collected while analysing, keyed by FEN so they survive moving
  // back and forth through the game. Feeds the score chart.
  final Map<String, ScoreSample> _evalByFen = {};

  /// What the score chart plots: every position on the line, its score, and
  /// what the engine wanted there against what was actually played.
  List<ScorePoint> get _scorePoints {
    final line = _line;
    final language = widget.settings.language;
    return [
      for (var i = 0; i < line.length; i++)
        () {
          final node = line[i];
          final sample = _evalByFen[node.position.toFen()];
          final next = i + 1 < line.length ? line[i + 1] : null;
          final best = sample?.bestMove;
          return ScorePoint(
            label: node.parent == null || node.move == null
                ? 'Start'
                : '${node.moveNumber}${node.isRedMove ? '.' : '...'} '
                      '${MoveNotation.toNotation(node.move!, node.parent!.position, language)}',
            position: node.position,
            cp: sample?.cp,
            depth: sample?.depth,
            bestMoveUci: best,
            bestMoveText: best == null
                ? null
                : MoveNotation.toNotation(best, node.position, language),
            playedMoveText: next?.move == null
                ? null
                : MoveNotation.toNotation(next!.move!, node.position, language),
            playedCp: next == null
                ? null
                : _evalByFen[next.position.toFen()]?.cp,
          );
        }(),
    ];
  }

  /// Rows for the analysis table: current-position lines (deepest on top)
  /// first, then any stale previous-position lines.
  List<AnalysisLine> get _analysisLines {
    final enginePos = _enginePosition;
    // If the board has moved on without a running search, the current lines
    // describe a previous position too.
    final curStale =
        enginePos == null || enginePos.toFen() != _position.toFen();
    final cur = (_curLines.values.toList()..sort(_deepestFirst)).map(
      (info) => AnalysisLine(
        info: info,
        position: enginePos ?? _position,
        stale: curStale,
      ),
    );
    return [...cur, ..._staleLines];
  }

  /// Deepest iteration first, and within an iteration the engine's own
  /// ordering: line 1 is the move it would play.
  static int _deepestFirst(SearchInfo a, SearchInfo b) {
    final byDepth = b.depth.compareTo(a.depth);
    return byDepth != 0 ? byDepth : a.multiPV.compareTo(b.multiPV);
  }

  /// Remember [info]'s score for the position being searched, keeping the
  /// deepest result per position so the chart settles rather than flickers.
  void _recordEval(SearchInfo info) {
    final searched = _enginePosition;
    if (searched == null) return;
    final cp = redCentipawns(
      info,
      sideToMoveIsRed: searched.sideToMove == PieceColor.red,
    );
    if (cp == null) return;
    final fen = searched.toFen();
    final previous = _evalByFen[fen];
    if (previous == null || info.depth >= previous.depth) {
      _evalByFen[fen] = ScoreSample(
        cp: cp,
        depth: info.depth,
        bestMove: info.pv.isEmpty ? previous?.bestMove : info.pv.first,
      );
    }
  }

  /// Send [pos] to the engine and start an infinite search, demoting the
  /// previous search's lines to the greyed stale list.
  void _startEngineSearch(Position pos) {
    if (_curLines.isNotEmpty && _enginePosition != null) {
      _staleLines =
          _curLines.values
              .map(
                (info) => AnalysisLine(
                  info: info,
                  position: _enginePosition!,
                  stale: true,
                ),
              )
              .toList()
            ..sort((a, b) => _deepestFirst(a.info, b.info));
    }
    _curLines.clear();
    _enginePosition = pos;
    _engine.setOption('MultiPV', '${widget.settings.multiPv}');
    _engine.setPosition(pos.toFen());
    _engine.goInfinite();
  }

  StreamSubscription<SearchInfo>? _infoSub;
  StreamSubscription<BestMove>? _bestMoveSub;
  StreamSubscription<String>? _rawSub;

  // Engine's best move and the opponent's best reply (the ponder move), in
  // UCI. Both come from the running search's PV and are refreshed by the final
  // bestmove; the board highlights derive from them.
  String? _bestUci;
  String? _ponderUci;

  static int? _uciSquare(String? uci, int offset) {
    if (uci == null || uci.length < offset + 2) return null;
    return Position.uciToSquare(uci.substring(offset, offset + 2));
  }

  int? get _bestMoveFrom => _uciSquare(_bestUci, 0);
  int? get _bestMoveTo => _uciSquare(_bestUci, 2);
  int? get _ponderMoveFrom => _uciSquare(_ponderUci, 0);
  int? get _ponderMoveTo => _uciSquare(_ponderUci, 2);

  /// The engine's current candidates, best first: the deepest line reported
  /// for each MultiPV rank.
  List<SearchInfo> get _candidateLines {
    final byRank = <int, SearchInfo>{};
    for (final info in _curLines.values) {
      if (info.pv.isEmpty) continue;
      final best = byRank[info.multiPV];
      if (best == null || info.depth > best.depth) byRank[info.multiPV] = info;
    }
    final ranks = byRank.keys.toList()..sort();
    return [for (final rank in ranks) byRank[rank]!];
  }

  /// What the board draws over the pieces.
  ///
  /// Searching a single line, that is the move to play and the reply expected
  /// after it. Asked for several lines, the reply matters less than the
  /// alternatives, so each candidate is drawn instead — numbered by rank, with
  /// everything behind the engine's choice drawn back.
  List<BoardArrow> get _boardArrows {
    final settings = widget.settings;

    // Walking a line, the engine's candidates belong to another position
    // entirely; all that is worth drawing is where this line goes next, and
    // numbering that would suggest a ranking it does not have.
    final exploring = _exploring;
    if (exploring != null) {
      final next = exploring.nextMove;
      final from = _uciSquare(next, 0);
      final to = _uciSquare(next, 2);
      if (from == null || to == null) return const [];
      return [
        BoardArrow(
          from: from,
          to: to,
          side: exploring.position.sideToMove,
          label: '',
        ),
      ];
    }

    final sideToMove = (_enginePosition ?? _position).sideToMove;

    if (settings.multiPv > 1) {
      if (!settings.highlightBestMove) return const [];
      final candidates = _candidateLines;
      return [
        for (var i = 0; i < candidates.length; i++)
          if (_uciSquare(candidates[i].pv.first, 0) != null &&
              _uciSquare(candidates[i].pv.first, 2) != null)
            BoardArrow(
              from: _uciSquare(candidates[i].pv.first, 0)!,
              to: _uciSquare(candidates[i].pv.first, 2)!,
              side: sideToMove,
              label: '${i + 1}',
              strength: i == 0 ? 1 : 0.5,
            ),
      ];
    }

    final opponent = sideToMove == PieceColor.red
        ? PieceColor.black
        : PieceColor.red;
    return [
      if (settings.highlightBestMove &&
          _bestMoveFrom != null &&
          _bestMoveTo != null)
        BoardArrow(
          from: _bestMoveFrom!,
          to: _bestMoveTo!,
          side: sideToMove,
          label: '1',
        ),
      if (settings.highlightPonderMove &&
          _ponderMoveFrom != null &&
          _ponderMoveTo != null)
        BoardArrow(
          from: _ponderMoveFrom!,
          to: _ponderMoveTo!,
          side: opponent,
          label: '2',
        ),
    ];
  }

  /// True when the engine's output describes the position currently shown.
  bool get _engineMatchesBoard =>
      _enginePosition != null && _enginePosition!.toFen() == _position.toFen();

  /// True when the engine's best move can be played on the board shown, i.e.
  /// the search that produced it was for this exact position.
  bool get _canPlayBestMove =>
      _bestUci != null && !_isSetupMode && _engineMatchesBoard;

  void _playBestMove() {
    if (!_canPlayBestMove) return;
    _playUci(_bestUci!);
  }

  // For highlighting the last move played
  int? _lastMoveFrom;
  int? _lastMoveTo;

  @override
  void initState() {
    super.initState();
    _loadGame(Game.fromPosition(Position.startPosition()));
    _initFilePicker();
    _initEngine();
  }

  /// The macOS build runs unsandboxed (it spawns the engine), so the picker's
  /// entitlement check has to be waived or it refuses to open.
  Future<void> _initFilePicker() async {
    if (!Platform.isMacOS) return;
    try {
      await FilePicker.skipEntitlementsChecks();
    } catch (_) {
      // Older plugin versions do not need this; carry on.
    }
  }

  Future<void> _initEngine() async {
    try {
      // Subscribe first so the startup handshake shows up in the log too.
      _rawSub = _engine.rawOutput.listen(_engineLog.add);
      await _engine.init();
      _infoSub = _engine.searchInfo.listen((info) {
        // Drop trailing output from a search that was stopped for a restart,
        // so old high-depth lines don't leak into the new position's table.
        if (_restartPending) return;
        // A search's last lines can arrive after the next one has started. If
        // the line cannot be played here it belongs to a position we have
        // moved on from, and crediting it would flip the score's sign.
        final searched = _enginePosition;
        if (searched != null &&
            info.pv.isNotEmpty &&
            !MoveRules.fitsPosition(searched, info.pv.first)) {
          return;
        }
        setState(() {
          if (info.pv.isNotEmpty) {
            _curLines[(depth: info.depth, multiPv: info.multiPV)] = info;
            // Only the first line is the engine's actual choice, so the board
            // arrows and the recorded score follow that one alone.
            if (info.multiPV <= 1) {
              // The PV's first two plies are the best move and the best reply.
              _bestUci = info.pv.first;
              _ponderUci = info.pv.length > 1 ? info.pv[1] : null;
            }
          }
          if (info.multiPV <= 1) _recordEval(info);
        });
      });
      _bestMoveSub = _engine.bestMove.listen((bm) {
        if (_restartPending) return; // ignore bestmove from a stop-for-restart
        setState(() {
          _latestBestMove = bm;
          _bestUci = bm.move;
          _ponderUci = bm.ponder;
          _isAnalyzing = false;
        });
      });
      setState(() => _engineReady = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Engine init failed: $e')));
      }
    }
  }

  @override
  void didUpdateWidget(PikaboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new line count only reaches the engine between searches, so restart
    // one that is already running.
    if (oldWidget.settings.multiPv != widget.settings.multiPv) {
      // Rows from the old count describe a different search; keeping them
      // would leave the rank column behind after going back to one line.
      setState(() {
        _curLines.clear();
        _staleLines = [];
      });
      if (_isAnalyzing) _restartSearch(_position);
    }
  }

  @override
  void dispose() {
    _infoSub?.cancel();
    _bestMoveSub?.cancel();
    _rawSub?.cancel();
    _engine.dispose();
    _engineLog.dispose();
    _fenController.dispose();
    super.dispose();
  }

  void _onSquareTap(int square) {
    if (_isSetupMode) {
      _handleSetupTap(square);
      return;
    }

    setState(() {
      if (_selectedSquare == null) {
        // Select a piece belonging to the side to move
        final piece = _position.pieceAt(square);
        if (piece != null && piece.color == _position.sideToMove) {
          _selectedSquare = square;
        }
      } else if (_selectedSquare == square) {
        // Deselect
        _selectedSquare = null;
      } else {
        // Check if tapping another piece of the same color — switch selection
        final targetPiece = _position.pieceAt(square);
        if (targetPiece != null && targetPiece.color == _position.sideToMove) {
          _selectedSquare = square;
          return;
        }

        // Move piece. A move rejected as illegal keeps the piece selected so
        // another destination can be tried.
        final piece = _position.pieceAt(_selectedSquare!);
        if (piece == null || _makeMove(_selectedSquare!, square)) {
          _selectedSquare = null;
        }
      }
    });
  }

  /// Execute a move on the board, update history, and restart engine if
  /// analyzing. Returns false when the move was rejected as illegal.
  bool _makeMove(int from, int to) {
    final piece = _position.pieceAt(from);
    if (piece == null) return false;

    // Setup mode edits the board freely, so the rules only apply to play.
    if (widget.settings.enforceRules &&
        !_isSetupMode &&
        !MoveRules.isLegal(_position, from, to)) {
      return false;
    }

    // Recording rather than truncating: a different move here becomes a
    // variation, and replaying a known move just walks back into it.
    final uci = '${Position.squareToUci(from)}${Position.squareToUci(to)}';
    _current = _current.addMove(uci);
    final newPos = _current.position;
    _fenController.text = newPos.toFen();
    _lastMoveFrom = from;
    _lastMoveTo = to;

    // If engine is analyzing, restart analysis on the new position. The old
    // lines stay visible (greyed, since the board no longer matches the engine
    // position) until the new search demotes them to the stale list.
    if (_isAnalyzing) {
      _latestBestMove = null;
      _bestUci = null;
      _ponderUci = null;
      _restartSearch(newPos);
    } else {
      _bestUci = null;
      _ponderUci = null;
    }
    return true;
  }

  bool get _canGoBack => _current.parent != null;
  bool get _canGoForward => _current.children.isNotEmpty;

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _current = _current.parent!;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      _current = _current.children.first;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  void _goToStart() {
    if (_current.isRoot) return;
    setState(() {
      _current = _game.root;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _lastMoveFrom = null;
      _lastMoveTo = null;
      _restartAnalysisIfNeeded();
    });
  }

  void _goToEnd() {
    if (_current.children.isEmpty) return;
    setState(() {
      _current = _current.mainlineEnd;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  /// Play a move given in UCI form (e.g. from a cloud candidate).
  void _playUci(String uci) {
    if (_isSetupMode || uci.length < 4) return;
    final from = Position.uciToSquare(uci.substring(0, 2));
    final to = Position.uciToSquare(uci.substring(2, 4));
    if (from == null || to == null) return;
    if (_position.pieceAt(from) == null) return;
    setState(() {
      _makeMove(from, to);
      _selectedSquare = null;
    });
  }

  /// Show [node] on the board.
  void _goToNode(GameNode node) {
    if (identical(node, _current)) return;
    setState(() {
      _current = node;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  /// Jump to a ply on the current line, used by the score chart.
  void _goToPly(int ply) {
    final line = _line;
    if (ply < 0 || ply >= line.length) return;
    _goToNode(line[ply]);
  }

  /// Drop [node] and everything after it, falling back to its parent.
  void _deleteNode(GameNode node) {
    if (node.isRoot) return;
    final parent = node.parent!;
    setState(() {
      if (_path.contains(node)) _current = parent;
      node.remove();
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  /// Make [node] the main line at its branch point.
  void _promoteNode(GameNode node) {
    setState(() => node.promote());
  }

  /// Highlight the move that led to the node on the board.
  void _updateLastMoveHighlight() {
    final move = _current.move;
    _lastMoveFrom = _uciSquare(move, 0);
    _lastMoveTo = _uciSquare(move, 2);
  }

  /// If analyzing, restart analysis on the current position.
  void _restartAnalysisIfNeeded() {
    if (!_isAnalyzing) {
      _bestUci = null;
      _ponderUci = null;
      return;
    }
    _latestBestMove = null;
    _bestUci = null;
    _ponderUci = null;
    _restartSearch(_position);
  }

  /// Point the running search at [target].
  ///
  /// Waits for the stopped search to report its bestmove — UCI's guarantee
  /// that nothing more is coming — rather than guessing with a timer, so its
  /// trailing lines cannot be credited to the new position.
  Future<void> _restartSearch(Position target) async {
    final generation = ++_searchGeneration;
    _restartPending = true;
    _engine.stop();
    await _engine.bestMove.first.timeout(
      const Duration(seconds: 3),
      onTimeout: () => const BestMove(move: ''),
    );
    // A newer restart took over while waiting.
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _restartPending = false;
      _startEngineSearch(target);
    });
  }

  /// Setup edits rewrite the position itself, so the edited board becomes the
  /// new starting point; any moves recorded from the old one are dropped.
  void _replaceCurrentPosition(Position pos) {
    final wasEditing = _isSetupMode;
    final armed = _palettePiece;
    _loadGame(Game.fromPosition(pos, metadata: _game.metadata));
    // Loading a game leaves editing; an edit should not.
    _isSetupMode = wasEditing;
    _palettePiece = armed;
  }

  /// Show [game] from its root, clearing everything tied to the old one.
  void _loadGame(Game game) {
    _game = game;
    _current = game.root;
    _fenController.text = _position.toFen();
    _selectedSquare = null;
    _palettePiece = null;
    _isSetupMode = false;
    _latestBestMove = null;
    _curLines.clear();
    _staleLines = [];
    // A different game means a different graph.
    _evalByFen.clear();
    _enginePosition = null;
    _bestUci = null;
    _ponderUci = null;
    _lastMoveFrom = null;
    _lastMoveTo = null;
  }

  /// Editing taps: place the armed piece, move the selected one, or select
  /// what was tapped.
  void _handleSetupTap(int square) {
    setState(() {
      final armed = _palettePiece;
      if (armed != null) {
        // An occupied square is not a place to drop a piece: select what is
        // standing there instead, so nothing is overwritten by accident.
        if (_position.pieceAt(square) != null) {
          _palettePiece = null;
          _selectedSquare = square;
          return;
        }
        // Placing stays armed, so a rank of pawns is a rank of taps.
        _replaceCurrentPosition(_position.withPiece(square, armed));
        _selectedSquare = null;
        return;
      }

      final selected = _selectedSquare;
      if (selected != null && selected != square) {
        final moving = _position.pieceAt(selected);
        if (moving != null) {
          _replaceCurrentPosition(
            _position.withPiece(selected, null).withPiece(square, moving),
          );
        }
        _selectedSquare = null;
        return;
      }

      // Tapping the selected piece again, or an empty square, just changes
      // what is selected.
      _selectedSquare = selected == square || _position.pieceAt(square) == null
          ? null
          : square;
    });
  }

  /// Right-click or long-press while editing empties a square.
  void _handleSetupSecondaryTap(int square) {
    if (!_isSetupMode || _position.pieceAt(square) == null) return;
    setState(() {
      _replaceCurrentPosition(_position.withPiece(square, null));
      if (_selectedSquare == square) _selectedSquare = null;
    });
  }

  /// Empty the selected square, for people who would rather press a button
  /// than right-click.
  void _deleteSelectedPiece() {
    final square = _selectedSquare;
    if (square == null) return;
    _handleSetupSecondaryTap(square);
  }

  /// Walk [moves] from [from], stopping [ply] moves in.
  ///
  /// The moves are copied rather than followed live: the engine rewrites its
  /// line as it searches, and reading a line that moves underfoot is worse
  /// than useless.
  void _exploreLine(SearchInfo info, Position from, int ply) {
    setState(() {
      _exploringInfo = info;
      _exploring = ExploredLine(
        start: from,
        moves: List<String>.unmodifiable(info.pv),
        index: ply,
      );
      // Only a node standing on the searched position can hold this line.
      _exploreAnchor = _current.position.toFen() == from.toFen()
          ? _current
          : null;
      _selectedSquare = null;
    });
  }

  void _stepExploration(int delta) {
    final line = _exploring;
    if (line == null) return;
    setState(() => _exploring = line.at(line.index + delta));
  }

  void _seekExploration(int index) {
    final line = _exploring;
    if (line == null) return;
    setState(() => _exploring = line.at(index));
  }

  void _stopExploring() {
    setState(() {
      _exploring = null;
      _exploreAnchor = null;
      _exploringInfo = null;
    });
  }

  /// Keep the walked line, as a variation of the position it started from.
  void _keepExploredLine() {
    final line = _exploring;
    final anchor = _exploreAnchor;
    if (line == null || anchor == null) return;
    setState(() {
      final end = anchor.addLine(line.moves.take(line.index));
      _exploring = null;
      _exploreAnchor = null;
      _exploringInfo = null;
      _current = end;
      _fenController.text = _position.toFen();
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  /// Controls for a line being walked: which line it is, where you are in it,
  /// how to move along it, and whether to keep it.
  Widget _explorationBanner(BuildContext context, ExploredLine line) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    final info = _exploringInfo;
    final onContainer = theme.colorScheme.onSecondaryContainer;

    final score = info == null
        ? null
        : formatScore(
            info,
            sideToMoveIsRed: line.start.sideToMove == PieceColor.red,
            redPerspective: settings.scorePerspective == ScorePerspective.red,
          );
    final next = line.nextMove;

    Widget step({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) => IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: onContainer,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.travel_explore, size: 16, color: onContainer),
          const SizedBox(width: 6),
          // Which line this is, and how good the engine thought it was.
          Flexible(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: onContainer),
                children: [
                  if (info != null && info.multiPV > 1)
                    TextSpan(text: '#${info.multiPV}  '),
                  TextSpan(text: '${line.index}/${line.moves.length}'),
                  if (info != null)
                    TextSpan(text: '  ·  d${info.depth}  ${info.timeText}'),
                  if (score != null)
                    TextSpan(
                      text: '  ${score.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (next != null)
                    TextSpan(
                      text:
                          '  ·  next ${MoveNotation.toNotation(next, line.position, settings.language)}',
                    ),
                ],
              ),
            ),
          ),
          step(
            icon: Icons.skip_previous,
            tooltip: 'Start of line',
            onPressed: line.canStepBack ? () => _seekExploration(0) : null,
          ),
          step(
            icon: Icons.chevron_left,
            tooltip: 'Back one move',
            onPressed: line.canStepBack ? () => _stepExploration(-1) : null,
          ),
          step(
            icon: Icons.chevron_right,
            tooltip: 'Forward one move',
            onPressed: line.canStepForward ? () => _stepExploration(1) : null,
          ),
          step(
            icon: Icons.skip_next,
            tooltip: 'End of line',
            onPressed: line.canStepForward
                ? () => _seekExploration(line.moves.length)
                : null,
          ),
          TextButton.icon(
            // Only a game standing on the position the line came from can
            // hold it.
            onPressed: _exploreAnchor == null || line.index == 0
                ? null
                : _keepExploredLine,
            icon: const Icon(Icons.playlist_add, size: 16),
            label: const Text('Add to game'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          TextButton.icon(
            onPressed: _stopExploring,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Done'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  void _setSetupMode(bool editing) {
    setState(() {
      _isSetupMode = editing;
      _palettePiece = null;
      _selectedSquare = null;
    });
  }

  void _startAnalysis() {
    if (!_engineReady) return;

    setState(() {
      _isAnalyzing = true;
      _latestBestMove = null;
      _staleLines = [];
      _bestUci = null;
      _ponderUci = null;
      _selectedSquare = null;
      _startEngineSearch(_position);
    });
  }

  /// Walk the current line, giving the engine a fixed slice of time on each
  /// position so the score chart fills in.
  ///
  /// Each position is searched with the normal infinite search and stopped on
  /// a timer, which works the same on both engine backends; scores land in the
  /// usual per-position store, so a deeper manual search is never overwritten
  /// by a shallow sweep.
  Future<void> _analyseWholeGame() async {
    if (!_engineReady || _batchTotal != null) return;
    final seconds = await _askSecondsPerMove();
    if (seconds == null || !mounted) return;

    if (_isAnalyzing) _stopAnalysis();
    final resumeAt = _current;
    // The line the board is on, from the start through to its end.
    final nodes = _current.mainlineEnd.pathFromRoot;

    setState(() {
      _secondsPerMove = seconds;
      _batchCancelled = false;
      _batchDone = 0;
      _batchTotal = nodes.length;
      _staleLines = [];
      _curLines.clear();
    });

    try {
      for (final node in nodes) {
        if (_batchCancelled || !mounted) break;
        setState(() {
          _current = node;
          _curLines.clear();
          _enginePosition = node.position;
          _updateLastMoveHighlight();
        });

        _engine.setOption('MultiPV', '${widget.settings.multiPv}');
        _engine.setPosition(node.position.toFen());
        _engine.goInfinite();
        await Future<void>.delayed(Duration(seconds: seconds));
        _engine.stop();
        // Let the search wind down so its last lines are attributed here.
        await _engine.bestMove.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => const BestMove(move: ''),
        );

        if (!mounted) break;
        setState(() => _batchDone = (_batchDone ?? 0) + 1);
      }
    } finally {
      if (mounted) {
        setState(() {
          _batchDone = null;
          _batchTotal = null;
          _isAnalyzing = false;
          _current = resumeAt;
          _updateLastMoveHighlight();
        });
      }
    }
  }

  void _cancelWholeGameAnalysis() {
    setState(() => _batchCancelled = true);
    _engine.stop();
  }

  /// Ask how long the engine gets on each position.
  Future<int?> _askSecondsPerMove() {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Analyse whole game'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'The engine searches each position in turn, then the chart shows '
              'how the game swung.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
          for (final seconds in const [1, 3, 5, 10, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, seconds),
              child: Text(
                '$seconds second${seconds == 1 ? '' : 's'} per move'
                '${seconds == _secondsPerMove ? '  ·  last used' : ''}',
              ),
            ),
        ],
      ),
    );
  }

  void _stopAnalysis() {
    _engine.stop();
    // _isAnalyzing will be set to false when bestmove callback fires
  }

  /// Open a game file: XQStudio's .XQF or one of ours.
  Future<void> _openGameFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: GameIO.readableExtensions,
      dialogTitle: 'Open game',
    );
    final path = picked?.files.single.path;
    if (path != null) await _openPath(path);
  }

  /// Load the game at [path], however it was chosen.
  ///
  /// A CCBridge library holds a whole collection, so more than one game may
  /// come back; the reader picks which to open.
  Future<void> _openPath(String path) async {
    try {
      final games = await GameIO.loadAll(
        path,
        language: widget.settings.language,
      );
      if (!mounted) return;
      final game = games.length == 1
          ? games.first
          : await _pickGame(games, path.split('/').last);
      if (game == null || !mounted) return;
      if (_isAnalyzing) _stopAnalysis();
      setState(() {
        _loadGame(game);
        // Only our own format can be written back to.
        _currentFilePath =
            path.toLowerCase().endsWith('.${GameIO.nativeExtension}')
            ? path
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open: $e')));
    }
  }

  /// Choose one game out of a collection.
  Future<Game?> _pickGame(List<Game> games, String fileName) {
    return showDialog<Game>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$fileName — ${games.length} games'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: ListView.builder(
            itemCount: games.length,
            itemBuilder: (context, index) {
              final game = games[index];
              final metadata = game.metadata;
              final players = [
                if (metadata.red.isNotEmpty) metadata.red,
                if (metadata.black.isNotEmpty) metadata.black,
              ].join(' — ');
              final detail = [
                if (players.isNotEmpty) players,
                if (metadata.event.isNotEmpty) metadata.event,
                if (metadata.date.isNotEmpty) metadata.date,
                '${game.mainlineLength} moves',
              ].join('  ·  ');
              return ListTile(
                dense: true,
                leading: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(dialogContext).hintColor,
                  ),
                ),
                title: Text(
                  metadata.title.isEmpty ? '(untitled)' : metadata.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(dialogContext, game),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Files dropped on the window open the same way picked ones do; extras are
  /// reported rather than silently replacing each other.
  Future<void> _openDropped(List<DropItem> items) async {
    setState(() => _dragging = false);
    final paths = [
      for (final item in items)
        if (item.path.isNotEmpty) item.path,
    ];
    if (paths.isEmpty) return;
    await _openPath(paths.first);
    if (paths.length > 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Opened ${paths.first.split('/').last} — '
            '${paths.length - 1} other file(s) ignored',
          ),
        ),
      );
    }
  }

  /// Save the game — including every variation and note — as JSON.
  Future<void> _saveGameFile() async {
    var path = _currentFilePath;
    if (path == null) {
      path = await FilePicker.saveFile(
        dialogTitle: 'Save game',
        fileName: GameIO.suggestedFileName(_game),
        type: FileType.custom,
        allowedExtensions: const [GameIO.nativeExtension],
      );
      if (path == null) return;
      if (!path.contains('.')) path = '$path.${GameIO.nativeExtension}';
    }

    try {
      await GameIO.save(path, _game);
      if (!mounted) return;
      setState(() => _currentFilePath = path);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved ${path.split('/').last}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  /// Write the game out as readable text or as HTML with board diagrams.
  Future<void> _exportGame(bool asHtml) async {
    final base = GameIO.suggestedFileName(
      _game,
    ).replaceAll('.${GameIO.nativeExtension}', '');
    final extension = asHtml ? 'html' : 'txt';
    final path = await FilePicker.saveFile(
      dialogTitle: asHtml ? 'Export HTML' : 'Export text',
      fileName: '$base.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (path == null) return;

    final content = asHtml
        ? GameExport.toHtml(_game, language: widget.settings.language)
        : GameExport.toText(_game, language: widget.settings.language);
    try {
      await File(
        path.contains('.') ? path : '$path.$extension',
      ).writeAsString(content, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${path.split('/').last}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export: $e')));
    }
  }

  /// Show and edit the game's title, players and result.
  Future<void> _editGameInfo() async {
    final metadata = _game.metadata.copy();
    final controllers = {
      'Title': TextEditingController(text: metadata.title),
      'Event': TextEditingController(text: metadata.event),
      'Site': TextEditingController(text: metadata.site),
      'Date': TextEditingController(text: metadata.date),
      'Red': TextEditingController(text: metadata.red),
      'Black': TextEditingController(text: metadata.black),
      'Annotator': TextEditingController(text: metadata.annotator),
    };
    var result = metadata.result;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Game information'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in controllers.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: entry.value,
                      decoration: InputDecoration(
                        labelText: entry.key,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<GameResult>(
                  initialValue: result,
                  decoration: const InputDecoration(
                    labelText: 'Result',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in GameResult.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(GameExport.resultText(value)),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => result = value ?? GameResult.unknown,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final controller in controllers.values) {
      if (saved == true) continue;
      controller.dispose();
    }
    if (saved != true) return;

    setState(() {
      _game.metadata
        ..title = controllers['Title']!.text
        ..event = controllers['Event']!.text
        ..site = controllers['Site']!.text
        ..date = controllers['Date']!.text
        ..red = controllers['Red']!.text
        ..black = controllers['Black']!.text
        ..annotator = controllers['Annotator']!.text
        ..result = result;
    });
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          settings: widget.settings,
          onChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }

  void _resetPosition() {
    if (_isAnalyzing) _stopAnalysis();
    final wasEditing = _isSetupMode;
    setState(() {
      _loadGame(Game.fromPosition(Position.startPosition()));
      _isSetupMode = wasEditing;
    });
  }

  /// Strip the board back to the two kings — a position the engine can still
  /// read, unlike an empty board.
  void _clearBoard() {
    if (_isAnalyzing) _stopAnalysis();
    final wasEditing = _isSetupMode;
    setState(() {
      _loadGame(Game.fromPosition(Position.kingsOnly()));
      _isSetupMode = wasEditing;
    });
  }

  void _applyFen() {
    if (_isAnalyzing) _stopAnalysis();
    final fen = _fenController.text.trim();
    if (fen.isEmpty) return;
    try {
      final position = Position.fromFen(fen);
      setState(
        () => _loadGame(Game.fromPosition(position, metadata: _game.metadata)),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid FEN: $e')));
    }
  }

  /// Replace the board with a transformed copy of the current position.
  ///
  /// The transformed position is a new starting point, so the move history is
  /// dropped and stale engine output cleared; a running search restarts on it.
  void _transformPosition(Position Function(Position) transform) {
    setState(() {
      _loadGame(
        Game.fromPosition(transform(_position), metadata: _game.metadata),
      );
      _restartAnalysisIfNeeded();
    });
  }

  void _toggleSideToMove() {
    setState(() {
      _replaceCurrentPosition(
        _position.withSideToMove(
          _position.sideToMove == PieceColor.red
              ? PieceColor.black
              : PieceColor.red,
        ),
      );
      _fenController.text = _position.toFen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final exploring = _exploring;
    // On mobile the board fills the phone width (430 also caps it on iPad);
    // on desktop there is room to make it noticeably larger.
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final double maxBoardWidth = isDesktop ? 640 : 430;

    return Scaffold(
      body: _withFileDrop(
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Cap the board's height so it shrinks to fit short windows
              // instead of overflowing; leave room for the control rows and a
              // usable analysis panel below. The reserve follows the text scale
              // since those rows grow with the font size. The ceiling matches
              // maxBoardWidth's 9:10 aspect so height, not the ceiling, is what
              // caps a big board.
              final textScaler = MediaQuery.textScalerOf(context);
              final double boardMaxHeight =
                  (constraints.maxHeight - textScaler.scale(340)).clamp(
                    160.0,
                    isDesktop ? 760.0 : 620.0,
                  );
              // Wide windows get XQStudio's shape: board on the left, the
              // game score beside it, notes and branches to the right.
              final wide = constraints.maxWidth >= 980;

              // The board keeps one size whether or not the palette is out.
              final paletteWidth = textScaler.scale(142);
              final available = constraints.maxWidth - 16;
              var boardWidth = math.min(
                math.min(maxBoardWidth, available),
                boardMaxHeight * Position.files / Position.ranks,
              );
              final reservePaletteSpace =
                  available >= boardWidth + 2 * paletteWidth;
              if (!reservePaletteSpace && _isSetupMode) {
                // Too narrow to reserve it: the board gives way instead.
                boardWidth = math.min(boardWidth, available - paletteWidth);
              }
              final boardHeight = boardWidth * Position.ranks / Position.files;

              final boardColumn = Column(
                children: [
                  // FEN input
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fenController,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(),
                              hintText: 'FEN',
                            ),
                            onSubmitted: (_) => _applyFen(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, size: 20),
                          onPressed: _applyFen,
                          tooltip: 'Apply FEN',
                        ),
                      ],
                    ),
                  ),

                  // Board, with the piece palette beside it while editing.
                  // The palette's width is reserved on both sides whenever
                  // the window can spare it, so opening it does not shove the
                  // board sideways.
                  Center(
                    child: SizedBox(
                      height: boardHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (reservePaletteSpace)
                            SizedBox(width: paletteWidth),
                          SizedBox(
                            width: boardWidth,
                            child: BoardWidget(
                              position: exploring?.position ?? _position,
                              selectedSquare: exploring == null
                                  ? _selectedSquare
                                  : null,
                              // Each indicator is independently switchable
                              // in settings; when off it is not passed.
                              lastMoveFrom: settings.highlightLastMove
                                  ? (exploring == null
                                        ? _lastMoveFrom
                                        : _uciSquare(exploring.lastMove, 0))
                                  : null,
                              lastMoveTo: settings.highlightLastMove
                                  ? (exploring == null
                                        ? _lastMoveTo
                                        : _uciSquare(exploring.lastMove, 2))
                                  : null,
                              arrows: _isSetupMode ? const [] : _boardArrows,
                              viewFromBlack: _viewFromBlack,
                              // Walking a line is read-only; the game is
                              // untouched until the line is kept.
                              onSquareTap: exploring == null
                                  ? _onSquareTap
                                  : null,
                              onSquareSecondaryTap: _isSetupMode
                                  ? _handleSetupSecondaryTap
                                  : null,
                              language: settings.language,
                            ),
                          ),
                          if (_isSetupMode)
                            SizedBox(
                              width: paletteWidth,
                              child: PiecePalette(
                                selected: _palettePiece,
                                hasSelectedSquare: _selectedSquare != null,
                                viewFromBlack: _viewFromBlack,
                                language: settings.language,
                                onPick: (piece) =>
                                    setState(() => _palettePiece = piece),
                                onDelete: _deleteSelectedPiece,
                                onClear: _clearBoard,
                                onReset: _resetPosition,
                                onDone: () => _setSetupMode(false),
                              ),
                            )
                          else if (reservePaletteSpace)
                            SizedBox(width: paletteWidth),
                        ],
                      ),
                    ),
                  ),

                  // While a line is being walked, its controls stand in for
                  // the game's navigation.
                  if (exploring != null)
                    _explorationBanner(context, exploring)
                  else
                    // Move navigation
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _canGoBack ? _goToStart : null,
                            icon: const Icon(Icons.skip_previous, size: 22),
                            tooltip: 'Go to start',
                          ),
                          IconButton(
                            onPressed: _canGoBack ? _goBack : null,
                            icon: const Icon(Icons.chevron_left, size: 28),
                            tooltip: 'Previous move',
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '${_current.ply}/${_current.mainlineEnd.ply}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _canGoForward ? _goForward : null,
                            icon: const Icon(Icons.chevron_right, size: 28),
                            tooltip: 'Next move',
                          ),
                          IconButton(
                            onPressed: _canGoForward ? _goToEnd : null,
                            icon: const Icon(Icons.skip_next, size: 22),
                            tooltip: 'Go to end',
                          ),
                        ],
                      ),
                    ),

                  // Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        // Single button that starts or stops the search.
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: !_engineReady
                                ? null
                                : (_isAnalyzing
                                      ? _stopAnalysis
                                      : _startAnalysis),
                            icon: Icon(
                              _isAnalyzing ? Icons.stop : Icons.play_arrow,
                              size: 18,
                            ),
                            label: Text(_isAnalyzing ? 'Stop' : 'Analyze'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _canPlayBestMove ? _playBestMove : null,
                            icon: const Icon(Icons.done_all, size: 18),
                            label: const Text('Play Best'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Board transforms, next to the side-to-move indicator
                        // they share a row with.
                        IconButton(
                          onPressed: () =>
                              _transformPosition((p) => p.mirrored()),
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          tooltip: 'Mirror left-right (a↔i)',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () =>
                              _transformPosition((p) => p.flipped()),
                          icon: const Icon(Icons.swap_vert, size: 20),
                          tooltip: 'Flip up-down and swap sides',
                          visualDensity: VisualDensity.compact,
                        ),
                        // View-only rotation — the position is untouched.
                        IconButton(
                          onPressed: () =>
                              setState(() => _viewFromBlack = !_viewFromBlack),
                          icon: Icon(
                            Icons.rotate_left,
                            size: 20,
                            color: _viewFromBlack
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          tooltip: _viewFromBlack
                              ? "View from Red's side"
                              : "View from Black's side",
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                        // Side to move indicator / toggle
                        GestureDetector(
                          onTap: _isAnalyzing ? null : _toggleSideToMove,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _position.sideToMove == PieceColor.red
                                  ? Colors.red
                                  : Colors.black87,
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Center(
                              child: Text(
                                _position.sideToMove == PieceColor.red
                                    ? 'R'
                                    : 'B',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Secondary controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: _isAnalyzing ? null : _resetPosition,
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('New'),
                        ),
                        IconButton(
                          onPressed: _openGameFile,
                          icon: const Icon(Icons.folder_open, size: 18),
                          tooltip: 'Open game (.XQF or .pbg)',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: _saveGameFile,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          tooltip: 'Save game',
                          visualDensity: VisualDensity.compact,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.ios_share, size: 18),
                          tooltip: 'Export',
                          onSelected: (choice) => _exportGame(choice == 'html'),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'txt',
                              child: Text('Export text…'),
                            ),
                            PopupMenuItem(
                              value: 'html',
                              child: Text('Export HTML with diagrams…'),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: _editGameInfo,
                          icon: const Icon(Icons.info_outline, size: 18),
                          tooltip: 'Game information',
                          visualDensity: VisualDensity.compact,
                        ),
                        TextButton.icon(
                          onPressed: _isAnalyzing
                              ? null
                              : () => _setSetupMode(!_isSetupMode),
                          icon: Icon(
                            _isSetupMode ? Icons.check : Icons.edit,
                            size: 18,
                          ),
                          label: Text(_isSetupMode ? 'Done' : 'Setup'),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings, size: 20),
                          tooltip: 'Settings',
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Move list, for narrow windows where there is no column
                  // beside the board to hold it.
                  if (!wide && _game.root.children.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: textScaler.scale(96),
                      ),
                      child: MoveTree(
                        game: _game,
                        current: _current,
                        language: settings.language,
                        onSelect: _goToNode,
                        onDelete: _deleteNode,
                        onPromote: _promoteNode,
                        showPreview: settings.previewOnMoveTree,
                        viewFromBlack: _viewFromBlack,
                        scoreLabelFor: (node) {
                          final sample = _evalByFen[node.position.toFen()];
                          return sample == null ? null : scoreLabel(sample.cp);
                        },
                      ),
                    ),
                  if (!wide && _game.root.children.isNotEmpty)
                    const Divider(height: 1),

                  // Engine analysis and cloud candidates in separate tabs
                  Expanded(
                    child: DefaultTabController(
                      // Notes live in the right-hand column when there is one.
                      length: wide ? 4 : 5,
                      child: Column(
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.center,
                            tabs: [
                              const Tab(text: 'Engine'),
                              if (!wide) const Tab(text: 'Notes'),
                              const Tab(text: 'Cloud'),
                              const Tab(text: 'Raw'),
                              const Tab(text: 'Score'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Scrolls internally so its stats row can stay
                                // pinned to the bottom.
                                AnalysisPanel(
                                  lines: _analysisLines,
                                  // While the search runs there is no bestmove
                                  // yet, so show the PV's current best/reply.
                                  bestMove:
                                      _latestBestMove ??
                                      (_bestUci == null
                                          ? null
                                          : BestMove(
                                              move: _bestUci!,
                                              ponder: _ponderUci,
                                            )),
                                  position: _enginePosition ?? _position,
                                  bestMoveStale: !_engineMatchesBoard,
                                  language: settings.language,
                                  scorePerspective: settings.scorePerspective,
                                  showPreview: settings.previewOnEngineLine,
                                  viewFromBlack: _viewFromBlack,
                                  onExplore: _exploreLine,
                                ),
                                if (!wide)
                                  NotesPanel(
                                    node: _current,
                                    language: settings.language,
                                    onChanged: (text) =>
                                        setState(() => _current.comment = text),
                                  ),
                                SingleChildScrollView(
                                  child: CandidateMoves(
                                    position: _position,
                                    language: widget.settings.language,
                                    scorePerspective:
                                        widget.settings.scorePerspective,
                                    onPlay: _playUci,
                                  ),
                                ),
                                EngineOutputView(log: _engineLog),
                                ScoreChart(
                                  points: _scorePoints,
                                  currentPly: _current.ply,
                                  onSelect: _goToPly,
                                  onAnalyseGame: _engineReady
                                      ? _analyseWholeGame
                                      : null,
                                  onCancelAnalysis: _cancelWholeGameAnalysis,
                                  analysedCount: _batchDone,
                                  analysisTotal: _batchTotal,
                                  showPreview: settings.previewOnChart,
                                  language: settings.language,
                                  viewFromBlack: _viewFromBlack,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Engine status
                  if (!_engineReady)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Loading engine...'),
                        ],
                      ),
                    ),
                ],
              );

              if (!wide) return boardColumn;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: boardColumn),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: textScaler.scale(196),
                    child: MoveTable(
                      line: _line,
                      current: _current,
                      language: settings.language,
                      onSelect: _goToNode,
                      showPreview: settings.previewOnMoveTree,
                      viewFromBlack: _viewFromBlack,
                      scoreLabelFor: (node) {
                        final sample = _evalByFen[node.position.toFen()];
                        return sample == null ? null : scoreLabel(sample.cp);
                      },
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: textScaler.scale(280),
                    child: Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: NotesPanel(
                            node: _current,
                            language: settings.language,
                            onChanged: (text) =>
                                setState(() => _current.comment = text),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          flex: 2,
                          child: VariationList(
                            current: _current,
                            language: settings.language,
                            onSelect: _goToNode,
                            onPromote: _promoteNode,
                            onDelete: _deleteNode,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Wrap [child] so a game file dropped on the window opens.
  ///
  /// Only desktop gets a drop target: the plugin has no iOS side, and there is
  /// nothing to drag there anyway.
  Widget _withFileDrop(Widget child) {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      return child;
    }
    final theme = Theme.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) => _openDropped(details.files),
      child: Stack(
        children: [
          child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Text(
                          'Drop to open  (.XQF, .pbg, .xqg)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
