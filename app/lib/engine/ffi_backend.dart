import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'engine_backend.dart';
import 'pikafish_bindings.dart';
import 'search_info.dart';

/// In-process engine backend used on mobile (iOS/Android), where the OS
/// forbids spawning a separate executable. The Pikafish sources are compiled
/// into the app and reached through Dart FFI.
class FfiBackend implements EngineBackend {
  FfiBackend() {
    _instance = this;
  }

  PikafishBindings? _bindings;
  bool _initialized = false;

  final _searchInfoController = StreamController<SearchInfo>.broadcast();
  final _bestMoveController = StreamController<BestMove>.broadcast();
  final _rawController = StreamController<String>.broadcast();

  @override
  Stream<SearchInfo> get searchInfo => _searchInfoController.stream;
  @override
  Stream<BestMove> get bestMove => _bestMoveController.stream;

  /// The bridge hands us parsed callbacks rather than the engine's stdout, so
  /// the raw view is fed UCI lines rebuilt from that data.
  @override
  Stream<String> get rawOutput => _rawController.stream;

  void _emitRaw(String line) {
    if (!_rawController.isClosed) _rawController.add(line);
  }

  @override
  bool get isInitialized => _initialized;

  // Pointers to native callbacks to prevent GC
  NativeCallable<PikafishInfoCallbackNative>? _infoCallable;
  NativeCallable<PikafishBestmoveCallbackNative>? _bestmoveCallable;

  @override
  Future<void> init() async {
    if (_initialized) return;

    debugPrint('[FfiBackend] init: starting');

    // On iOS, static libraries are linked into the process
    final lib = DynamicLibrary.process();
    _bindings = PikafishBindings.fromLibrary(lib);
    debugPrint('[FfiBackend] init: bindings loaded');

    // Ensure NNUE file is available
    final nnueDir = await _ensureNnueFile();
    debugPrint('[FfiBackend] init: NNUE dir=$nnueDir');

    // Set up native callbacks
    _infoCallable = NativeCallable<PikafishInfoCallbackNative>.listener(
      _onInfoCallback,
    );
    _bestmoveCallable = NativeCallable<PikafishBestmoveCallbackNative>.listener(
      _onBestmoveCallback,
    );

    _bindings!.setInfoCallback(_infoCallable!.nativeFunction);
    _bindings!.setBestmoveCallback(_bestmoveCallable!.nativeFunction);
    debugPrint('[FfiBackend] init: callbacks set, calling pikafish_init...');

    // Initialize engine
    final nnueDirPtr = nnueDir.toNativeUtf8().cast<Char>();
    final result = _bindings!.init(nnueDirPtr);
    malloc.free(nnueDirPtr);
    debugPrint('[FfiBackend] init: pikafish_init returned $result');

    if (result != 0) {
      throw Exception('Failed to initialize Pikafish engine');
    }

    // Use all available cores; scale hash with thread count
    final cores = Platform.numberOfProcessors;
    setOption('Threads', '$cores');
    setOption('Hash', '${cores * 16}');

    _initialized = true;
    debugPrint('[FfiBackend] init: done!');
  }

  @override
  void setPosition(String fen, {List<String> moves = const []}) {
    if (!_initialized) return;

    final movesStr = moves.join(' ');
    _emitRaw(
      '> position fen $fen${movesStr.isEmpty ? '' : ' moves $movesStr'}',
    );
    final fenPtr = fen.toNativeUtf8().cast<Char>();
    final movesPtr = movesStr.toNativeUtf8().cast<Char>();

    _bindings!.setPosition(fenPtr, movesPtr);

    malloc.free(fenPtr);
    malloc.free(movesPtr);
  }

  @override
  void goInfinite() {
    if (!_initialized) return;
    _emitRaw('> go infinite');
    _bindings!.goInfinite();
  }

  @override
  void goDepth(int depth) {
    if (!_initialized) return;
    _emitRaw('> go depth $depth');
    _bindings!.goDepth(depth);
  }

