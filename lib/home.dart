import 'package:flutter/material.dart';

import 'lang.dart';
import 'logistics_screen.dart';
import 'personel_screen.dart';
import 'terminal.dart';
import 'theme.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static final _modules = <(String, Widget Function())>[
    ('LOGISTICS', () => const LogisticsScreen()),
    ('PERSONNEL', () => const PersonelScreen()),
  ];

  final _term = TerminalSession();
  final _focus = FocusNode();
  bool _open = false;

  @override
  void dispose() {
    _term.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setOpen(bool v) {
    if (!v) _focus.unfocus();
    setState(() => _open = v);
  }

  @override
  Widget build(BuildContext context) {
    // Only the menu rebuilds on a language change; every other screen is
    // built fresh when opened, so it picks up the current language by itself.
    return ListenableBuilder(
      listenable: lang,
      builder: (_, __) => PopScope(
        canPop: !_open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setOpen(false);
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'REDLINE // ${tr('MAIN MENU')}',
                              style: const TextStyle(
                                fontSize: 18,
                                letterSpacing: 2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: toggleLang,
                            icon: const Icon(Icons.language, size: 18),
                            label: Text(
                              lang.value.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _modules.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${(i + 1).toString().padLeft(2, '0')}  ${tr(_modules[i].$1)}',
                          ),
                          trailing:
                              const Icon(Icons.chevron_right, color: kDim),
                          onTap: () {
                            _focus.unfocus();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _modules[i].$2(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _setOpen(!_open),
                  onVerticalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -200) _setOpen(true);
                    if (v > 200) _setOpen(false);
                  },
                  child: Container(
                    height: 44,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: kRed)),
                    ),
                    child: const Text(
                      'TERMINAL',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (_open)
                  Expanded(
                    flex: 2,
                    child: TerminalView(session: _term, focus: _focus),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
