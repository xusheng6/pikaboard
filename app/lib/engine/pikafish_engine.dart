import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'pikafish_bindings.dart';
import 'search_info.dart';

class PikafishEngine {
  PikafishBindings? _bindings;
  bool _initialized = false;

  final _searchInfoController = StreamController<SearchInfo>.broadcast();
  final _bestMoveController = StreamController<BestMove>.broadcast();

  Stream<SearchInfo> get searchInfo => _searchInfoController.stream;
  Stream<BestMove> get bestMove => _bestMoveController.stream;
  bool get isInitialized => _initialized;

  // Pointers to native callbacks to prevent GC
  NativeCallable<PikafishInfoCallbackNative>? _infoCallable;
  NativeCallable<PikafishBestmoveCallbackNative>? _bestmoveCallable;

  Future<void> init() async {
    if (_initialized) return;

    debugPrint('[PikafishEngine] init: starting');

    // On iOS, static libraries are linked into the process
    final lib = DynamicLibrary.process();
    _bindings = PikafishBindings.fromLibrary(lib);
    debugPrint('[PikafishEngine] init: bindings loaded');

    // Ensure NNUE file is available
    final nnueDir = await _ensureNnueFile();
    debugPrint('[PikafishEngine] init: NNUE dir=$nnueDir');

    // Set up native callbacks
    _infoCallable = NativeCallable<PikafishInfoCallbackNative>.listener(
      _onInfoCallback,
    );
    _bestmoveCallable =
        NativeCallable<PikafishBestmoveCallbackNative>.listener(
      _onBestmoveCallback,
    );

    _bindings!.setInfoCallback(_infoCallable!.nativeFunction);
    _bindings!.setBestmoveCallback(_bestmoveCallable!.nativeFunction);
    debugPrint('[PikafishEngine] init: callbacks set, calling pikafish_init...');

    // Initialize engine
    final nnueDirPtr = nnueDir.toNativeUtf8().cast<Char>();
    final result = _bindings!.init(nnueDirPtr);
    malloc.free(nnueDirPtr);
    debugPrint('[PikafishEngine] init: pikafish_init returned $result');

    if (result != 0) {
      throw Exception('Failed to initialize Pikafish engine');
    }

    // Set conservative defaults for mobile
    setOption('Threads', '1');
    setOption('Hash', '16');

    _initialized = true;
    debugPrint('[PikafishEngine] init: done!');
  }

  void setPosition(String fen, {List<String> moves = const []}) {
    if (!_initialized) return;

    final fenPtr = fen.toNativeUtf8().cast<Char>();
    final movesStr = moves.join(' ');
    final movesPtr = movesStr.toNativeUtf8().cast<Char>();

    _bindings!.setPosition(fenPtr, movesPtr);

    malloc.free(fenPtr);
    malloc.free(movesPtr);
  }

  void goInfinite() {
    if (!_initialized) return;
    _bindings!.goInfinite();
  }

  void goDepth(int depth) {
    if (!_initialized) return;
    _bindings!.goDepth(depth);
  }

  void stop() {
    if (!_initialized) return;
    _bindings!.stop();
  }

  void setOption(String name, String value) {
    if (!_initialized && name != 'Threads' && name != 'Hash') return;
    final namePtr = name.toNativeUtf8().cast<Char>();
    final valuePtr = value.toNativeUtf8().cast<Char>();
    _bindings!.setOption(namePtr, valuePtr);
    malloc.free(namePtr);
    malloc.free(valuePtr);
  }

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
  }

  static void _onBestmoveCallback(
    Pointer<Char> bestmovePtr,
    Pointer<Char> ponderPtr,
  ) {
    final bestmove = bestmovePtr.cast<Utf8>().toDartString();
    final ponder = ponderPtr.cast<Utf8>().toDartString();

    final bm = BestMove(
      move: bestmove,
      ponder: ponder.isEmpty ? null : ponder,
    );

    _instance?._bestMoveController.add(bm);
  }

  // Singleton pattern for callback routing
  static PikafishEngine? _instance;

  factory PikafishEngine() {
    _instance ??= PikafishEngine._internal();
    return _instance!;
  }

  PikafishEngine._internal();

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
