import 'dart:async';

import 'package:flutter/material.dart';

import '../../eeg/eeg_source.dart';
import '../../eeg/eye_check.dart';
import '../../eeg/fake_moose.dart';

/// The guided eye check: big prompts with exact timing, recording, then a plain verdict.
class EyeCheckScreen extends StatefulWidget {
  const EyeCheckScreen({super.key, required this.source});

  final EegSource source;

  @override
  State<EyeCheckScreen> createState() => _EyeCheckScreenState();
}

class _EyeCheckScreenState extends State<EyeCheckScreen> {
  final _af7 = <double>[];
  final _af8 = <double>[];
  final _clock = Stopwatch();
  StreamSubscription<EegChunk>? _stream;
  Timer? _ticker;
  int _step = -1;
  EyeCheckResult? _result;

  int get _af7Index => widget.source.channels.indexOf('AF7');
  int get _af8Index => widget.source.channels.indexOf('AF8');
  bool get _supported => _af7Index >= 0 && _af8Index >= 0;

  void _start() {
    _af7.clear();
    _af8.clear();
    _result = null;
    _step = -1;
    final source = widget.source;
    if (source is FakeMoose) source.scripted = true;
    _stream = source.chunks.listen((chunk) {
      _af7.addAll(chunk.samples[_af7Index]);
      _af8.addAll(chunk.samples[_af8Index]);
    });
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
    setState(() {});
  }

  void _tick() {
    final seconds = _clock.elapsedMilliseconds / 1000;
    var step = _step;
    while (step + 1 < eyeCheckSteps.length &&
        eyeCheckSteps[step + 1].at <= seconds) {
      step++;
      _act(eyeCheckSteps[step].action);
    }
    if (seconds >= eyeCheckSeconds) {
      _finish();
      return;
    }
    setState(() => _step = step);
  }

  /// Fake Moose does what it's told, so people without a headband can try the check too.
  void _act(EyeAction action) {
    final source = widget.source;
    if (source is! FakeMoose) return;
    switch (action) {
      case EyeAction.blink:
        source.blink();
      case EyeAction.lookLeft:
        source.look(-1);
      case EyeAction.lookRight:
        source.look(1);
      case EyeAction.lookAhead:
        source.look(0);
      case EyeAction.still:
        break;
    }
  }

  void _finish() {
    _ticker?.cancel();
    _stream?.cancel();
    _clock.stop();
    final source = widget.source;
    if (source is FakeMoose) source.scripted = false;
    setState(
      () => _result = evaluateEyeCheck(_af7, _af8, widget.source.sampleRate),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stream?.cancel();
    final source = widget.source;
    if (source is FakeMoose) source.scripted = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eye check')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: !_supported
                    ? const Text(
                        'This headband has no forehead sensors (AF7 and AF8), so it cannot see your eyes.',
                      )
                    : _result != null
                    ? _ResultView(result: _result!, onAgain: _start)
                    : _clock.isRunning
                    ? _PromptView(
                        step: _step,
                        seconds: _clock.elapsedMilliseconds / 1000,
                      )
                    : _IntroView(onStart: _start),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.visibility_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Can your headband see your eyes?',
          style: text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'For 18 seconds, follow the words on the screen: keep still, blink three times, then look left '
          'and right. Move only your eyes, not your head.\n\n'
          'Blinks should show up on both forehead sensors in the same direction. Looking left and right should '
          'move them in opposite directions: that is the signal a lucid dreamer can send from inside a dream.',
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start'),
        ),
      ],
    );
  }
}

class _PromptView extends StatelessWidget {
  const _PromptView({required this.step, required this.seconds});

  final int step;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = step < 0 ? eyeCheckSteps.first : eyeCheckSteps[step];
    final arrow = switch (current.action) {
      EyeAction.lookLeft => '←',
      EyeAction.lookRight => '→',
      EyeAction.blink => '◉',
      _ => '•',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(arrow, style: text.displayLarge, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          current.prompt,
          key: const Key('prompt'),
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        LinearProgressIndicator(value: (seconds / eyeCheckSeconds).clamp(0, 1)),
        const SizedBox(height: 8),
        Text(
          'Keep your head still',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onAgain});

  final EyeCheckResult result;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ok = result.passed;
    final tips = <String>[
      if (result.blinksSeen < result.blinksAsked - 1)
        'Blinks were hard to see: the forehead sensors may not be touching well. Dampen the forehead and press the band gently.',
      if (result.looksSeen < result.looksAsked - 1)
        'Left and right were hard to see: look further to the side and hold it until the next word, without turning your head.',
      if (result.looksSeen > 0 && !result.directionsConsistent)
        'Left and right did not move the sensors in a consistent direction. Try again, moving only your eyes.',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 64,
          color: ok ? const Color(0xFF4CAF50) : const Color(0xFFFFC107),
        ),
        const SizedBox(height: 12),
        Text(
          ok ? 'Your headband can see your eyes' : 'Not quite yet',
          style: text.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _Line('Blinks seen', '${result.blinksSeen} of ${result.blinksAsked}'),
        _Line(
          'Left and right seen',
          '${result.looksSeen} of ${result.looksAsked}',
        ),
        _Line(
          'Left and right in opposite directions',
          result.directionsConsistent ? 'yes' : 'no',
        ),
        _Line(
          'Resting wiggle, eyes still',
          '${result.restingNoise.round()} µV',
        ),
        for (final tip in tips) ...[
          const SizedBox(height: 12),
          Text(tip, style: text.bodyMedium),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onAgain,
                child: const Text('Try again'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyLarge)),
          Text(value, style: text.titleMedium),
        ],
      ),
    );
  }
}
