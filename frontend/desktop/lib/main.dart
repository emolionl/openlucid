import 'package:flutter/material.dart';

import 'app/headband.dart';
import 'app/settings.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  runApp(OpenLucidApp(settings: settings, headband: Headband(settings)));
}

class OpenLucidApp extends StatelessWidget {
  const OpenLucidApp({super.key, required this.settings, required this.headband});

  final Settings settings;
  final Headband headband;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenLucid',
      debugShowCheckedModeBanner: false,
      theme: nightTheme(),
      home: AppShell(settings: settings, headband: headband),
    );
  }
}
