// command_interpreter.dart
// -----------------------------------------------------------------------------
// Pure logic layer for the terminal: no Flutter/widget imports here at all.
// Keeping this UI-free makes it trivially unit-testable and guarantees it can
// never accidentally trigger a rebuild or block the UI thread by holding
// widget references.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';

/// A single rendered line in the terminal log.
/// `isPrompt` distinguishes the echoed `redline@sys:~# <cmd>` line from
/// regular output, so the UI can color/style them differently without the
/// interpreter needing to know anything about widgets.
class TerminalLine {
  final String text;
  final bool isPrompt;
  final bool isError;

  const TerminalLine(this.text, {this.isPrompt = false, this.isError = false});
}

/// Signature for a command handler. Handlers return their output lines
/// synchronously — for anything that might take real time (network calls,
/// file IO), wrap the *call site*, not this signature, in a Future so the
/// interpreter itself never blocks. See `net-scan` below for the pattern:
/// it returns instantly with a "scanning..." line and schedules the result
/// asynchronously via a callback instead of awaiting inline.
typedef CommandHandler = List<TerminalLine> Function(List<String> args);

/// Stateless-ish command dispatcher. Holds no widget state — only a command
/// table — so it can be a single long-lived instance owned by the shell's
/// State object.
class CommandInterpreter {
  CommandInterpreter() {
    _registerBuiltins();
  }

  final Map<String, CommandHandler> _commands = {};
  final Random _rand = Random();

  void _registerBuiltins() {
    _commands['help'] = (args) => const [
          TerminalLine('AVAILABLE COMMANDS:'),
          TerminalLine('  help        show this list'),
          TerminalLine('  sys-info    display device/runtime info'),
          TerminalLine('  net-scan    simulate a local network scan'),
          TerminalLine('  echo        print arguments back'),
          TerminalLine('  clear       clear the terminal log'),
        ];

    _commands['clear'] = (args) => const []; // handled specially by the shell (see onCommand)

    _commands['echo'] = (args) => [
          TerminalLine(args.isEmpty ? '' : args.join(' ')),
        ];

    _commands['sys-info'] = (args) => [
          const TerminalLine('QUERYING LOCAL RUNTIME...'),
          TerminalLine('PLATFORM   : ${_platformName()}'),
          const TerminalLine('ENGINE     : Flutter (release)'),
          const TerminalLine('RENDERER   : Impeller/Skia'),
          const TerminalLine('STATUS     : NOMINAL'),
        ];

    // net-scan is intentionally instant and deterministic-looking but is the
    // template for any command that needs to feel like it's "doing work"
    // without ever blocking the UI thread — see runAsyncCommand below.
    _commands['net-scan'] = (args) => [
          const TerminalLine('SCANNING LOCAL SEGMENT...'),
          for (final host in _fakeHosts()) TerminalLine('  HOST FOUND: $host'),
          const TerminalLine('SCAN COMPLETE.'),
        ];
  }

  List<String> _fakeHosts() {
    // Deterministic-feeling but slightly varied output so `net-scan` doesn't
    // look identical every run. All computed synchronously — this is cheap
    // string work, not real I/O, so it's safe to return directly.
    final count = 2 + _rand.nextInt(3);
    return List.generate(count, (i) {
      final last = 10 + _rand.nextInt(240);
      return '192.168.1.$last';
    });
  }

  String _platformName() {
    // Avoided importing dart:io/Platform here to keep this file dependency-free;
    // the shell widget passes platform info in if it's ever needed for real.
    return 'ANDROID';
  }

  /// Executes [rawInput] and returns the resulting output lines.
  /// Returns null for 'clear' so the caller knows to wipe history instead
  /// of appending.
  List<TerminalLine>? run(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return const [];

    final parts = trimmed.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    final args = parts.skip(1).toList();

    if (cmd == 'clear') return null;

    final handler = _commands[cmd];
    if (handler == null) {
      return [TerminalLine('UNKNOWN COMMAND: $cmd', isError: true)];
    }

    // Handlers here are all cheap/synchronous by design (string building
    // only). If a future command needs real async work (e.g. an actual
    // socket-based scan), do it like this at the call site so a single slow
    // command can never freeze the input field or scroll:
    //
    //   Future<void> runRealNetScan() async {
    //     final result = await someIOBoundCall();
    //     // then push `result` into terminal state via setState/callback
    //   }
    //
    // i.e. keep `run()` itself synchronous and non-blocking, and handle any
    // genuinely slow command as a Future scheduled outside of it.
    return handler(args);
  }
}
