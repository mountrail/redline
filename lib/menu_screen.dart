// menu_screen.dart
// -----------------------------------------------------------------------------
// The first scene: a scrollable, clickable module menu. Sits behind the
// draggable terminal panel (see home_shell.dart) and stays interactive at
// all times — the terminal is an overlay, not a route change.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'theme.dart';

/// Static module list. Numbers are cosmetic (ctOS-style indexing), not IDs —
/// kept as a const list so this never gets rebuilt or reallocated.
const List<String> kModules = [
  'NETWORK',
  'DNS',
  'HTTP',
  'IP TOOLS',
  'ENCODER',
  'FILE TOOLS',
  'SYSTEM',
  'UTILITIES',
  'SETTINGS',
];

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, // the terminal panel handles its own bottom inset
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'REDLINE // MAIN MENU',
              style: TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.accent,
                fontSize: 18,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'SELECT A MODULE OR DRAG THE TERMINAL UP FROM THE BOTTOM.',
              style: TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.textMuted,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              // Bottom padding clears the collapsed terminal handle (see
              // HomeShell._peekHeight) so the last menu item is never hidden
              // underneath it.
              padding: const EdgeInsets.only(bottom: 72),
              itemCount: kModules.length,
              itemBuilder: (context, index) {
                return _ModuleRow(index: index + 1, label: kModules[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.index, required this.label});

  final int index;
  final String label;

  void _open(BuildContext context) {
    // The terminal's input field can hold keyboard focus even while
    // collapsed. Without this, popping back from the placeholder screen
    // restores that stale focus and the keyboard pops open unexpectedly,
    // shoving the whole layout up. Clearing focus before navigating means
    // there's nothing left for the Navigator to restore on return.
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModulePlaceholderScreen(moduleName: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // No splash/highlight color — theme already disables Material ripple
      // visuals globally, keeping this a flat, instant tap response.
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: RedLineColors.accentDim, width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontFamily: kTerminalFontFamily,
                  color: RedLineColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: kTerminalFontFamily,
                  color: RedLineColors.accent,
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: RedLineColors.accentDim,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder destination for each module. Swap the body of this screen
/// out per-module as real functionality gets built — the routing and shell
/// around it stays the same.
class ModulePlaceholderScreen extends StatelessWidget {
  const ModulePlaceholderScreen({super.key, required this.moduleName});

  final String moduleName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RedLineColors.background,
      appBar: AppBar(title: Text('REDLINE // $moduleName')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MODULE: $moduleName',
              style: const TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.accent,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'STATUS: PLACEHOLDER — NOT YET IMPLEMENTED',
              style: TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
