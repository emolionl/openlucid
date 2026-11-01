import 'package:flutter/material.dart';

import '../app/headband.dart';
import '../app/settings.dart';
import 'screens/journal_screen.dart';
import 'screens/nights_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tonight_screen.dart';
import 'theme.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Tonight', Icons.bedtime_outlined, Icons.bedtime),
  _Destination('Nights', Icons.insights_outlined, Icons.insights),
  _Destination('Journal', Icons.menu_book_outlined, Icons.menu_book),
  _Destination('Settings', Icons.tune_outlined, Icons.tune),
];

/// The app's frame: a bottom bar on phones, a side rail on tablets and laptops.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings, required this.headband});

  final Settings settings;
  final Headband headband;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  Widget _page() => switch (_index) {
        0 => TonightScreen(headband: widget.headband),
        1 => const NightsScreen(),
        2 => const JournalScreen(),
        _ => SettingsScreen(settings: widget.settings),
      };

  @override
  Widget build(BuildContext context) {
    final size = windowSizeOf(context);
    final page = SafeArea(child: _page());

    if (size == WindowSize.compact) {
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            extended: size == WindowSize.expanded,
            minExtendedWidth: 200,
            labelType: size == WindowSize.expanded ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: size == WindowSize.expanded
                  ? Text('🌙 OpenLucid', style: Theme.of(context).textTheme.titleLarge)
                  : const Text('🌙', style: TextStyle(fontSize: 26)),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}
