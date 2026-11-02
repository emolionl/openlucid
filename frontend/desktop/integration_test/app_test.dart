// End-to-end tests that launch the REAL OpenLucid app (real timers, real network, real files).
//
// Run from frontend/desktop:
//   flutter test integration_test -d windows
//
// Optional: --dart-define=DIARY_KEEPER_URL=http://127.0.0.1:8001 (the Docker server; default below)
//           --dart-define=SHOT_DIR=C:/path/to/folder (where screenshots go; default: none)
//
// SharedPreferences is replaced by an in-memory store (setMockInitialValues), so the test never
// writes the server address to the user's real settings file on disk.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openlucid/app/headband.dart';
import 'package:openlucid/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

const diaryKeeperUrl = String.fromEnvironment('DIARY_KEEPER_URL', defaultValue: 'http://127.0.0.1:8001');
const shotDir = String.fromEnvironment('SHOT_DIR');

final _clock = Stopwatch()..start();
void log(String message) =>
    // ignore: avoid_print
    print('[e2e ${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] $message');

/// Starts the app through its real main(), with an empty in-memory settings store.
Future<void> launch(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await app.main();
  await pumpFor(tester, const Duration(milliseconds: 500));
}

/// Real time passes while frames keep coming. (pumpAndSettle would never return: the live plot animates.)
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] finds something, or fails after [timeout].
Future<Duration> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 10)}) async {
  final start = DateTime.now();
  final end = start.add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return DateTime.now().difference(start);
  }
  fail('Timed out after $timeout waiting for $finder');
}

