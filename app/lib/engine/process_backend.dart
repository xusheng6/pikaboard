import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'engine_backend.dart';
import 'search_info.dart';

/// Desktop engine backend. Spawns the Pikafish executable as a child process
/// and speaks the UCI protocol over stdin/stdout — the same way desktop chess
/// GUIs drive their engines. Raw UCI output is parsed back into the same
/// [SearchInfo] / [BestMove] events produced by the FFI backend.
class ProcessBackend implements EngineBackend {
  Process? _process;
  bool _initialized = false;

  final _searchInfoController = StreamController<SearchInfo>.broadcast();
  final _bestMoveController = StreamController<BestMove>.broadcast();

  // Broadcast of every line the engine prints, used both for the UCI handshake
  // and for streaming search output.
  final _lineController = StreamController<String>.broadcast();

  @override
  Stream<SearchInfo> get searchInfo => _searchInfoController.stream;
  @override
  Stream<BestMove> get bestMove => _bestMoveController.stream;
  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> init() async {
    if (_initialized) return;

    final binary = _locateEngineBinary();
    final nnue = _locateNnueFile();
    debugPrint('[ProcessBackend] init: binary=$binary nnue=$nnue');

    final process = await Process.start(
      binary,
      const [],
      workingDirectory: File(binary).parent.path,
    );
    _process = process;

    // Route stdout line-by-line into the broadcast stream + parser.
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    // Surface engine diagnostics for debugging.
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => debugPrint('[Pikafish stderr] $l'));

    // UCI handshake.
    _send('uci');
    await _waitFor((l) => l.trim() == 'uciok');

    if (nnue != null) {
      _send('setoption name EvalFile value $nnue');
    }
    // Use all available cores; scale hash with thread count.
    final cores = Platform.numberOfProcessors;
    _send('setoption name Threads value $cores');
    _send('setoption name Hash value ${cores * 16}');

    _send('isready');
    await _waitFor((l) => l.trim() == 'readyok');

