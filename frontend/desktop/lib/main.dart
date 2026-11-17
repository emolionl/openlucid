import 'package:flutter/material.dart';

import 'app/account.dart';
import 'app/headband.dart';
import 'app/heart_strap.dart';
import 'app/settings.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final account = Account(settings);
  final headband = Headband(settings, heart: HeartStrap())..onNightSaved = account.nightSaved;
  runApp(OpenLucidApp(settings: settings, headband: headband, account: account));
}

class OpenLucidApp extends StatelessWidget {
  const OpenLucidApp({super.key, required this.settings, required this.headband, this.account});

  final Settings settings;
  final Headband headband;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenLucid',
      debugShowCheckedModeBanner: false,
      theme: nightTheme(),
      home: AppShell(settings: settings, headband: headband, account: account ?? Account(settings)),
    );
  }
}
