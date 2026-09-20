// home_shell.dart
// -----------------------------------------------------------------------------
// Composes the app's first scene: MenuScreen sits full-bleed in the
// background; the terminal is a panel pinned to the bottom that the user
// drags up by its handle to open, and drags back down to collapse.
//
// Deliberately NOT built on DraggableScrollableSheet: that widget ties its
// drag gesture to an inner scrollable's ScrollController, which fights with
// the terminal log's own ListView once both want to interpret vertical
// drags (open-the-sheet vs. scroll-the-log). Instead, the drag gesture here
// is scoped to just the handle bar, and the panel's height is driven
// directly by a single AnimationController — simpler, and it means the log
// scrolls normally the instant the panel is open with zero gesture conflict.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'theme.dart';
import 'menu_screen.dart';
import 'terminal_panel.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  // Height of just the grab-bar row. This is the ONLY thing visible when
  // the panel is fully collapsed — the log and input bar are hidden
  // entirely below the screen edge in that state (see the OverflowBox
  // trick in build() below), not just squeezed thin.
  static const double _handleHeight = 44;

  // A small fixed buffer against sub-pixel rounding. Flutter's debug
  // overflow banner fires on overflows as small as a fraction of a
  // logical pixel, and the peek height here is built from several
  // separately-computed doubles (screen height minus insets minus
  // clearance, multiplied by an animation fraction) — floating-point
  // arithmetic on those can legitimately land a hair short. This costs
  // nothing visually but eliminates that class of 1px overflow.
  static const double _roundingSlack = 2;

  // Leaves this much clearance at the very top when fully expanded, so the
  // panel never covers the status bar / notch area.
  static const double _topClearance = 24;

  late final AnimationController _controller;
  final FocusNode _terminalInputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0.0, // starts collapsed — menu is the first thing the user sees
    )..addListener(_handleControllerValueChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerValueChanged);
    _controller.dispose();
    _terminalInputFocusNode.dispose();
    super.dispose();
  }

  /// Belt-and-suspenders focus drop: the moment the panel is fully
  /// collapsed (value == 0.0), forcibly unfocus the terminal input.
  ///
  /// Without this, the FocusNode can remain the route's remembered
  /// "primary focus" even though the panel is visually clipped away by
  /// OverflowBox — it's still in the tree, just invisible. Flutter then
  /// restores focus to it (and pops the keyboard back up) whenever focus
  /// returns to this route, e.g. after popping back from a pushed module
  /// screen in MenuScreen. This listener catches every path that lands the
  /// panel at value 0 — drag-to-close, fling-to-close, handle tap, and the
  /// back-button close in _closeTerminal — not just the ones that
  /// explicitly call unfocus() themselves.
  void _handleControllerValueChanged() {
    if (_controller.value == 0.0) {
      _terminalInputFocusNode.unfocus();
    }
  }

  void _onHandleDragUpdate(DragUpdateDetails details, double dragRange) {
    if (dragRange <= 0) return;
    // Dragging up (negative dy) should increase openness, hence the minus.
    final delta = -details.primaryDelta! / dragRange;
    _controller.value = (_controller.value + delta).clamp(0.0, 1.0);
  }

  void _onHandleDragEnd(DragEndDetails details) {
    const flingThreshold =
        300.0; // px/s — below this, go by position not velocity
    final velocity = details.primaryVelocity ?? 0.0;

    late final double target;
    if (velocity.abs() > flingThreshold) {
      target = velocity < 0
          ? 1.0
          : 0.0; // flung up -> open, flung down -> close
    } else {
      target = _controller.value > 0.5 ? 1.0 : 0.0; // otherwise snap to nearest
    }
    // Drop focus right away rather than waiting for the animation (and the
    // _handleControllerValueChanged listener) to reach 0 — this closes the
    // keyboard in step with the panel instead of a beat behind it.
    if (target == 0.0) {
      _terminalInputFocusNode.unfocus();
    }
    _controller.animateTo(target, curve: Curves.easeOutCubic);
  }

  /// Collapses the terminal back to peek height. Used by both the drag
  /// handle and the hardware/gesture back button.
  void _closeTerminal() {
    _terminalInputFocusNode.unfocus();
    _controller.animateTo(0.0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topInset = MediaQuery.of(context).padding.top;
        // The Android system nav bar (3-button bar or gesture pill) sits in
        // this bottom inset. The panel is pinned flush to the physical
        // bottom edge, so without accounting for this the input bar either
        // renders partly underneath the system UI or gets squeezed by
        // exactly this many pixels — which is what was overflowing.
        final bottomInset = MediaQuery.of(context).padding.bottom;

        final peekHeight = _handleHeight + bottomInset + _roundingSlack;
        final expandedHeight = constraints.maxHeight - topInset - _topClearance;
        final dragRange = expandedHeight - peekHeight;

        // The maximum height the log+divider+input block could ever need —
        // i.e. its size once the panel is fully open. TerminalPanel is
        // always laid out at exactly this height (see the SizedBox below),
        // regardless of how much of it is actually visible right now. That
        // is what lets the collapsed state show nothing but the handle:
        // instead of asking TerminalPanel to physically shrink below its
        // real minimum size (which is what caused the earlier overflow),
        // it keeps its full natural size and OverflowBox simply reveals or
        // hides it through a smaller window.
        final terminalContentHeight = expandedHeight - _handleHeight;

        // The Stack (menu + panel) is built exactly once per layout pass and
        // handed down as `child` to the outer AnimatedBuilder below, so
        // re-evaluating canPop on every animation tick never triggers a
        // rebuild of the menu list or the terminal log — only the thin
        // PopScope wrapper reacts to the controller.
        final content = Stack(
          children: [
            // Background: the clickable menu. Always laid out full-size and
            // always interactive.
            const Positioned.fill(child: MenuScreen()),

            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final currentHeight =
                    peekHeight +
                    (expandedHeight - peekHeight) * _controller.value;
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: currentHeight,
                  child: child!,
                );
              },
              // Built once, not on every animation tick — AnimatedBuilder
              // passes it through as `child` unchanged.
              child: Container(
                decoration: const BoxDecoration(
                  color: RedLineColors.background,
                  border: Border(
                    top: BorderSide(color: RedLineColors.accent, width: 1),
                  ),
                ),
                // SafeArea (bottom only — top is already handled by
                // _topClearance) reserves exactly `bottomInset` at the
                // bottom of whatever height this container currently has,
                // so the input row is never drawn under the system nav bar.
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) =>
                            _onHandleDragUpdate(d, dragRange),
                        onVerticalDragEnd: _onHandleDragEnd,
                        // Tapping the handle also toggles — a quick tap is
                        // often easier than a drag on a small target.
                        onTap: () {
                          final target = _controller.value > 0.5 ? 0.0 : 1.0;
                          if (target == 0.0) {
                            _terminalInputFocusNode.unfocus();
                          }
                          _controller.animateTo(
                            target,
                            curve: Curves.easeOutCubic,
                          );
                        },
                        child: const _DragHandle(height: _handleHeight),
                      ),
                      // ClipRect + OverflowBox: give TerminalPanel a fixed,
                      // always-comfortable height (terminalContentHeight)
                      // no matter how little vertical space this Expanded
                      // currently has, then clip whatever doesn't fit.
                      // OverflowBox is explicitly designed to let a child
                      // render bigger than its box and clip silently — no
                      // RenderFlex overflow warning, and no forcing the
                      // log/divider/input to actually squeeze. When
                      // collapsed, this Expanded has almost no height, so
                      // essentially the whole TerminalPanel — log AND
                      // input bar — is clipped away, leaving only the
                      // handle visible above.
                      Expanded(
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight: 0,
                            maxHeight: terminalContentHeight,
                            child: SizedBox(
                              height: terminalContentHeight,
                              child: TerminalPanel(
                                focusNode: _terminalInputFocusNode,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // While the terminal is open (or mid-drag), swallow the system
            // back gesture/button ourselves and just collapse the panel —
            // "back" should feel like "return to the main menu", not "quit
            // the app". Only once it's fully collapsed do we let a real pop
            // go through (which, at the root route, exits the app as usual).
            final terminalIsOpen = _controller.value > 0.02;
            return PopScope(
              canPop: !terminalIsOpen,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                _closeTerminal();
              },
              child: child!,
            );
          },
          child: Scaffold(
            backgroundColor: RedLineColors.background,
            // We compute the panel's height ourselves from MediaQuery
            // insets (see peekHeight/expandedHeight above). Leaving this
            // true would let Flutter ALSO shrink the whole body when the
            // keyboard opens, on top of our own math — the two fighting
            // over the same space is what was hiding the top of the log.
            // TerminalPanel handles the keyboard inset itself instead (see
            // terminal_panel.dart).
            resizeToAvoidBottomInset: false,
            body: content,
          ),
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: RedLineColors.accentDim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'TERMINAL',
            style: TextStyle(
              fontFamily: kTerminalFontFamily,
              color: RedLineColors.accent,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
