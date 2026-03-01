import 'dart:ffi';

// -- Native callback types --

typedef PikafishInfoCallbackNative = Void Function(
  Int32 depth,
  Int32 seldepth,
  Int32 multipv,
  Int32 scoreCp,
  Int32 scoreMate,
  Int32 isLowerbound,
  Int32 isUpperbound,
  Uint64 nodes,
  Uint64 nps,
  Uint64 timeMs,
  Int32 hashfull,
  Pointer<Char> pv,
);

typedef PikafishBestmoveCallbackNative = Void Function(
  Pointer<Char> bestmove,
  Pointer<Char> ponder,
);

// -- Native function types --

typedef PikafishInitNative = Int32 Function(Pointer<Char> nnueDir);
typedef PikafishInitDart = int Function(Pointer<Char> nnueDir);

typedef PikafishDestroyNative = Void Function();
typedef PikafishDestroyDart = void Function();

typedef PikafishSetInfoCallbackNative = Void Function(
  Pointer<NativeFunction<PikafishInfoCallbackNative>> cb,
);
typedef PikafishSetInfoCallbackDart = void Function(
  Pointer<NativeFunction<PikafishInfoCallbackNative>> cb,
);

typedef PikafishSetBestmoveCallbackNative = Void Function(
  Pointer<NativeFunction<PikafishBestmoveCallbackNative>> cb,
);
typedef PikafishSetBestmoveCallbackDart = void Function(
  Pointer<NativeFunction<PikafishBestmoveCallbackNative>> cb,
);

typedef PikafishSetPositionNative = Void Function(
  Pointer<Char> fen,
  Pointer<Char> moves,
);
typedef PikafishSetPositionDart = void Function(
  Pointer<Char> fen,
  Pointer<Char> moves,
);

typedef PikafishGoDepthNative = Void Function(Int32 depth);
typedef PikafishGoDepthDart = void Function(int depth);

typedef PikafishGoInfiniteNative = Void Function();
typedef PikafishGoInfiniteDart = void Function();

typedef PikafishStopNative = Void Function();
typedef PikafishStopDart = void Function();

typedef PikafishWaitNative = Void Function();
typedef PikafishWaitDart = void Function();

typedef PikafishSetOptionNative = Void Function(
  Pointer<Char> name,
  Pointer<Char> value,
);
typedef PikafishSetOptionDart = void Function(
  Pointer<Char> name,
  Pointer<Char> value,
);

/// Resolved native function pointers for the Pikafish bridge.
class PikafishBindings {
  final PikafishInitDart init;
  final PikafishDestroyDart destroy;
  final PikafishSetInfoCallbackDart setInfoCallback;
  final PikafishSetBestmoveCallbackDart setBestmoveCallback;
  final PikafishSetPositionDart setPosition;
  final PikafishGoDepthDart goDepth;
  final PikafishGoInfiniteDart goInfinite;
  final PikafishStopDart stop;
  final PikafishWaitDart wait;
  final PikafishSetOptionDart setOption;

  PikafishBindings._({
    required this.init,
    required this.destroy,
    required this.setInfoCallback,
    required this.setBestmoveCallback,
    required this.setPosition,
    required this.goDepth,
    required this.goInfinite,
    required this.stop,
    required this.wait,
    required this.setOption,
  });

  factory PikafishBindings.fromLibrary(DynamicLibrary lib) {
    return PikafishBindings._(
      init: lib
          .lookup<NativeFunction<PikafishInitNative>>('pikafish_init')
          .asFunction<PikafishInitDart>(),
      destroy: lib
          .lookup<NativeFunction<PikafishDestroyNative>>('pikafish_destroy')
          .asFunction<PikafishDestroyDart>(),
      setInfoCallback: lib
          .lookup<NativeFunction<PikafishSetInfoCallbackNative>>(
              'pikafish_set_info_callback')
          .asFunction<PikafishSetInfoCallbackDart>(),
      setBestmoveCallback: lib
          .lookup<NativeFunction<PikafishSetBestmoveCallbackNative>>(
              'pikafish_set_bestmove_callback')
          .asFunction<PikafishSetBestmoveCallbackDart>(),
      setPosition: lib
          .lookup<NativeFunction<PikafishSetPositionNative>>(
              'pikafish_set_position')
          .asFunction<PikafishSetPositionDart>(),
      goDepth: lib
          .lookup<NativeFunction<PikafishGoDepthNative>>('pikafish_go_depth')
          .asFunction<PikafishGoDepthDart>(),
      goInfinite: lib
          .lookup<NativeFunction<PikafishGoInfiniteNative>>(
              'pikafish_go_infinite')
          .asFunction<PikafishGoInfiniteDart>(),
      stop: lib
          .lookup<NativeFunction<PikafishStopNative>>('pikafish_stop')
          .asFunction<PikafishStopDart>(),
      wait: lib
          .lookup<NativeFunction<PikafishWaitNative>>('pikafish_wait')
          .asFunction<PikafishWaitDart>(),
      setOption: lib
          .lookup<NativeFunction<PikafishSetOptionNative>>(
              'pikafish_set_option')
          .asFunction<PikafishSetOptionDart>(),
    );
  }
}
