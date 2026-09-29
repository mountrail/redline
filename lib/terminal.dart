import 'dart:math';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'theme.dart';

const kPrompt = 'redline@sys:~#';

/// Slows down the `hack` animation. 1 = old speed, bigger = slower.
const _hackPace = 3;

/// Terminal state + commands. Owned by Home so output (and the `hack`
/// animation) keeps running while the panel is collapsed.
class TerminalSession extends ChangeNotifier {
  final lines = <String>['REDLINE OS v1.0', "TYPE 'help' FOR COMMANDS."];
  final _rand = Random();
  bool _busy = false;

  void _add(String text, {bool replaceLast = false}) {
    if (replaceLast && lines.isNotEmpty) lines.removeLast();
    lines.add(text);
    notifyListeners();
  }

  Future<void> run(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _add('$kPrompt $text');
    if (_busy) {
      _add('SYSTEM BUSY.');
      return;
    }
    final parts = text.split(RegExp(r'\s+'));
    final args = parts.skip(1).toList();
    switch (parts.first.toLowerCase()) {
      case 'clear':
        lines.clear();
        notifyListeners();
      case 'help':
        lines.addAll([
          'COMMANDS:',
          '  help           show this list',
          '  status         open logs / items out',
          '  router [ip]    open the wifi router page in the browser',
          '  wifi           show connected wifi + saved password',
          '  wifi save <pw> save password for this wifi',
          '  wifi forget    delete the saved password',
          '  hack [target]  fake breach sequence',
          '  echo <text>    print text',
          '  clear          clear the log',
        ]);
        notifyListeners();
      case 'echo':
        _add(args.join(' '));
      case 'status':
        final openLogs = Db.logs.values
            .where((l) => l['back_from_id'] == null)
            .length;
        final itemsOut = Db.units.values
            .where((u) => u['status'] == 'OUT')
            .length;
        _add('OPEN LOGS: $openLogs   ITEMS OUT: $itemsOut');
      case 'router':
        await _router(args);
      case 'wifi':
        await _wifi(args);
      case 'hack':
        _busy = true;
        try {
          await _hack(args.join(' '));
        } finally {
          _busy = false;
        }
      default:
        _add('UNKNOWN COMMAND: ${parts.first}');
    }
  }

  /// Opens http://<wifi gateway> (e.g. 192.168.0.1) in the browser.
  /// `router 10.0.0.1` overrides the detected address.
  Future<void> _router(List<String> args) async {
    final ip = args.isNotEmpty
        ? args.first
        : await NetworkInfo().getWifiGatewayIP();
    if (ip == null || ip.isEmpty) {
      _add('NO WIFI GATEWAY FOUND. CONNECT TO WIFI FIRST.');
      return;
    }
    _add('OPENING http://$ip ...');
    try {
      final ok = await launchUrl(
        Uri.parse('http://$ip'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _add('COULD NOT OPEN BROWSER.');
    } catch (_) {
      _add('COULD NOT OPEN BROWSER.');
    }
  }

  /// Shows the connected wifi. Android does not let apps read a network's
  /// password, so it is typed once with `wifi save <password>` and kept
  /// on this device, per SSID.
  Future<void> _wifi(List<String> args) async {
    final perm = await Permission.locationWhenInUse.request();
    if (!perm.isGranted) {
      _add(
        'LOCATION PERMISSION DENIED. ANDROID NEEDS IT TO READ THE WIFI NAME.',
      );
      return;
    }
    final info = NetworkInfo();
    final ssid = (await info.getWifiName())?.replaceAll('"', '');
    if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') {
      _add('NOT CONNECTED TO WIFI (OR LOCATION IS TURNED OFF).');
      return;
    }
    final key = 'wifi_pw::$ssid';
    final sub = args.isEmpty ? '' : args.first.toLowerCase();
    if (sub == 'save') {
      final pw = args.skip(1).join(' ');
      if (pw.isEmpty) {
        _add('USAGE: wifi save <password>');
        return;
      }
      await Db.meta.put(key, pw);
      _add('PASSWORD SAVED FOR $ssid.');
      return;
    }
    if (sub == 'forget') {
      await Db.meta.delete(key);
      _add('SAVED PASSWORD REMOVED FOR $ssid.');
      return;
    }
    final pw = Db.meta.get(key) as String?;
    _add('SSID: $ssid');
    _add('IP: ${await info.getWifiIP() ?? '-'}');
    _add('GATEWAY: ${await info.getWifiGatewayIP() ?? '-'}');
    _add(
      pw == null
          ? 'PASSWORD: NOT SAVED. USE: wifi save <password>'
          : 'PASSWORD: $pw',
    );
  }

  /// Purely cosmetic fake breach sequence.
  Future<void> _hack(String target) async {
    String hex(int n) => List.generate(
      n,
      (_) => _rand.nextInt(16).toRadixString(16).toUpperCase(),
    ).join();
    Future<void> step(String t, [int ms = 150, bool replace = false]) async {
      await Future.delayed(Duration(milliseconds: ms * _hackPace));
      _add(t, replaceLast: replace);
    }

    final tgt = target.trim().isEmpty ? 'MAINFRAME-07' : target.toUpperCase();
    await step('INITIATING BREACH :: TARGET $tgt', 200);
    await step(
      'HOST RESOLVED :: 10.${_rand.nextInt(255)}.${_rand.nextInt(255)}.${1 + _rand.nextInt(254)}',
      250,
    );

    final key = hex(16);
    for (var i = 1; i <= 9; i++) {
      final locked = key.length * i ~/ 9;
      await step(
        'DECRYPTING KEY: ${key.substring(0, locked)}${hex(key.length - locked)}',
        60,
        i > 1,
      );
    }
    for (var i = 0; i < 4; i++) {
      await step(
        '0x${hex(4)}  ${List.generate(8, (_) => hex(2)).join(' ')}',
        70,
      );
    }
    for (var p = 0; p <= 100; p += 10) {
      final filled = p ~/ 5;
      await step(
        'BYPASSING FIREWALL [${'#' * filled}${'-' * (20 - filled)}] $p%',
        90,
        p > 0,
      );
    }
    await step('ROOT ACCESS ACQUIRED.', 260);
    await step('ACCESS GRANTED :: $tgt', 320);
  }
}

class TerminalView extends StatefulWidget {
  const TerminalView({super.key, required this.session, required this.focus});

  final TerminalSession session;
  final FocusNode focus;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_toBottom);
    _toBottom();
  }

  @override
  void dispose() {
    widget.session.removeListener(_toBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  });

  bool _hot(String l) =>
      l.startsWith(kPrompt) ||
      l.startsWith('ACCESS') ||
      l.startsWith('PASSWORD') ||
      l.startsWith('UNKNOWN');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: widget.session,
            builder: (_, __) => ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: widget.session.lines.length,
              itemBuilder: (_, i) {
                final l = widget.session.lines[i];
                return Text(
                  l,
                  style: TextStyle(
                    fontSize: 13,
                    color: _hot(l) ? kRed : kMuted,
                    fontWeight: l.startsWith(kPrompt)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                );
              },
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Text(
                kPrompt,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: widget.focus,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: kRed,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (v) {
                    widget.session.run(v);
                    _input.clear();
                    widget.focus.requestFocus();
                  },
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
