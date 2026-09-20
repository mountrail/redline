// terminal_panel.dart
// -----------------------------------------------------------------------------
// The terminal's log + input content, WITHOUT its own Scaffold/AppBar — it
// is embedded inside the draggable sheet built by home_shell.dart, not used
// as a standalone route. All the original performance notes still apply:
// ListView.builder for the log, no blocking calls in the command path.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'command_interpreter.dart';
import 'theme.dart';

/// Fixed height of the bottom input bar. Exported so HomeShell can compute
/// an exact, overflow-safe collapsed ("peek") height for the whole panel —
/// the peek state must always be at least (handle + divider + this) tall,
/// or the input row has nowhere to go and Flutter reports a RenderFlex
/// overflow (the yellow/black hazard stripes).
const double kTerminalInputBarHeight = 44;

/// Height of the thin divider between the log and the input bar. Kept as a
/// named constant for the same reason as the height above — HomeShell needs
/// the exact figure, not a guess, to size the collapsed panel correctly.
const double kTerminalDividerHeight = 1;

/// Extra breathing room below the input row itself, separate from the
/// system nav bar inset (handled in HomeShell) and the keyboard inset
/// (handled below) — just a bit of visual space so the prompt doesn't sit
/// flush against whatever's beneath it.
const double kTerminalInputBottomSpacing = 10;

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.focusNode});

  // Owned by HomeShell, not this widget — HomeShell needs to force-unfocus
  // it the moment the panel is dragged down, which it can't do to a
  // FocusNode buried inside this State's private fields.
  final FocusNode focusNode;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final CommandInterpreter _interpreter = CommandInterpreter();

  final List<TerminalLine> _history = [
    const TerminalLine('REDLINE OS v1.0 — SECURE SHELL INITIALIZED'),
    const TerminalLine("TYPE 'help' FOR AVAILABLE COMMANDS."),
  ];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Tracks the keyboard height across builds so we can tell when it just
  // opened or closed (see build() below) and nudge the log back into view
  // at that moment, rather than only after the next submitted command.
  double _lastBottomInset = 0;

  // True while a scripted animation (currently just `hack`) is playing.
  // Real commands can't interleave with it — see _submit — since the
  // animation drives _history with its own timed setState calls and
  // letting a normal command's output land in the middle would garble
  // both. The input field itself stays enabled and focused throughout;
  // this only gates what submitting does, it never touches focus/keyboard.
  bool _isAnimating = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    // focusNode is owned by HomeShell — it disposes it, not us.
    super.dispose();
  }

  void _submit(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    // Echo the command immediately, then clear the field — same for every
    // command, animated or not.
    setState(() {
      _history.add(TerminalLine('redline@sys:~# $raw', isPrompt: true));
    });
    _inputController.clear();

    if (_isAnimating) {
      // A sequence is already mid-playback and driving _history with its
      // own timed updates — don't let a normal command's output land in
      // the middle of that.
      setState(() {
        _history.add(
          const TerminalLine(
            'SYSTEM BUSY — SEQUENCE IN PROGRESS.',
            isError: true,
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    final cmd = trimmed.split(RegExp(r'\s+')).first.toLowerCase();
    if (CommandInterpreter.animatedCommands.contains(cmd)) {
      final args = trimmed.split(RegExp(r'\s+')).skip(1).toList();
      _playHackSequence(_interpreter.buildHackFrames(args));
      return;
    }

    // `run()` is synchronous and cheap by contract (see command_interpreter.dart).
    // If it ever needs to host a genuinely slow command, that command must
    // schedule its own Future and push results back via setState later —
    // this call site itself must never be awaited/blocked.
    final result = _interpreter.run(raw);

    setState(() {
      if (result == null) {
        _history.clear();
      } else {
        _history.addAll(result);
      }
    });

    _scrollToBottom();
  }

  /// Plays a scripted sequence (currently only `hack`) back frame by frame,
  /// waiting each frame's real delay via `Future.delayed` between
  /// `setState` calls. This is exactly the pattern documented in
  /// command_interpreter.dart for slow commands: the interpreter itself
  /// stays synchronous, and the time-spreading happens here at the call
  /// site, so the input field and scrolling are never blocked mid-sequence
  /// — only gated by `_isAnimating` in `_submit` above.
  Future<void> _playHackSequence(List<HackFrame> frames) async {
    setState(() => _isAnimating = true);

    for (final frame in frames) {
      await Future.delayed(frame.delay);
      if (!mounted) return; // panel could be disposed mid-sequence
      setState(() {
        if (frame.replacesLast && _history.isNotEmpty) {
          _history[_history.length - 1] = frame.line;
        } else {
          _history.add(frame.line);
        }
      });
      _scrollToBottom();
    }

    if (!mounted) return;
    setState(() => _isAnimating = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    // HomeShell sets resizeToAvoidBottomInset: false and gives this widget
    // a fixed height regardless of the keyboard, specifically so nothing
    // else fights over that space. We read the keyboard's own height here
    // and push our content up above it ourselves — the log's Expanded
    // simply shrinks to make room, exactly like it already does when the
    // panel is dragged to a smaller height.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset != _lastBottomInset) {
      _lastBottomInset = bottomInset;
      // The keyboard just opened or closed — keep the most recent lines in
      // view rather than leaving the scroll position wherever it happened
      // to be relative to the now-resized log viewport.
      _scrollToBottom();
    }

    // No Scaffold here — this widget only ever fills whatever box the
    // draggable panel in HomeShell gives it.
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        children: [
          // Wrapped in ClipRect: when the panel is collapsed, this Expanded
          // is squeezed to zero — a flexible widget shrinking to 0 is
          // always safe (unlike the fixed-size divider and input bar
          // below, which must never be asked to render smaller than their
          // real size).
          Expanded(
            child: ClipRect(
              child: _TerminalLog(
                history: _history,
                scrollController: _scrollController,
              ),
            ),
          ),
          const Divider(height: kTerminalDividerHeight),
          _CommandInputLine(
            controller: _inputController,
            focusNode: widget.focusNode,
            onSubmit: _submit,
          ),
          // Was declared but never actually placed in the layout — this is
          // the breathing room below the prompt row, ahead of the keyboard
          // inset padding and (via HomeShell) the system nav bar inset.
          const SizedBox(height: kTerminalInputBottomSpacing),
        ],
      ),
    );
  }
}

class _TerminalLog extends StatelessWidget {
  const _TerminalLog({required this.history, required this.scrollController});

  final List<TerminalLine> history;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: history.length,
      itemExtent: 20,
      itemBuilder: (context, index) {
        final line = history[index];
        return _TerminalLogRow(line: line);
      },
    );
  }
}

