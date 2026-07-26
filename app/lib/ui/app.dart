import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../engine/pikafish_engine.dart';
import '../engine/search_info.dart';
import '../models/piece.dart';
import '../models/position.dart';
import '../models/settings.dart';
import '../models/settings_store.dart';
import 'board_widget.dart';
import 'analysis_panel.dart';
import 'candidate_moves.dart';
import 'move_list.dart';
import 'settings_page.dart';

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

  // Move history: list of positions from the starting position onward.
  // _historyIndex points to the currently displayed position.
  List<Position> _history = [];
  int _historyIndex = 0;

  Position get _position => _history[_historyIndex];

  int? _selectedSquare;
  bool _isAnalyzing = false;
  bool _engineReady = false;
  bool _restartPending = false; // true when stop() is called for a restart
  bool _isSetupMode = false;
  PieceColor _setupColor = PieceColor.red;

  BestMove? _latestBestMove;

  // The position the engine is currently searching. Search output is tied to
  // this so its moves render in the right notation and so lines can be marked
  // stale once the board moves on.
  Position? _enginePosition;

  // Current search lines, keyed by depth so each iteration collapses to one
  // row (latest update per depth wins).
  final Map<int, SearchInfo> _curByDepth = {};

  // Lines from the previous searched position, shown greyed below the current
  // ones until the next hard reset.
  List<AnalysisLine> _staleLines = [];

  /// Rows for the analysis table: current-position lines (deepest on top)
  /// first, then any stale previous-position lines.
  List<AnalysisLine> get _analysisLines {
    final enginePos = _enginePosition;
    // If the board has moved on without a running search, the current lines
    // describe a previous position too.
    final curStale =
        enginePos == null || enginePos.toFen() != _position.toFen();
    final cur =
        (_curByDepth.values.toList()
              ..sort((a, b) => b.depth.compareTo(a.depth)))
            .map(
              (info) => AnalysisLine(
                info: info,
                position: enginePos ?? _position,
                stale: curStale,
              ),
            );
    return [...cur, ..._staleLines];
  }

  /// Send [pos] to the engine and start an infinite search, demoting the
  /// previous search's lines to the greyed stale list.
  void _startEngineSearch(Position pos) {
    if (_curByDepth.isNotEmpty && _enginePosition != null) {
      _staleLines =
          _curByDepth.values
              .map(
                (info) => AnalysisLine(
                  info: info,
                  position: _enginePosition!,
                  stale: true,
                ),
              )
              .toList()
            ..sort((a, b) => b.info.depth.compareTo(a.info.depth));
    }
    _curByDepth.clear();
    _enginePosition = pos;
    _engine.setPosition(pos.toFen());
    _engine.goInfinite();
  }

  StreamSubscription<SearchInfo>? _infoSub;
  StreamSubscription<BestMove>? _bestMoveSub;

  // For highlighting the best move
  int? _bestMoveFrom;
  int? _bestMoveTo;

  // For highlighting the last move played
  int? _lastMoveFrom;
  int? _lastMoveTo;

  @override
  void initState() {
    super.initState();
    _history = [Position.startPosition()];
    _historyIndex = 0;
    _fenController.text = _position.toFen();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      await _engine.init();
      _infoSub = _engine.searchInfo.listen((info) {
        // Drop trailing output from a search that was stopped for a restart,
        // so old high-depth lines don't leak into the new position's table.
        if (_restartPending) return;
        setState(() {
          if (info.pv.isNotEmpty) _curByDepth[info.depth] = info;
          // Highlight best move from PV
          if (info.pv.isNotEmpty) {
            final move = info.pv.first;
            if (move.length >= 4) {
              _bestMoveFrom = Position.uciToSquare(move.substring(0, 2));
              _bestMoveTo = Position.uciToSquare(move.substring(2, 4));
            }
          }
        });
      });
      _bestMoveSub = _engine.bestMove.listen((bm) {
        if (_restartPending) return; // ignore bestmove from a stop-for-restart
        setState(() {
          _latestBestMove = bm;
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
  void dispose() {
    _infoSub?.cancel();
    _bestMoveSub?.cancel();
    _engine.dispose();
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

        // Move piece
        final piece = _position.pieceAt(_selectedSquare!);
        if (piece != null) {
          _makeMove(_selectedSquare!, square);
        }
        _selectedSquare = null;
      }
    });
  }

  /// Execute a move on the board, update history, and restart engine if analyzing.
  void _makeMove(int from, int to) {
    final piece = _position.pieceAt(from);
    if (piece == null) return;

    final newPos = _position
        .withPiece(from, null)
        .withPiece(to, piece)
        .withSideToMove(
          _position.sideToMove == PieceColor.red
              ? PieceColor.black
              : PieceColor.red,
        );

    // Truncate future history if we're not at the end
    if (_historyIndex < _history.length - 1) {
      _history = _history.sublist(0, _historyIndex + 1);
    }

    _history.add(newPos);
    _historyIndex = _history.length - 1;
    _fenController.text = newPos.toFen();
    _lastMoveFrom = from;
    _lastMoveTo = to;

    // If engine is analyzing, restart analysis on the new position. The old
    // lines stay visible (greyed, since the board no longer matches the engine
    // position) until the new search demotes them to the stale list.
    if (_isAnalyzing) {
      _latestBestMove = null;
      _bestMoveFrom = null;
      _bestMoveTo = null;
      _restartPending = true;
      _engine.stop();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _restartPending = false;
            _startEngineSearch(newPos);
          });
        }
      });
    } else {
      _bestMoveFrom = null;
      _bestMoveTo = null;
    }
  }

  bool get _canGoBack => _historyIndex > 0;
  bool get _canGoForward => _historyIndex < _history.length - 1;

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _historyIndex--;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      _historyIndex++;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  void _goToStart() {
    if (_historyIndex == 0) return;
    setState(() {
      _historyIndex = 0;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _lastMoveFrom = null;
      _lastMoveTo = null;
      _restartAnalysisIfNeeded();
    });
  }

  void _goToEnd() {
    if (_historyIndex == _history.length - 1) return;
    setState(() {
      _historyIndex = _history.length - 1;
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

  /// Jump to a specific position in the move history.
  void _goToIndex(int index) {
    if (index < 0 || index >= _history.length || index == _historyIndex) return;
    setState(() {
      _historyIndex = index;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _updateLastMoveHighlight();
      _restartAnalysisIfNeeded();
    });
  }

  /// Reconstruct last-move highlight by comparing current and previous positions.
  void _updateLastMoveHighlight() {
    if (_historyIndex == 0) {
      _lastMoveFrom = null;
      _lastMoveTo = null;
      return;
    }
    // Find the squares that differ between previous and current position
    final prev = _history[_historyIndex - 1];
    final curr = _history[_historyIndex];
    int? from;
    int? to;
    for (int sq = 0; sq < Position.squareCount; sq++) {
      final prevP = prev.pieceAt(sq);
      final currP = curr.pieceAt(sq);
      if (prevP != currP) {
        if (prevP != null && currP == null) {
          from = sq; // piece left this square
        } else if (currP != null && (prevP == null || prevP != currP)) {
          to = sq; // piece arrived at this square
        }
      }
    }
    _lastMoveFrom = from;
    _lastMoveTo = to;
  }

  /// If analyzing, restart analysis on the current position.
  void _restartAnalysisIfNeeded() {
    if (!_isAnalyzing) {
      _bestMoveFrom = null;
      _bestMoveTo = null;
      return;
    }
    _latestBestMove = null;
    _bestMoveFrom = null;
    _bestMoveTo = null;
    _restartPending = true;
    _engine.stop();
    final target = _position;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _restartPending = false;
          _startEngineSearch(target);
        });
      }
    });
  }

  void _handleSetupTap(int square) {
    setState(() {
      final existing = _position.pieceAt(square);
      if (existing != null) {
        // Remove piece
        _replaceCurrentPosition(_position.withPiece(square, null));
      } else {
        // Show piece picker
        _showPiecePicker(square);
      }
      _fenController.text = _position.toFen();
    });
  }

  /// Replace the current position in history (for setup mode edits).
  void _replaceCurrentPosition(Position pos) {
    _history[_historyIndex] = pos;
  }

  void _showPiecePicker(int square) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Place piece at ${Position.squareToUci(square)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ToggleButtons(
                    isSelected: [
                      _setupColor == PieceColor.red,
                      _setupColor == PieceColor.black,
                    ],
                    onPressed: (i) {
                      setState(() {
                        _setupColor = i == 0
                            ? PieceColor.red
                            : PieceColor.black;
                      });
                      Navigator.pop(context);
                      _showPiecePicker(square);
                    },
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Red', style: TextStyle(color: Colors.red)),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Black'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: PieceType.values.map((type) {
                  final piece = Piece(_setupColor, type);
                  return ActionChip(
                    label: Text(
                      piece.label,
                      style: TextStyle(
                        fontSize: 22,
                        color: _setupColor == PieceColor.red
                            ? Colors.red.shade800
                            : Colors.black,
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _replaceCurrentPosition(
                          _position.withPiece(square, piece),
                        );
                        _fenController.text = _position.toFen();
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startAnalysis() {
    if (!_engineReady) return;

    setState(() {
      _isAnalyzing = true;
      _latestBestMove = null;
      _staleLines = [];
      _bestMoveFrom = null;
      _bestMoveTo = null;
      _selectedSquare = null;
      _startEngineSearch(_position);
    });
  }

  void _stopAnalysis() {
    _engine.stop();
    // _isAnalyzing will be set to false when bestmove callback fires
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
    setState(() {
      _history = [Position.startPosition()];
      _historyIndex = 0;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _latestBestMove = null;
      _curByDepth.clear();
      _staleLines = [];
      _enginePosition = null;
      _bestMoveFrom = null;
      _bestMoveTo = null;
      _lastMoveFrom = null;
      _lastMoveTo = null;
    });
  }

  void _clearBoard() {
    if (_isAnalyzing) _stopAnalysis();
    setState(() {
      _history = [Position.empty()];
      _historyIndex = 0;
      _fenController.text = _position.toFen();
      _selectedSquare = null;
      _latestBestMove = null;
      _curByDepth.clear();
      _staleLines = [];
      _enginePosition = null;
      _bestMoveFrom = null;
      _bestMoveTo = null;
      _lastMoveFrom = null;
      _lastMoveTo = null;
    });
  }

  void _applyFen() {
    if (_isAnalyzing) _stopAnalysis();
    final fen = _fenController.text.trim();
    if (fen.isEmpty) return;
    try {
      setState(() {
        _history = [Position.fromFen(fen)];
        _historyIndex = 0;
        _selectedSquare = null;
        _latestBestMove = null;
        _curByDepth.clear();
        _staleLines = [];
        _enginePosition = null;
        _bestMoveFrom = null;
        _bestMoveTo = null;
        _lastMoveFrom = null;
        _lastMoveTo = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid FEN: $e')));
    }
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
    // On mobile the board fills the phone width (430 also caps it on iPad);
    // on desktop there is room to make it noticeably larger.
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final double maxBoardWidth = isDesktop ? 640 : 430;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cap the board's height so it shrinks to fit short windows
            // instead of overflowing; leave room for the control rows and a
            // usable analysis panel below. The ceiling matches maxBoardWidth's
            // 9:10 aspect so height, not the ceiling, is what caps a big board.
            final double boardMaxHeight = (constraints.maxHeight - 340).clamp(
              160.0,
              isDesktop ? 760.0 : 620.0,
            );
            return Column(
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

                // Board — constrained to maxBoardWidth
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxBoardWidth,
                      maxHeight: boardMaxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: BoardWidget(
                        position: _position,
                        selectedSquare: _selectedSquare,
                        highlightFrom: _bestMoveFrom,
                        highlightTo: _bestMoveTo,
                        lastMoveFrom: _lastMoveFrom,
                        lastMoveTo: _lastMoveTo,
                        onSquareTap: _onSquareTap,
                        language: widget.settings.language,
                      ),
                    ),
                  ),
                ),

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
                          '${_historyIndex}/${_history.length - 1}',
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
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _engineReady && !_isAnalyzing
                              ? _startAnalysis
                              : null,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Analyze'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isAnalyzing ? _stopAnalysis : null,
                          icon: const Icon(Icons.stop, size: 18),
                          label: const Text('Stop'),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                      TextButton.icon(
                        onPressed: _isAnalyzing ? null : _clearBoard,
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear'),
                      ),
                      TextButton.icon(
                        onPressed: _isAnalyzing
                            ? null
                            : () =>
                                  setState(() => _isSetupMode = !_isSetupMode),
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

                // Move list (only once moves have been played)
                if (_history.length > 1)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 64),
                    child: MoveList(
                      history: _history,
                      currentIndex: _historyIndex,
                      language: widget.settings.language,
                      onSelect: _goToIndex,
                    ),
                  ),
                if (_history.length > 1) const Divider(height: 1),

                // Cloud candidates + engine analysis (scroll together)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CandidateMoves(
                          position: _position,
                          language: widget.settings.language,
                          scorePerspective: widget.settings.scorePerspective,
                          onPlay: _playUci,
                        ),
                        const Divider(height: 1),
                        AnalysisPanel(
                          lines: _analysisLines,
                          bestMove: _latestBestMove,
                          position: _enginePosition ?? _position,
                          language: widget.settings.language,
                          scorePerspective: widget.settings.scorePerspective,
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
          },
        ),
      ),
    );
  }
}
