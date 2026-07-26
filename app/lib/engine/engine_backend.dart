import 'dart:async';

import 'search_info.dart';

/// Common interface for driving the Pikafish engine, regardless of how the
/// engine is reached: in-process via Dart FFI (mobile) or as a separate
/// process spoken to over UCI (desktop).
///
/// Both backends normalize their output to the same [SearchInfo] / [BestMove]
/// events so the rest of the app never needs to know which transport is in use.
abstract class EngineBackend {
  Stream<SearchInfo> get searchInfo;
  Stream<BestMove> get bestMove;
  bool get isInitialized;

  Future<void> init();
  void setPosition(String fen, {List<String> moves});
  void goInfinite();
  void goDepth(int depth);
  void stop();
  void setOption(String name, String value);
  void dispose();
}
