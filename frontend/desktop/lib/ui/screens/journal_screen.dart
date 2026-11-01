import 'package:flutter/material.dart';

import 'empty_state.dart';

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      title: 'Your dream journal',
      icon: Icons.auto_stories_outlined,
      message: 'Until this screen is ready, keep a notebook next to your bed. '
          'Write down every dream the moment you wake, before touching your phone.',
      comingIn: 'The journal arrives in Module 8',
    );
  }
}
