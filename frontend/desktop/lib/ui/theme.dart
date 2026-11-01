import 'package:flutter/material.dart';

/// A dark, calm theme: easy on the eyes in a dark bedroom, with little bright blue.
ThemeData nightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6B6FD6),
    brightness: Brightness.dark,
  ).copyWith(
    surface: const Color(0xFF0E1020),
    surfaceContainerLowest: const Color(0xFF0A0B17),
    surfaceContainerLow: const Color(0xFF14162B),
    surfaceContainer: const Color(0xFF181A33),
    surfaceContainerHigh: const Color(0xFF1E2140),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: scheme.surfaceContainerLowest),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: scheme.surfaceContainerLowest),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

/// Layout sizes, following Material 3's window size classes.
enum WindowSize { compact, medium, expanded }

WindowSize windowSizeOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return WindowSize.compact;
  if (width < 840) return WindowSize.medium;
  return WindowSize.expanded;
}
