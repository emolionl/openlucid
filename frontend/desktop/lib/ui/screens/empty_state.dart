import 'package:flutter/material.dart';

/// A friendly placeholder for screens whose feature arrives in a later module.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    required this.comingIn,
  });

  final String title;
  final IconData icon;
  final String message;
  final String comingIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Chip(label: Text(comingIn), avatar: const Icon(Icons.construction_rounded, size: 18)),
            ],
          ),
        ),
      ),
    );
  }
}
