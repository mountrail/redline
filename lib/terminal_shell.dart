// terminal_shell.dart
// -----------------------------------------------------------------------------
// The primary interactive screen: scrolling log + bottom input line.
// Performance notes are inlined at each decision point below.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'command_interpreter.dart';
import 'theme.dart';

class TerminalShell extends StatefulWidget {
  const TerminalShell({super.key});

  @override
  State<TerminalShell> createState() => _TerminalShellState();
}

class _TerminalShellState extends State<TerminalShell> {
  // A single long-lived interpreter instance — no per-command allocation.
  final CommandInterpreter _interpreter = CommandInterpreter();

  // Plain growable list, not a ValueNotifier-wrapped structure: the whole
  // log only ever changes via setState from within this State, so there's
  // no benefit to extra listenable machinery here.
  final List<TerminalLine> _history = [
    const TerminalLine('REDLINE OS v1.0 — SECURE SHELL INITIALIZED'),
    const TerminalLine("TYPE 'help' FOR AVAILABLE COMMANDS."),
  ];

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    if (raw.trim().isEmpty) return;

    // Echo the command as its own prompt-styled line immediately, so the UI
    // feels responsive even before the interpreter runs.
    setState(() {
      _history.add(TerminalLine('redline@sys:~# $raw', isPrompt: true));
    });

    // `run()` is synchronous and cheap by contract (see command_interpreter.dart).
    // If it ever needs to host a genuinely slow command, that command must
    // schedule its own Future and push results back via setState later —
    // this call site itself must never be awaited/blocked.
    final result = _interpreter.run(raw);

    setState(() {
      if (result == null) {
        // 'clear' sentinel
        _history.clear();
      } else {
        _history.addAll(result);
      }
    });

    _inputController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    // Deferred to the next frame so it runs after the ListView has laid out
    // the newly added items — jumping immediately would target a stale
    // maxScrollExtent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Explicit black — belt-and-suspenders with the theme's
      // scaffoldBackgroundColor, and it means this widget renders correctly
      // even if dropped into a different theme context.
      backgroundColor: RedLineColors.background,
      appBar: AppBar(
        title: const Text('REDLINE // TERMINAL'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _TerminalLog(history: _history, scrollController: _scrollController)),
            const Divider(height: 1),
            _CommandInputLine(
              controller: _inputController,
              focusNode: _inputFocusNode,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrolling log view. Extracted as its own widget (rather than inlined in
/// build()) so it can be `const`-constructed and so Flutter's element diffing
/// stays cheap — this subtree's identity is stable across rebuilds.
class _TerminalLog extends StatelessWidget {
  const _TerminalLog({required this.history, required this.scrollController});

  final List<TerminalLine> history;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // ListView.builder only builds visible children — required here since
      // a long-running session's log can grow to thousands of lines and we
      // never want to pay layout cost for off-screen entries.
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: history.length,
      // Fixed extent lets the ListView skip a full layout pass to measure
      // each line, which matters once history gets long.
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

/// Bottom input row styled as `redline@sys:~#`.
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: RedLineColors.background,
        border: Border(top: BorderSide(color: RedLineColors.accentDim, width: 1)),
      ),
      child: Row(
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
              autofocus: true,
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
              // Plain ASCII/command input only — no need for autocorrect or
              // suggestions, both of which add IME overhead on every keystroke.
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: const [], // reserved: add allow-listed chars here if needed
              onSubmitted: (value) {
                onSubmit(value);
                // Re-focus so the keyboard stays open for the next command —
                // standard terminal UX.
                focusNode.requestFocus();
              },
            ),
          ),
        ],
      ),
    );
  }
}