    _initialized = true;
    debugPrint('[ProcessBackend] init: done!');
  }

  @override
  void setPosition(String fen, {List<String> moves = const []}) {
    if (!_initialized) return;
    final movesPart = moves.isEmpty ? '' : ' moves ${moves.join(' ')}';
    _send('position fen $fen$movesPart');
  }

  @override
  void goInfinite() {
    if (!_initialized) return;
    _send('go infinite');
  }

  @override
  void goDepth(int depth) {
    if (!_initialized) return;
    _send('go depth $depth');
  }

  @override
  void stop() {
    if (!_initialized) return;
    _send('stop');
  }

  @override
  void setOption(String name, String value) {
    if (!_initialized) return;
    _send('setoption name $name value $value');
  }

  @override
  void dispose() {
    if (_process != null) {
      try {
        _send('stop');
        _send('quit');
      } catch (_) {}
      _process!.kill();
      _process = null;
    }
    _initialized = false;
    _searchInfoController.close();
    _bestMoveController.close();
    _lineController.close();
  }

  // --- internals -----------------------------------------------------------

  void _send(String command) {
    _process?.stdin.writeln(command);
  }

  Future<void> _waitFor(bool Function(String) predicate) {
    final completer = Completer<void>();
    late StreamSubscription<String> sub;
    sub = _lineController.stream.listen((line) {
      if (predicate(line)) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  void _onLine(String line) {
    if (!_lineController.isClosed) _lineController.add(line);

    if (line.startsWith('info ')) {
      final info = _parseInfo(line);
      if (info != null && !_searchInfoController.isClosed) {
        _searchInfoController.add(info);
      }
    } else if (line.startsWith('bestmove')) {
      final bm = _parseBestMove(line);
      if (bm != null && !_bestMoveController.isClosed) {
        _bestMoveController.add(bm);
      }
    }
  }

  /// Parse a UCI `info` line. Only lines carrying a principal variation are
  /// surfaced (they are the ones with meaningful evaluation output).
  SearchInfo? _parseInfo(String line) {
    final tokens = line.split(RegExp(r'\s+'));
    int depth = 0,
        selDepth = 0,
        multiPv = 1,
        nodes = 0,
        nps = 0,
        timeMs = 0,
        hashfull = 0;
    int? scoreCp, scoreMate;
    bool lower = false, upper = false;
    List<String> pv = const [];

    int i = 1; // skip leading "info"
    while (i < tokens.length) {
      final t = tokens[i];
      switch (t) {
        case 'depth':
          depth = int.tryParse(_next(tokens, i)) ?? depth;
          i += 2;
          break;
        case 'seldepth':
          selDepth = int.tryParse(_next(tokens, i)) ?? selDepth;
          i += 2;
          break;
        case 'multipv':
          multiPv = int.tryParse(_next(tokens, i)) ?? multiPv;
          i += 2;
          break;
        case 'nodes':
          nodes = int.tryParse(_next(tokens, i)) ?? nodes;
          i += 2;
          break;
        case 'nps':
          nps = int.tryParse(_next(tokens, i)) ?? nps;
          i += 2;
          break;
        case 'time':
          timeMs = int.tryParse(_next(tokens, i)) ?? timeMs;
          i += 2;
          break;
        case 'hashfull':
          hashfull = int.tryParse(_next(tokens, i)) ?? hashfull;
          i += 2;
          break;
        case 'score':
          final kind = _next(tokens, i);
          final value = int.tryParse(_next(tokens, i + 1)) ?? 0;
          if (kind == 'mate') {
            scoreMate = value;
          } else {
            scoreCp = value;
          }
          i += 3;
          break;
        case 'lowerbound':
          lower = true;
          i += 1;
          break;
        case 'upperbound':
          upper = true;
          i += 1;
          break;
        case 'pv':
          pv = tokens.sublist(i + 1);
          i = tokens.length; // pv runs to end of line
          break;
        default:
          i += 1; // unknown/ignored token (currmove, string, etc.)
      }
    }

    if (pv.isEmpty) return null;

    return SearchInfo(
      depth: depth,
      selDepth: selDepth,
      multiPV: multiPv,
      scoreCp: scoreMate != null ? null : scoreCp,
      scoreMate: scoreMate,
      isLowerbound: lower,
      isUpperbound: upper,
      nodes: nodes,
      nps: nps,
      timeMs: timeMs,
      hashfull: hashfull,
      pv: pv,
    );
  }

  BestMove? _parseBestMove(String line) {
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.length < 2) return null;
    final move = tokens[1];
    if (move == '(none)') return null;
    String? ponder;
    final pIdx = tokens.indexOf('ponder');
    if (pIdx != -1 && pIdx + 1 < tokens.length) {
      ponder = tokens[pIdx + 1];
    }
    return BestMove(move: move, ponder: ponder);
  }

  static String _next(List<String> tokens, int i) =>
      (i + 1 < tokens.length) ? tokens[i + 1] : '';

  /// Resolve the Pikafish executable. Honors a [PIKAFISH_BIN] override for
  /// development, otherwise looks inside the app bundle's Resources.
  String _locateEngineBinary() {
    final override = Platform.environment['PIKAFISH_BIN'];
    if (override != null && File(override).existsSync()) return override;

    for (final candidate in _resourceCandidates('pikafish')) {
      if (File(candidate).existsSync()) return candidate;
    }
    throw Exception(
      'Pikafish engine binary not found. Set PIKAFISH_BIN or bundle it '
      'into the app Resources.',
    );
  }

  String? _locateNnueFile() {
    final override = Platform.environment['PIKAFISH_NNUE'];
    if (override != null && File(override).existsSync()) return override;

    for (final candidate in _resourceCandidates('pikafish.nnue')) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null; // fall back to engine's own default lookup
  }

  /// Candidate on-disk locations for a bundled resource, most-specific first.
  /// On macOS the executable lives at `Foo.app/Contents/MacOS/Foo`, so bundled
  /// resources are one directory up in `Contents/Resources`.
  List<String> _resourceCandidates(String name) {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return [
      '${exeDir.path}/$name', // alongside the executable
      '${exeDir.parent.path}/Resources/$name', // macOS .app Resources
    ];
  }
}
