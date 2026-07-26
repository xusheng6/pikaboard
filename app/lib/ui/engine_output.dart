import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Rolling buffer of the engine conversation, kept outside the widget tree so
/// the log survives tab switches.
///
/// Search output arrives far faster than the screen refreshes, so listeners are
/// notified on a short timer rather than once per line.
class EngineLog extends ChangeNotifier {
  EngineLog({this.maxLines = 4000});

  /// Lines kept before the oldest are dropped.
  final int maxLines;

  // Trimming in blocks keeps the common case (a plain append) cheap.
  static const int _trimBlock = 500;

  final List<String> _lines = [];
  Timer? _notifyTimer;
  int _dropped = 0;

  List<String> get lines => List.unmodifiable(_lines);
  int get length => _lines.length;

  /// How many lines have been dropped off the front of the buffer.
  int get droppedCount => _dropped;

  void add(String line) {
    _lines.add(line);
    if (_lines.length > maxLines + _trimBlock) {
      final drop = _lines.length - maxLines;
      _lines.removeRange(0, drop);
      _dropped += drop;
    }
    _scheduleNotify();
  }

  void clear() {
    _lines.clear();
    _dropped = 0;
    notifyListeners();
  }

  void _scheduleNotify() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 120), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    super.dispose();
  }
}

/// Shows the engine's raw UCI conversation, newest line at the bottom.
class EngineOutputView extends StatelessWidget {
  final EngineLog log;

  const EngineOutputView({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final lines = log.lines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Text(
                    'UCI log',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${lines.length} lines'
                    '${log.droppedCount > 0 ? ' (+${log.droppedCount} dropped)' : ''}',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: lines.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: lines.join('\n')),
                          ),
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy log',
                  ),
                  IconButton(
                    onPressed: lines.isEmpty ? null : log.clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Clear log',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No engine output yet.',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    )
                  : SelectionArea(
                      // Reversed so new output stays pinned at the bottom
                      // without having to drive a scroll controller.
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final line = lines[lines.length - 1 - i];
                          final isCommand = line.startsWith('> ');
                          return Text(
                            line,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              height: 1.35,
                              color: isCommand
                                  ? theme.colorScheme.primary
                                  : null,
                              fontWeight: isCommand
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
