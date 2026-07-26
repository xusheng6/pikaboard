import 'dart:async';
import 'dart:io';

import 'engine_backend.dart';
import 'ffi_backend.dart';
import 'process_backend.dart';
import 'search_info.dart';

/// App-facing engine handle. Delegates to a platform-appropriate
/// [EngineBackend]:
///
///   * Desktop (macOS/Windows/Linux) → [ProcessBackend], driving the Pikafish
///     executable over UCI. The OS allows spawning child processes and this
///     avoids compiling the engine into the app.
///   * Mobile (iOS/Android) → [FfiBackend], with the engine compiled in and
///     reached via FFI, because these platforms forbid launching a separate
///     executable.
class PikafishEngine {
  factory PikafishEngine() => _instance ??= PikafishEngine._internal();

  PikafishEngine._internal() : _backend = _createBackend();

  static PikafishEngine? _instance;

  final EngineBackend _backend;

  static EngineBackend _createBackend() {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return ProcessBackend();
    }
    return FfiBackend();
  }

  Stream<SearchInfo> get searchInfo => _backend.searchInfo;
  Stream<BestMove> get bestMove => _backend.bestMove;
  bool get isInitialized => _backend.isInitialized;

  Future<void> init() => _backend.init();

  void setPosition(String fen, {List<String> moves = const []}) =>
      _backend.setPosition(fen, moves: moves);

  void goInfinite() => _backend.goInfinite();

  void goDepth(int depth) => _backend.goDepth(depth);

  void stop() => _backend.stop();

  void setOption(String name, String value) => _backend.setOption(name, value);

  void dispose() => _backend.dispose();
}