  @override
  void stop() {
    if (!_initialized) return;
    _emitRaw('> stop');
    _bindings!.stop();
  }

  @override
  void setOption(String name, String value) {
    if (!_initialized && name != 'Threads' && name != 'Hash') return;
    _emitRaw('> setoption name $name value $value');
    final namePtr = name.toNativeUtf8().cast<Char>();
    final valuePtr = value.toNativeUtf8().cast<Char>();
    _bindings!.setOption(namePtr, valuePtr);
    malloc.free(namePtr);
    malloc.free(valuePtr);
  }

  @override
  void dispose() {
    if (_initialized) {
      _bindings?.stop();
      _bindings?.wait();
      _bindings?.destroy();
      _initialized = false;
    }
    _infoCallable?.close();
    _bestmoveCallable?.close();
    _searchInfoController.close();
    _bestMoveController.close();
    _rawController.close();
  }

  static void _onInfoCallback(
    int depth,
    int seldepth,
    int multipv,
    int scoreCp,
    int scoreMate,
    int isLowerbound,
    int isUpperbound,
    int nodes,
    int nps,
    int timeMs,
    int hashfull,
    Pointer<Char> pvPtr,
  ) {
    final pvStr = pvPtr.cast<Utf8>().toDartString();
    final pv = pvStr.isEmpty ? <String>[] : pvStr.split(' ');

    final info = SearchInfo(
      depth: depth,
      selDepth: seldepth,
      multiPV: multipv,
      scoreCp: scoreMate != 0 ? null : scoreCp,
      scoreMate: scoreMate != 0 ? scoreMate : null,
      isLowerbound: isLowerbound != 0,
      isUpperbound: isUpperbound != 0,
      nodes: nodes,
      nps: nps,
      timeMs: timeMs,
      hashfull: hashfull,
      pv: pv,
    );

    // Since this is a listener callback, it's already on the Dart side
    _instance?._searchInfoController.add(info);
    _instance?._emitRaw(_infoLine(info));
  }

  /// Rebuild the UCI `info` line the engine would have printed.
  static String _infoLine(SearchInfo i) {
    final score = i.scoreMate != null
        ? 'mate ${i.scoreMate}'
        : 'cp ${i.scoreCp ?? 0}';
    final bound = i.isLowerbound
        ? ' lowerbound'
        : i.isUpperbound
        ? ' upperbound'
        : '';
    return 'info depth ${i.depth} seldepth ${i.selDepth} '
        'multipv ${i.multiPV} score $score$bound nodes ${i.nodes} '
        'nps ${i.nps} hashfull ${i.hashfull} time ${i.timeMs} '
        'pv ${i.pv.join(' ')}';
  }

  static void _onBestmoveCallback(
    Pointer<Char> bestmovePtr,
    Pointer<Char> ponderPtr,
  ) {
    final bestmove = bestmovePtr.cast<Utf8>().toDartString();
    final ponder = ponderPtr.cast<Utf8>().toDartString();

    final bm = BestMove(move: bestmove, ponder: ponder.isEmpty ? null : ponder);

    _instance?._bestMoveController.add(bm);
    _instance?._emitRaw(
      'bestmove $bestmove${ponder.isEmpty ? '' : ' ponder $ponder'}',
    );
  }

  // Static reference for routing native callbacks back to this instance.
  static FfiBackend? _instance;

  /// Ensure pikafish.nnue is available in the documents directory.
  Future<String> _ensureNnueFile() async {
    final docDir = await getApplicationDocumentsDirectory();
    final nnuePath = '${docDir.path}/pikafish.nnue';
    final nnueFile = File(nnuePath);

    if (!await nnueFile.exists()) {
      // Copy from Flutter assets
      final data = await rootBundle.load('assets/pikafish.nnue');
      await nnueFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }

    // Return directory path (engine appends the filename)
    return '${docDir.path}/';
  }
}
