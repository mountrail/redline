// theme.dart
// -----------------------------------------------------------------------------
// Centralized visual configuration for RedLine.
// Kept as pure `const` data wherever possible — const constructors mean the
// Flutter framework can skip rebuilding these subtrees entirely, which matters
// for a "zero jank" terminal UI that re-renders a ListView on every command.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

/// Raw color palette. Kept as top-level consts (not a class with statics)
/// so the compiler can inline them — no indirection, no runtime lookup.
class RedLineColors {
  RedLineColors._(); // no instances — this is a namespace, not an object

  static const Color background = Color(0xFF000000); // pure black, zero overdraw
  static const Color accent = Color(0xFFFF0033); // neon red
  static const Color accentDim = Color(0xFF5A0011); // low-emphasis red (borders/dividers)
  static const Color textMuted = Color(0xFF8A8A8A); // subdued log / description text
  static const Color error = Color(0xFFFF0033); // errors reuse accent — one less color to theme
}

/// Font family name. "Consolas" must exist as a local asset (see pubspec note
/// at the bottom of this file) — it is NOT bundled with Flutter or fetched
/// over the network, so there is no google_fonts dependency and no startup
/// network/file-system race.
const String kTerminalFontFamily = 'Consolas';

/// Builds the single [ThemeData] used by the app. Constructed once in main()
/// and handed to MaterialApp — never rebuilt at runtime.
ThemeData buildRedLineTheme() {
  const baseTextStyle = TextStyle(
    fontFamily: kTerminalFontFamily,
    color: RedLineColors.accent,
    fontSize: 14,
    height: 1.3,
    letterSpacing: 0.2,
  );

  return ThemeData(
    // Disable Material's default splash/highlight animations — they cost
    // paint time for zero functional value in a terminal-style UI.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: RedLineColors.background,
    canvasColor: RedLineColors.background,
    fontFamily: kTerminalFontFamily,

    colorScheme: const ColorScheme.dark(
      primary: RedLineColors.accent,
      secondary: RedLineColors.accent,
      surface: RedLineColors.background,
      error: RedLineColors.error,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: RedLineColors.background,
      surfaceTintColor: Colors.transparent, // kill M3's auto elevation tint
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: kTerminalFontFamily,
        color: RedLineColors.accent,
        fontSize: 16,
        letterSpacing: 1.1,
      ),
      iconTheme: IconThemeData(color: RedLineColors.accent),
    ),

    textTheme: TextTheme(
      bodyLarge: baseTextStyle,
      bodyMedium: baseTextStyle,
      bodySmall: baseTextStyle.copyWith(color: RedLineColors.textMuted, fontSize: 12),
    ),

    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: RedLineColors.accent,
      selectionColor: RedLineColors.accentDim,
      selectionHandleColor: RedLineColors.accent,
    ),

    dividerTheme: const DividerThemeData(
      color: RedLineColors.accentDim,
      thickness: 1,
      space: 1,
    ),

    // Disable page transition animations — a terminal-style utility app
    // has no business doing hero/slide transitions that burn frames.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
        TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
      },
    ),
  );
}

/// A page transition that performs an instant cut instead of animating.
/// Avoids GPU compositing work for enter/exit transitions entirely.
class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child; // no wrapping animation widget at all
  }
}

// -----------------------------------------------------------------------------
// pubspec.yaml font registration (reference — not executed, just documented
// here so the font wiring lives next to the theme that depends on it):
//
// flutter:
//   fonts:
//     - family: Consolas
//       fonts:
//         - asset: assets/fonts/Consolas-Regular.ttf
//         - asset: assets/fonts/Consolas-Bold.ttf
//           weight: 700
//
// Consolas is a Microsoft font, not open-licensed for redistribution — supply
// your own legally obtained .ttf files under assets/fonts/. If you don't have
// rights to redistribute it, substitute a metrically similar open font (e.g.
// "JetBrains Mono" or "Cascadia Mono") under the same family alias so no
// other code in this project needs to change.
// -----------------------------------------------------------------------------
