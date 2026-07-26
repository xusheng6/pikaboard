import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/engine/process_backend.dart';
import 'package:app/models/position.dart';

/// Drives a real Pikafish process to check the raw UCI stream end to end.
/// Skipped unless the engine is pointed at explicitly, e.g.
///
///     R=build/macos/Build/Products/Debug/app.app/Contents/Resources
///     PIKAFISH_BIN=$R/pikafish PIKAFISH_NNUE=$R/pikafish.nnue flutter test
void main() {
  final binary = Platform.environment['PIKAFISH_BIN'];
  final available = binary != null && File(binary).existsSync();

  test(
    'raw output carries the handshake, commands and search lines',
    () async {
      final backend = ProcessBackend();
      final lines = <String>[];
      final sub = backend.rawOutput.listen(lines.add);

      await backend.init().timeout(const Duration(seconds: 60));
      backend.setPosition(Position.startFen);
      backend.goDepth(6);
      await backend.bestMove.first.timeout(const Duration(seconds: 60));
      // Let the last raw lines drain before tearing the process down.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      backend.dispose();
      await sub.cancel();

      expect(lines, contains('> uci'));
      expect(lines, contains('uciok'));
      expect(lines.any((l) => l.startsWith('> position fen')), isTrue);
      expect(lines.any((l) => l.startsWith('info ')), isTrue);
      expect(lines.any((l) => l.startsWith('bestmove')), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: available ? false : 'set PIKAFISH_BIN to run against a real engine',
  );
}
