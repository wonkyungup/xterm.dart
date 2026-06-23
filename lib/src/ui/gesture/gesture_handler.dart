import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  /// Buffer cell where the current mouse drag-selection started. Captured once
  /// at drag start so the selection base stays glued to the same content even
  /// if the viewport scrolls mid-drag. Null for non-mouse (word-select) drags.
  CellOffset? _dragStartCell;

  /// Latest drag position (local to the terminal) during a mouse drag-select.
  /// Used by the edge auto-scroll timer to keep extending the selection.
  Offset? _lastDragLocalPosition;

  /// Repeats while the drag is held past the top/bottom edge, scrolling the
  /// viewport so the selection can extend beyond the visible area.
  Timer? _autoScrollTimer;

  LongPressStartDetails? _lastLongPressStartDetails;

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      // onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDoubleTapDown: onDoubleTapDown,
    );
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;
    _lastDragLocalPosition = details.localPosition;

    if (details.kind == PointerDeviceKind.mouse) {
      _dragStartCell = renderTerminal.getCellOffset(details.localPosition);
      renderTerminal.selectCharacters(details.localPosition);
    } else {
      _dragStartCell = null;
      renderTerminal.selectWord(details.localPosition);
    }
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragLocalPosition = details.localPosition;
    final base = _dragStartCell;
    if (base != null) {
      renderTerminal.selectCharactersFrom(base, details.localPosition);
      _updateAutoScroll();
    } else {
      renderTerminal.selectCharacters(
        _lastDragStartDetails!.localPosition,
        details.localPosition,
      );
    }
  }

  void onDragEnd(DragEndDetails details) {
    _stopAutoScroll();
    _dragStartCell = null;
    _lastDragLocalPosition = null;
  }

  /// Starts the edge auto-scroll timer if the latest drag position is past the
  /// top/bottom edge of the viewport, otherwise stops it.
  void _updateAutoScroll() {
    final pos = _lastDragLocalPosition;
    if (pos == null || _dragStartCell == null) {
      _stopAutoScroll();
      return;
    }
    final height = renderTerminal.viewportHeight;
    if (pos.dy >= 0 && pos.dy <= height) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??=
        Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  /// One auto-scroll step: scroll the viewport toward the edge the pointer is
  /// past, then re-extend the selection to the content now under the pointer.
  void _autoScrollTick() {
    final pos = _lastDragLocalPosition;
    final base = _dragStartCell;
    if (pos == null || base == null) {
      _stopAutoScroll();
      return;
    }
    final controller = terminalView.scrollController;
    if (!controller.hasClients) {
      _stopAutoScroll();
      return;
    }

    final height = renderTerminal.viewportHeight;
    final double overshoot;
    if (pos.dy < 0) {
      overshoot = pos.dy; // negative → scroll up
    } else if (pos.dy > height) {
      overshoot = pos.dy - height; // positive → scroll down
    } else {
      _stopAutoScroll();
      return;
    }

    // A few pixels per tick, faster the further past the edge (capped).
    final step = overshoot.sign * (4.0 + overshoot.abs() / 8.0).clamp(4.0, 40.0);
    final position = controller.position;
    final target = (position.pixels + step)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      controller.jumpTo(target);
    }
    renderTerminal.selectCharactersFrom(base, pos);
  }
}
