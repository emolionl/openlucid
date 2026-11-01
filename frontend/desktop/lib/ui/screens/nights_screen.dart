import 'package:flutter/material.dart';

import 'empty_state.dart';

class NightsScreen extends StatelessWidget {
  const NightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'No nights yet',
      icon: Icons.nights_stay_outlined,
      message: 'Every night you record shows up here as a skyline of your sleep: '
          'when you were awake, in deep sleep, and dreaming.',
      comingIn: 'Recording arrives in Module 2',
    );
  }
}
