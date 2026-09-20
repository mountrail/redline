// main.dart
// -----------------------------------------------------------------------------
// RedLine entrypoint.
//
// Cold-start budget notes:
//  - WidgetsFlutterBinding is initialized explicitly and first, before any
//    other work, since font loading and platform channel calls both need a
//    live binding.
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
import 'theme.dart';
import 'home_shell.dart';

Future<void> main() async {
  // Must run before anything touching platform channels, MediaQuery, or
  // text layout.
  WidgetsFlutterBinding.ensureInitialized();

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

// -----------------------------------------------------------------------------
// NATIVE ANDROID COLD-START CONFIG (apply these alongside the Dart code above)
// -----------------------------------------------------------------------------
//
// Flutter's default launch theme briefly shows a white window before the
// first Flutter frame paints. Fix this at the native layer so the *very
// first* pixel the OS composites is already pure black:
//
// 1) android/app/src/main/res/drawable/launch_background.xml
//    Replace the default `<item android:drawable="@android:color/white" />`
//    (or the branding layer-list) with a flat black background:
//
//      <?xml version="1.0" encoding="utf-8"?>
//      <layer-list xmlns:android="http://schemas.android.com/apk/res/android">
//          <item android:drawable="@android:color/black" />
//      </layer-list>
//
//    Do this for BOTH:
//      android/app/src/main/res/drawable/launch_background.xml
//      android/app/src/main/res/drawable-v21/launch_background.xml
//
// 2) android/app/src/main/res/values/styles.xml (and values-night/styles.xml)
//    Ensure both the LaunchTheme and NormalTheme set a black window
//    background so there's no flash between the launch screen and the
//    first Flutter-drawn frame:
//
//      <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
//          <item name="android:windowBackground">@drawable/launch_background</item>
//          <item name="android:windowFullscreen">false</item>
//      </style>
//
//      <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
//          <item name="android:windowBackground">@android:color/black</item>
//      </style>
//
// 3) android/app/src/main/AndroidManifest.xml
//    Confirm the launching activity references LaunchTheme:
//
//      <activity
//          android:name=".MainActivity"
//          android:theme="@style/LaunchTheme"
//          ...>
//
// 4) android/app/build.gradle
//    For release builds, enable R8/minification and resource shrinking so
//    the APK stays small and class-loading at cold start stays fast:
//
//      buildTypes {
//          release {
//              minifyEnabled true
//              shrinkResources true
//              proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
//          }
//      }
//
// 5) pubspec.yaml — keep dependencies minimal. This app intentionally uses
//    ONLY the Flutter SDK (material, services, rendering) — no google_fonts,
//    no animation/Lottie/Rive packages, no state-management framework. Every
//    added package is extra class-loading and extra APK size on the critical
//    cold-start path.
// -----------------------------------------------------------------------------
