// main.dart
// -----------------------------------------------------------------------------
// RedLine entrypoint.
//
// Cold-start budget notes:
//  - WidgetsFlutterBinding is initialized explicitly and first, since font
//    loading, platform channel calls, AND Hive's local storage init all
//    need a live binding.
//  - Local-first: LocalStore.init() opens the on-disk Hive boxes the
//    logistics module reads/writes. No network, no Firebase — the app is
//    fully usable offline from the first frame. When a Firebase sync layer
//    is added later (see local_store.dart), Firebase.initializeApp() and
//    an auth step would go here ALONGSIDE this call, not instead of it —
//    LocalStore stays the source of truth either way, like Google Keep.
//  - Font *geometry* (glyph metrics) is warmed via a zero-size offstage
//    TextPainter.layout() call before runApp(): this forces Skia/Impeller to
//    resolve and cache the Consolas glyph atlas for the sizes we use, so the
//    very first frame of the terminal screen doesn't pay that cost mid-frame.
//  - No splash animation, no theme computed at build time — buildRedLineTheme()
//    is called once, here, and handed to MaterialApp as a static value.
//  - Root widget (RedLineApp) is a StatelessWidget: no lifecycle overhead,
//    no unnecessary rebuild surface.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'services/local_store.dart';
import 'theme.dart';
import 'home_shell.dart';

Future<void> main() async {
  // Must run before anything touching platform channels, MediaQuery, or
  // text layout.
  WidgetsFlutterBinding.ensureInitialized();

  // Opens the local Hive boxes. Must complete before any screen tries to
  // read/write logistics data.
  await LocalStore.instance.init();

  // Pre-warm the Consolas glyph atlas at the sizes actually used by the UI
  // (see theme.dart / terminal_shell.dart: 13, 14, and 16 are the only sizes
  // in play). This is cheap — a handful of offscreen layout passes — but it
  // means the cost happens here, synchronously, before the first frame is
  // even scheduled, instead of causing a jank spike on the first real
  // terminal render.
  _warmUpFontGeometry();

  runApp(const RedLineApp());
}

void _warmUpFontGeometry() {
  const sizes = [13.0, 14.0, 16.0];
  for (final size in sizes) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'REDLINE 0123456789 redline@sys:~# ',
        style: TextStyle(fontFamily: kTerminalFontFamily, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Discard immediately — we only care about the side effect of the
    // engine resolving/caching the font, not the layout result itself.
    painter.dispose();
  }
}

class RedLineApp extends StatelessWidget {
  const RedLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RedLine',
      debugShowCheckedModeBanner: false,
      theme: buildRedLineTheme(),
      home: const HomeShell(),
    );
  }
}
