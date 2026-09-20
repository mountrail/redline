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

/// A single frame of a scripted, purely cosmetic "animation" sequence — the
/// `hack` easter egg below is the only one right now. This class carries
/// only data (a line, and how long to wait before showing it); it holds no
/// Timer or Future itself. The actual waiting is done by the shell widget
/// via `Future.delayed`, which is what keeps this file free of async
/// runtime/UI concerns, same as everything else here.
class HackFrame {
  final TerminalLine line;
  final Duration delay;

  /// If true, this frame overwrites the most recently appended log line
  /// instead of adding a new one. Used for the progress bar and the
  /// decrypt/scramble effect so they animate in place — one line ticking
  /// through states — rather than flooding the log with a new line per
  /// frame.
  final bool replacesLast;

  const HackFrame(this.line, this.delay, {this.replacesLast = false});
}

/// Signature for a command handler. Handlers return their output lines
/// synchronously — for anything that might take real time (network calls,
/// file IO), wrap the *call site*, not this signature, in a Future so the
/// interpreter itself never blocks. See `net-scan` below for the pattern:
/// it returns instantly with a "scanning..." line and schedules the result
/// asynchronously via a callback instead of awaiting inline.
///
/// `hack` goes a step further and is fully scripted over time (a fake
/// breach/decrypt sequence) — see `animatedCommands` and `buildHackFrames`
/// below. Commands in that set are never routed through a CommandHandler at
/// all; the shell recognizes them before calling run() and drives the
/// animation itself.
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

  /// Command names that are cosmetic, scripted-over-time sequences rather
  /// than instant synchronous handlers. The shell checks this set BEFORE
  /// calling run() and, if matched, calls buildHackFrames() and plays the
  /// frames back itself with real delays between them — run() never sees
  /// these commands and has no entry for them in `_commands`.
  static const Set<String> animatedCommands = {'hack'};

  void _registerBuiltins() {
    _commands['help'] = (args) => const [
      TerminalLine('AVAILABLE COMMANDS:'),
      TerminalLine('  help        show this list'),
      TerminalLine('  sys-info    display device/runtime info'),
      TerminalLine('  net-scan    simulate a local network scan'),
      TerminalLine('  hack [tgt]  play a fake breach sequence (cosmetic)'),
      TerminalLine('  echo        print arguments back'),
      TerminalLine('  clear       clear the terminal log'),
    ];

    _commands['clear'] = (args) =>
        const []; // handled specially by the shell (see onCommand)

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

  // ---------------------------------------------------------------------
  // `hack` — purely cosmetic "breach" animation.
  //
  // This does not touch the network, the filesystem, or any real system
  // state — it's a fixed script of fake hex noise, a fake decrypt/reveal
  // effect, and a fake progress bar, entirely generated from local random
  // strings. It exists for the ctOS/hacker-terminal aesthetic the rest of
  // the UI (RedLine, the neon-red theme, the module list) is going for.
  // ---------------------------------------------------------------------

  /// Builds the full scripted sequence for `hack [target]`. Pure function
  /// of `args` and internal RNG state — no side effects, no async — so the
  /// shell can call it synchronously and then play the returned frames
  /// back over time itself.
  List<HackFrame> buildHackFrames(List<String> args) {
    final target = args.isNotEmpty
        ? args.join(' ').toUpperCase()
        : _fakeTarget();
    final frames = <HackFrame>[];

    void add(
      String text, {
      int ms = 120,
      bool isPrompt = false,
      bool isError = false,
      bool replacesLast = false,
    }) {
      frames.add(
        HackFrame(
          TerminalLine(text, isPrompt: isPrompt, isError: isError),
          Duration(milliseconds: ms),
          replacesLast: replacesLast,
        ),
      );
    }

    add('INITIATING BREACH SEQUENCE :: TARGET $target', ms: 200);
    add('RESOLVING HOST...', ms: 260);
    add('HOST RESOLVED :: ${_fakeIp()}', ms: 200);

    // Decrypt/reveal effect: a fake session key starts fully scrambled and
    // "locks in" left-to-right over a few quick frames, all overwriting the
    // same log line.
    final revealSteps = _decodeReveal(_fakeHexKey(length: 16), steps: 9);
    for (var i = 0; i < revealSteps.length; i++) {
      add(
        'DECRYPTING SESSION KEY: ${revealSteps[i]}',
        ms: 45,
        replacesLast: i > 0,
      );
    }

    // A short burst of fake hex-dump noise, purely for texture.
    for (var i = 0; i < 4; i++) {
      add(_fakeHexDump(), ms: 70);
    }

    // Fake progress bar for "bypassing" the firewall, animating in place.
    for (var pct = 0; pct <= 100; pct += 10) {
      add(
        'BYPASSING FIREWALL ${_progressBar(pct)} $pct%',
        ms: 90,
        replacesLast: pct > 0,
      );
    }

    add('FIREWALL BYPASSED.', ms: 220);
    add('ELEVATING PRIVILEGES...', ms: 260);
    add('ROOT ACCESS ACQUIRED.', ms: 260);
    add('ACCESS GRANTED :: $target', ms: 320, isPrompt: true);

    return frames;
  }

  String _progressBar(int pct) {
    const width = 20;
    final filled = (width * pct / 100).round();
    return '[${'#' * filled}${'-' * (width - filled)}]';
  }

  String _fakeIp() {
    final a = 10 + _rand.nextInt(200);
    final b = _rand.nextInt(255);
    final c = _rand.nextInt(255);
    final d = 1 + _rand.nextInt(254);
    return '$a.$b.$c.$d';
  }

  String _fakeTarget() {
    const names = [
      'MAINFRAME-07',
      'NODE//BLACKOUT',
      'CTRL-GATEWAY',
      'SECTOR-9-RELAY',
      'CORE//ORACLE',
    ];
    return names[_rand.nextInt(names.length)];
  }

  String _fakeHexKey({int length = 16}) {
    const digits = '0123456789ABCDEF';
    return List.generate(
      length,
      (_) => digits[_rand.nextInt(digits.length)],
    ).join();
  }

  String _fakeHexDump() {
    final address = _fakeHexKey(length: 4);
    final bytes = List.generate(8, (_) => _fakeHexKey(length: 2)).join(' ');
    return '0x$address  $bytes';
  }

  /// Produces `steps` progressively-more-resolved versions of [finalText]:
  /// the first is fully scrambled, and each subsequent step "locks in"
  /// roughly one more character (left to right) while the rest keeps
  /// re-scrambling — a cosmetic decrypt/reveal effect, nothing more.
  List<String> _decodeReveal(String finalText, {required int steps}) {
    const digits = '0123456789ABCDEF';
    final chars = finalText.split('');
    return List.generate(steps, (step) {
      final locked = ((chars.length) * (step + 1) / steps).floor();
      return List.generate(chars.length, (i) {
        if (i < locked) return chars[i];
        return digits[_rand.nextInt(digits.length)];
      }).join();
    });
  }
}