/// Saves what the window shows as a PNG. binding.takeScreenshot does not work on Windows desktop,
/// so we render the root layer ourselves.
Future<void> shot(WidgetTester tester, String name) async {
  if (shotDir.isEmpty) return;
  try {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final size = view.paintBounds.size;
    final image = await layer.toImage(Offset.zero & size, pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$shotDir${Platform.pathSeparator}$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    log('screenshot ${file.path}');
  } catch (e) {
    log('screenshot $name failed: $e');
  }
}

Future<void> go(WidgetTester tester, String destination) async {
  await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(destination)));
  await pumpFor(tester, const Duration(milliseconds: 400));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Draw every frame, like the app does on its own (the default only redraws when the test pumps).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('1. app starts and the side rail reaches every screen', (tester) async {
    final t = Stopwatch()..start();
    await launch(tester);
    log('window size: ${tester.view.physicalSize} @ ${tester.view.devicePixelRatio}x');

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Start listening'), findsOneWidget);
    expect(find.text('Put on your headband and check the contact.'), findsOneWidget);
    await shot(tester, '01-tonight');

    await go(tester, 'Nights');
    expect(find.text('No nights yet'), findsOneWidget);
    await shot(tester, '01-nights');

    await go(tester, 'Journal');
    expect(find.text('Your dream journal'), findsOneWidget);
    await shot(tester, '01-journal');

    await go(tester, 'Settings');
    expect(find.text('Diary Keeper'), findsOneWidget);
    expect(find.text('Power grid'), findsOneWidget);
    await shot(tester, '01-settings');

    await go(tester, 'Tonight');
    expect(find.text('Start listening'), findsOneWidget);
    expect(tester.takeException(), isNull);
    log('test 1 took ${t.elapsedMilliseconds} ms');
  });

  testWidgets('2. Settings: wave at the Diary Keeper in Docker', (tester) async {
    final t = Stopwatch()..start();
    await launch(tester);
    await go(tester, 'Settings');

    final address = find.byType(TextField);
    expect(tester.widget<TextField>(address).controller!.text, 'http://localhost:8000'); // default
    await tester.enterText(address, '$diaryKeeperUrl/'); // trailing slash: the app should strip it
    await tester.pump();
    await tester.tap(find.text('Wave at the Diary Keeper'));

    final waited = await pumpUntil(tester, find.textContaining('The Diary Keeper is awake.'));
    final reply = tester.widget<Text>(find.byKey(const Key('reply'))).data!;
    log('server reply after ${waited.inMilliseconds} ms: $reply');
    expect(reply, matches(RegExp(r'^The Diary Keeper is awake\. \(\d{4}-\d\d-\d\dT')));
    expect(tester.widget<TextField>(address).controller!.text, diaryKeeperUrl, reason: 'trailing slash stripped');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('diaryKeeperUrl'), diaryKeeperUrl);
    await shot(tester, '02-settings-awake');

    // A wrong address gives the friendly "no answer" message (port 1 is closed).
    // Pitfall: a second enterText on the same field did nothing in run 2 (the field still showed :8001).
    // Tapping the field first gives it a fresh text-input connection.
    await tester.tap(address);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(address, 'http://127.0.0.1:1');
    await tester.pump();
    log('address field now: ${tester.widget<TextField>(address).controller!.text}');
    await tester.tap(find.text('Wave at the Diary Keeper'));
    final waveStart = DateTime.now();
    String replyNow() => tester.widget<Text>(find.byKey(const Key('reply'))).data!;
    while (DateTime.now().difference(waveStart) < const Duration(seconds: 12) && !replyNow().startsWith('No answer')) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    log('reply ${DateTime.now().difference(waveStart).inMilliseconds} ms after the second wave: ${replyNow()}');
    log('saved address: ${(await SharedPreferences.getInstance()).getString('diaryKeeperUrl')}');
    await shot(tester, '02-settings-no-answer');
    expect(replyNow(), startsWith('No answer.'));

    // Leave the (in-memory) settings at the default again.
    await prefs.remove('diaryKeeperUrl');
    log('test 2 took ${t.elapsedMilliseconds} ms');
  });

  testWidgets('3. Tonight: Fake Moose streams, contact card and ~256 samples/s', (tester) async {
    final t = Stopwatch()..start();
    await launch(tester);

    await tester.tap(find.text('Fake Moose'));
    await tester.pump();
    await tester.tap(find.text('Start listening'));
    await pumpUntil(tester, find.text('Stop'));
    expect(find.text('Connected to Fake Moose.'), findsOneWidget);

    await pumpFor(tester, const Duration(seconds: 4));
    await shot(tester, '03-tonight-listening');

    expect(find.text('Contact'), findsOneWidget, reason: 'the laptop layout shows the contact card');
    final readings = find.textContaining(RegExp(r'^(Good|Okay|Poor) · \d+ µV · \d+%$'));
    final lines = [for (final e in readings.evaluate()) (e.widget as Text).data!];
    log('contact readings: $lines');
    expect(lines, hasLength(4));

    final rateText = tester.widget<Text>(find.textContaining('samples/s')).data!;
    log('rate line: $rateText');
    final rate = int.parse(RegExp(r'^(\d+) samples/s').firstMatch(rateText)!.group(1)!);
    expect(rate, inInclusiveRange(240, 272));

    await tester.tap(find.text('Stop'));
    await pumpUntil(tester, find.text('Start listening'));
    expect(find.textContaining('Stopped. Lost packets during that session: 0.'), findsOneWidget);
    await shot(tester, '03-tonight-stopped');
    log('test 3 took ${t.elapsedMilliseconds} ms');
  });

  testWidgets('4. Eye check with Fake Moose passes and saves a recording', (tester) async {
    final t = Stopwatch()..start();
    await launch(tester);

    await tester.tap(find.text('Start listening'));
    await pumpUntil(tester, find.text('Eye check'));
    await pumpFor(tester, const Duration(seconds: 3)); // let the contact numbers settle

    await tester.tap(find.text('Eye check'));
    await pumpUntil(tester, find.text('Can your headband see your eyes?'));
    final start = find.byWidgetPredicate(
      (w) => w is Text && (w.data == 'Start' || w.data == 'Start anyway'),
    );
    await pumpUntil(tester, start);
    log('start button says: ${(start.evaluate().first.widget as Text).data}');
    await shot(tester, '04-eye-intro');
    await tester.tap(start.first);

    await pumpUntil(tester, find.byKey(const Key('prompt')));
    final prompts = <String>{};
    final end = DateTime.now().add(const Duration(seconds: 30));
    var midShot = false;
    while (DateTime.now().isBefore(end) && find.text('Done').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
      final p = find.byKey(const Key('prompt'));
      if (p.evaluate().isNotEmpty) {
        prompts.add(tester.widget<Text>(p).data!);
        if (!midShot && prompts.contains('Look left')) {
          midShot = true;
          await shot(tester, '04-eye-look-left');
        }
      }
    }
    log('prompts seen: $prompts');
    expect(find.text('Done'), findsOneWidget, reason: 'the result view appears after ~18.5 s');
    expect(prompts, containsAll(['Blink', 'Look left', 'Look right', 'Straight ahead']));

    await pumpUntil(tester, find.textContaining('Recording saved to'));
    final summary = [
      for (final e in find.byType(Text).evaluate())
        if ((e.widget as Text).data != null) (e.widget as Text).data!,
    ];
    log('result screen: ${summary.join(' | ')}');
    await shot(tester, '04-eye-result');
    expect(find.text('Your headband can see your eyes'), findsOneWidget);

    final saved = tester.widget<Text>(find.textContaining('Recording saved to')).data!.substring(
          'Recording saved to '.length,
        );
    final file = File(saved);
    expect(file.existsSync(), isTrue);
    final csv = file.readAsLinesSync();
    final dataRows = csv.where((l) => !l.startsWith('#') && !l.startsWith('seconds')).length;
    log('recording $saved: ${csv.length} lines, $dataRows data rows, header: ${csv.take(2).join(' / ')}');
    expect(csv.first, startsWith('# OpenLucid eye check, Fake Moose, 256.0 samples/s'));
    expect(dataRows, inInclusiveRange(18 * 256, 19 * 256 + 64));
    // ignore: avoid_print
    print('E2E_SAVED_FILE=$saved');

    await tester.tap(find.text('Done'));
    await pumpUntil(tester, find.text('Stop'));
    await tester.tap(find.text('Stop'));
    await pumpUntil(tester, find.text('Start listening'));
    log('test 4 took ${t.elapsedMilliseconds} ms');
  });

  testWidgets('5. A short night with Fake Moose: start, record 35 s, stop, files on disk, listed in Nights', (tester) async {
    final t = Stopwatch()..start();
    final root = Directory.systemTemp.createTempSync('openlucid-e2e-night-');
    Headband.nightsFolderOverride = () async => root;
    await launch(tester);

    await tester.tap(find.text('Fake Moose'));
    await tester.pump();
    await tester.tap(find.text('Start listening'));
    await pumpUntil(tester, find.byKey(const Key('startNight')));
    await tester.tap(find.byKey(const Key('startNight')));
    await pumpUntil(tester, find.byKey(const Key('stopNight')));
    expect(find.text('Recording the night. Sleep well.'), findsOneWidget);
    final stopListening = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Stop'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(stopListening.onPressed, isNull, reason: 'during a night, the headband cannot be stopped by one tap');

    await pumpFor(tester, const Duration(seconds: 35));
    await shot(tester, '05-night-recording');
    final clock = tester.widget<Text>(find.byKey(const Key('nightClock'))).data!;
    log('night clock after 35 s: $clock, epochs row: ${find.text('1').evaluate().length}');
    expect(clock, '0:00');

    await tester.tap(find.byKey(const Key('stopNight')));
    await pumpUntil(tester, find.text('Stop the night?'));
    await tester.tap(find.text('Stop the night'));
    await pumpUntil(tester, find.byKey(const Key('startNight')));
    final status = tester.widget<Text>(find.byKey(const Key('status'))).data!;
    log(status);
    expect(status, startsWith('Night saved: '));

    final edf = root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('_eeg.edf')).toList();
    expect(edf, hasLength(1));
    final header = String.fromCharCodes(edf.single.readAsBytesSync().sublist(236, 244)).trim();
    log('EDF ${edf.single.path}: $header records');
    expect(int.parse(header), inInclusiveRange(33, 40));
    // ignore: avoid_print
    print('E2E_NIGHT_FOLDER=${edf.single.parent.parent.path}');

    await tester.tap(find.text('Nights'));
    await pumpUntil(tester, find.textContaining('1 epochs'));
    await shot(tester, '05-nights-list');

    await tester.tap(find.text('Tonight'));
    await pumpUntil(tester, find.text('Stop'));
    await tester.tap(find.text('Stop'));
    await pumpUntil(tester, find.text('Start listening'));
    log('test 5 took ${t.elapsedMilliseconds} ms');
  });
}