class _TerminalLogRow extends StatelessWidget {
  const _TerminalLogRow({required this.line});

  final TerminalLine line;

  @override
  Widget build(BuildContext context) {
    final Color color = line.isError
        ? RedLineColors.accent
        : line.isPrompt
        ? RedLineColors.accent
        : RedLineColors.textMuted;

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        line.text,
        style: TextStyle(
          fontFamily: kTerminalFontFamily,
          color: color,
          fontSize: 13,
          fontWeight: line.isPrompt ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CommandInputLine extends StatelessWidget {
  const _CommandInputLine({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    // A hard SizedBox height (rather than relying on padding + intrinsic
    // text-field height, which varies slightly by platform font metrics) is
    // what lets HomeShell compute an exact, guaranteed-safe peek height via
    // kTerminalInputBarHeight — no guessing, no overflow.
    return SizedBox(
      height: kTerminalInputBarHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: RedLineColors.background,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'redline@sys:~#',
              style: TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                // Not autofocused: the panel starts collapsed off-screen, so
                // grabbing focus (and popping the keyboard) on app launch
                // would be jarring and would fight the menu for attention.
                autofocus: false,
                cursorColor: RedLineColors.accent,
                style: const TextStyle(
                  fontFamily: kTerminalFontFamily,
                  color: RedLineColors.accent,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (value) {
                  onSubmit(value);
                  focusNode.requestFocus();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
