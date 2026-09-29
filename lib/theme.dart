import 'package:flutter/material.dart';

const kRed = Color(0xFFFF0033);
const kDim = Color(0xFF5A0011);
const kMuted = Color(0xFF8A8A8A);
const kFont = 'Consolas';

const kLabel = TextStyle(color: kMuted, fontSize: 12);
const kBold = TextStyle(fontWeight: FontWeight.bold, fontSize: 15);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    splashFactory: NoSplash.splashFactory,
    colorScheme: const ColorScheme.dark(
      primary: kRed,
      onPrimary: Colors.black,
      surface: Colors.black,
      surfaceContainerHigh: Colors.black,
      onSurface: kRed,
      onSurfaceVariant: kMuted,
      error: kRed,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: kFont,
      bodyColor: kRed,
      displayColor: kRed,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: kRed),
      titleTextStyle: TextStyle(fontFamily: kFont, color: kRed, fontSize: 16),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kRed,
      foregroundColor: Colors.black,
    ),
    dividerTheme: const DividerThemeData(color: kDim, space: 1),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: kMuted),
      hintStyle: TextStyle(color: kMuted),
    ),
  );
}
