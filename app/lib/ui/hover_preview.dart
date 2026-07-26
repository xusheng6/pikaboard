import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/position.dart';
import '../models/settings.dart';
import 'board_widget.dart';

/// Places a preview of [size] beside [pointer] (in window coordinates) without
/// letting it leave the window: it flips to the other side of the pointer when
/// it would overflow, and is clamped as a last resort.
Positioned placePreview({
  required Size screen,
  required Offset pointer,
  required Size size,
  required Widget child,
}) {
  const gap = 18.0;
  const margin = 8.0;

  var left = pointer.dx + gap;
  if (left + size.width > screen.width - margin) {
    left = pointer.dx - gap - size.width;
  }
  var top = pointer.dy + gap;
  if (top + size.height > screen.height - margin) {
    top = pointer.dy - gap - size.height;
  }

  final maxLeft = math.max(margin, screen.width - size.width - margin);
  final maxTop = math.max(margin, screen.height - size.height - margin);
  return Positioned(
    left: left.clamp(margin, maxLeft),
    top: top.clamp(margin, maxTop),
    width: size.width,
    child: IgnorePointer(child: child),
  );
}

/// Shows [previewBuilder] beside the pointer while [child] is hovered.
///
/// The card is drawn in the app's overlay rather than inside whatever widget
/// raised it, so a panel's bounds cannot clip it, and it is kept inside the
/// window: it flips to the other side of the pointer when it would run off an
/// edge, and is clamped in both directions as a last resort.
class HoverPreview extends StatefulWidget {
  final Widget child;

  /// Built each time the card is shown or moved.
  final WidgetBuilder previewBuilder;

  /// How much room to reserve when placing the card.
  final Size previewSize;

  /// When false the child is returned untouched, so previews can be switched
  /// off without restructuring the tree.
  final bool enabled;

  const HoverPreview({
    super.key,
    required this.child,
    required this.previewBuilder,
    required this.previewSize,
    this.enabled = true,
  });

  @override
  State<HoverPreview> createState() => _HoverPreviewState();
}

class _HoverPreviewState extends State<HoverPreview> {
  final _controller = OverlayPortalController();
  Offset _pointer = Offset.zero;

  void _moveTo(Offset globalPosition) {
    if (!widget.enabled) return;
    setState(() => _pointer = globalPosition);
    if (!_controller.isShowing) _controller.show();
  }

  void _hide() {
    if (_controller.isShowing) _controller.hide();
  }

  @override
  void didUpdateWidget(HoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hide();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (overlayContext) => placePreview(
        screen: MediaQuery.sizeOf(overlayContext),
        pointer: _pointer,
        size: widget.previewSize,
        child: widget.previewBuilder(overlayContext),
      ),
      child: MouseRegion(
        onEnter: (event) => _moveTo(event.position),
        onHover: (event) => _moveTo(event.position),
        onExit: (_) => _hide(),
        child: widget.child,
      ),
    );
  }
}

/// One labelled line under a preview board, e.g. the engine's move against the
/// move actually played.
class PreviewRow {
  final String label;
  final String text;
  final Color colour;
  final String? trailing;

  const PreviewRow({
    required this.label,
    required this.text,
    required this.colour,
    this.trailing,
  });
}

/// The card itself: a heading, the position, and any explanatory rows.
class MovePreviewCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Position position;
  final List<BoardArrow> arrows;
  final List<PreviewRow> rows;
  final DisplayLanguage language;

  /// Draw the preview rotated, matching a board being viewed from Black's side.
  final bool viewFromBlack;

  /// Board width inside the card. Big enough to read the pieces at a glance.
  static const double boardWidth = 300;

  const MovePreviewCard({
    super.key,
    required this.title,
    required this.position,
    this.subtitle,
    this.arrows = const [],
    this.rows = const [],
    this.language = DisplayLanguage.simplified,
    this.viewFromBlack = false,
  });

  /// Room the card needs, so [HoverPreview] can place it before building it.
  static Size sizeFor({required int rowCount, bool hasSubtitle = false}) {
    // 9:10 board, plus heading, rows and padding.
    const boardHeight = boardWidth * 10 / 9;
    return Size(
      boardWidth + 20,
      boardHeight + 34 + (hasSubtitle ? 16 : 0) + rowCount * 19 + 16,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: theme.hintColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: boardWidth,
              child: BoardWidget(
                position: position,
                arrows: arrows,
                language: language,
                viewFromBlack: viewFromBlack,
              ),
            ),
            for (final row in rows) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: row.colour,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    row.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.hintColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      row.text,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (row.trailing != null)
                    Text(
                      row.trailing!,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.hintColor,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
