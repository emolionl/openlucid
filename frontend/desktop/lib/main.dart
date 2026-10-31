import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Where the Diary Keeper (the backend) lives. On a phone, change this to the laptop's IP address.
const String diaryKeeperUrl = 'http://localhost:8000';

void main() {
  runApp(const OpenLucidApp());
}

class OpenLucidApp extends StatelessWidget {
  const OpenLucidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenLucid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HelloScreen(),
    );
  }
}

/// Checkpoint 00: the app waves, the Diary Keeper waves back.
class HelloScreen extends StatefulWidget {
  const HelloScreen({super.key});

  @override
  State<HelloScreen> createState() => _HelloScreenState();
}

class _HelloScreenState extends State<HelloScreen> {
  String _reply = 'Not asked yet.';
  bool _asking = false;

  Future<void> _wave() async {
    setState(() => _asking = true);
    try {
      final response = await http.get(Uri.parse('$diaryKeeperUrl/health')).timeout(const Duration(seconds: 5));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() => _reply = '${body['message']} (${body['time']})');
    } catch (_) {
      setState(() => _reply = 'No answer. Is the Diary Keeper running? Start the backend first.');
    } finally {
      setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('OpenLucid', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              const Text('Hello. I will listen to your night.'),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _asking ? null : _wave,
                icon: const Icon(Icons.waving_hand),
                label: const Text('Wave at the Diary Keeper'),
              ),
              const SizedBox(height: 16),
              Text(_reply, key: const Key('reply'), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
