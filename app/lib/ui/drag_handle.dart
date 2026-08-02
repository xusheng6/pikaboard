import 'package:flutter/material.dart';

/// A thin splitter that resizes the panes it sits between.
///
/// [axis] is the bar's own direction: [Axis.vertical] draws a vertical bar that
/// is dragged left and right, [Axis.horizontal] a horizontal one dragged up and
/// down. [onDrag] receives the pointer movement along the drag direction in
/// logical pixels, [onDragEnd] fires once the gesture is over (the moment to
/// persist the new size), and a double-tap calls [onReset] to hand the pane
/// back to the automatic layout.
class DragHandle extends StatefulWidget {
  final Axis axis;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;

  /// Width of a vertical bar, height of a horizontal one. Only a hairline is
  /// painted; the rest is there to make the handle easy to grab.
  final double thickness;

  /// Length of the painted grip. A vertical bar centres it top to bottom.
  final double gripLength;

  final String? tooltip;

  const DragHandle({
    super.key,
    required this.axis,
    required this.onDrag,
    this.onDragEnd,
    this.onReset,
    this.thickness = 8,
    this.gripLength = 36,
    this.tooltip,
  });

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle> {
  bool _hovering = false;
  bool _dragging = false;

  bool get _vertical => widget.axis == Axis.vertical;

  void _end() {
    setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _hovering || _dragging;
    final color = active ? theme.colorScheme.primary : theme.dividerColor;

    // The hairline keeps the panes visually separated; the grip on top of it
    // says the separator can be moved.
    Widget bar = Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: _vertical ? 1 : double.infinity,
          height: _vertical ? double.infinity : 1,
          color: theme.dividerColor,
        ),
        Container(
          width: _vertical ? (active ? 4 : 3) : widget.gripLength,
          height: _vertical ? widget.gripLength : (active ? 4 : 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );

    if (widget.tooltip != null) {
      bar = Tooltip(message: widget.tooltip!, child: bar);
    }

    return MouseRegion(
      cursor: _vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: _vertical
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragUpdate: _vertical
            ? (d) => widget.onDrag(d.delta.dx)
            : null,
        onHorizontalDragEnd: _vertical ? (_) => _end() : null,
        onHorizontalDragCancel: _vertical ? _end : null,
        onVerticalDragStart: _vertical
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: _vertical
            ? null
            : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: _vertical ? null : (_) => _end(),
        onVerticalDragCancel: _vertical ? null : _end,
        child: SizedBox(
          width: _vertical ? widget.thickness : double.infinity,
          height: _vertical ? double.infinity : widget.thickness,
          child: bar,
        ),
      ),
    );
  }
}
