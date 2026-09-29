import 'package:flutter/material.dart';

import 'data.dart';
import 'home.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.init();
  runApp(
    MaterialApp(
      title: 'RedLine',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Home(),
    ),
  );
}
