import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart';
import 'package:desktop_updater/widget/update_direct_card.dart';
import 'package:flutter/material.dart';

import '../../app/account.dart';
import '../../app/diary_keeper.dart';
import '../../app/settings.dart';
import '../../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.account});

  final Settings settings;
  final Account account;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: widget.settings.diaryKeeperUrl);
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _reply = 'Not asked yet.';
  bool _asking = false;

  Future<void> _wave() async {
    widget.settings.diaryKeeperUrl = _url.text;
    _url.text = widget.settings.diaryKeeperUrl;
    setState(() => _asking = true);
    try {
      final message = await DiaryKeeper(widget.settings.diaryKeeperUrl).wave();
      setState(() => _reply = message);
    } catch (_) {
      setState(() => _reply = 'No answer. Is the Diary Keeper running at this address?');
    } finally {
      setState(() => _asking = false);
    }
  }

  Future<void> _signIn({required bool create}) async {
    widget.settings.diaryKeeperUrl = _url.text;
    _url.text = widget.settings.diaryKeeperUrl;
    final ok = create
        ? await widget.account.register(_email.text.trim(), _password.text)
        : await widget.account.signIn(_email.text.trim(), _password.text);
    if (ok) _password.clear();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.settings, widget.account]),
      builder: (context, _) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Settings', style: text.headlineMedium),
              const SizedBox(height: 16),
              _Section(
                title: 'Diary Keeper',
                subtitle: 'The small server on your laptop that writes down every night.',
                children: [
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      helperText: 'On this laptop: http://localhost:8000 · On a phone: http://<laptop-ip>:8000',
                      helperMaxLines: 3,
                    ),
                    onSubmitted: (value) => widget.settings.diaryKeeperUrl = value,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _asking ? null : _wave,
                        icon: const Icon(Icons.waving_hand),
                        label: const Text('Wave at the Diary Keeper'),
                      ),
                      Text(_reply, key: const Key('reply'), style: text.bodySmall),
                    ],
                  ),
                  const Divider(height: 32),
                  ..._accountFields(text),
                ],
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Power grid',
                subtitle: 'The electricity in your walls hums at 50 Hz (Europe, Africa, most of Asia) '
                    'or 60 Hz (the Americas). The live view filters it out.',
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 50, label: Text('50 Hz')),
                      ButtonSegment(value: 60, label: Text('60 Hz')),
                    ],
                    selected: {widget.settings.mainsHz},
                    onSelectionChanged: (s) => widget.settings.mainsHz = s.first,
                  ),
                  const SizedBox(height: 4),
                  Text('Applies the next time you connect a headband.', style: text.bodySmall),
                ],
              ),
              const SizedBox(height: 16),
              const _Section(
                title: 'About OpenLucid',
                subtitle: 'Free and open source (MIT license): github.com/emolionl/openlucid',
                children: [
                  Text(
                    'Educational, not medical advice. A consumer EEG headband is not a medical device, '
                    'and OpenLucid does not diagnose or treat anything. Your brain data stays on your own devices. '
                    'Sound cues only: no electricity goes into anyone\'s head.',
                  ),
                ],
              ),
              if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
                const SizedBox(height: 16),
                DesktopUpdateDirectCard(controller: UpdateService.controller, child: const SizedBox()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension on _SettingsScreenState {
  /// Signing in to the Diary Keeper, so nights (brain signal, movement, heartbeats) get a copy there.
  List<Widget> _accountFields(TextTheme text) {
    final account = widget.account;
    if (account.signedIn) {
      return [
        Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Signed in as ${account.email}', style: text.bodyMedium)),
            TextButton(onPressed: account.busy ? null : account.signOut, child: const Text('Sign out')),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: widget.settings.autoUpload,
          onChanged: (v) => widget.settings.autoUpload = v,
          title: const Text('Send every night after it is saved'),
          subtitle: const Text('The night stays on this device too. Older nights: the Nights tab.'),
        ),
      ];
    }
    return [
      Text('Account', style: text.titleSmall),
      const SizedBox(height: 4),
      Text(
        'Sign in to send your nights to this Diary Keeper. The first account on a new Diary Keeper becomes its admin.',
        style: text.bodySmall,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Password', helperText: 'At least 10 characters for a new account.'),
        onSubmitted: (_) => _signIn(create: false),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(
            key: const Key('signIn'),
            onPressed: account.busy ? null : () => _signIn(create: false),
            child: const Text('Sign in'),
          ),
          OutlinedButton(
            onPressed: account.busy ? null : () => _signIn(create: true),
            child: const Text('Create account'),
          ),
        ],
      ),
      if (account.status.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(account.status, key: const Key('accountStatus'), style: text.bodySmall),
      ],
      const SizedBox(height: 4),
      Text(
        'Creating an account means agreeing that this Diary Keeper stores your nights (EEG, movement, heartbeats, '
        'journal). You can export or delete everything there at any time.',
        style: text.bodySmall,
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: text.bodySmall),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
