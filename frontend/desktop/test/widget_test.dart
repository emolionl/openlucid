import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/app/headband.dart';
import 'package:openlucid/app/settings.dart';
import 'package:openlucid/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(OpenLucidApp(settings: settings, headband: Headband(settings)));
}

void main() {
  testWidgets('phone: bottom navigation and the Tonight screen', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Start listening'), findsOneWidget);
    expect(tester.takeException(), isNull); // nothing overflows
  });

  testWidgets('laptop: side rail with labels', (tester) async {
    await pumpAt(tester, const Size(1280, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Start listening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in [
    ('small phone', const Size(360, 640)),
    ('phone', const Size(390, 844)),
    ('phone landscape', const Size(844, 390)),
    ('tablet', const Size(700, 1000)),
    ('laptop', const Size(1280, 800)),
  ]) {
    testWidgets('$name: listening to Fake Moose fits on screen', (tester) async {
      await pumpAt(tester, size);
      await tester.tap(find.text('Start listening'));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Live signal'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Stop'));
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  testWidgets('phone: the eye check opens from Tonight and fits', (tester) async {
    await pumpAt(tester, const Size(360, 640));
    await tester.tap(find.text('Start listening'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Eye check'));
    await tester.pumpAndSettle();

    expect(find.text('Can your headband see your eyes?'), findsOneWidget);
    expect(find.textContaining('Start'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('settings: wave at the Diary Keeper, choose 50 or 60 Hz', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Wave at the Diary Keeper'), findsOneWidget);
    expect(find.text('Not asked yet.'), findsOneWidget);

    await tester.tap(find.text('60 Hz'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('mainsHz'), 60);
  });

  testWidgets('placeholders for nights and journal', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    Headband.nightsFolderOverride = () async => Directory('${Directory.systemTemp.path}/openlucid-no-nights-here');
    await tester.tap(find.text('Nights'));
    // Reading the folder is real file access: give it real time, then draw again.
    for (var i = 0; i < 20 && find.text('No nights yet').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('No nights yet'), findsOneWidget);

    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();
    expect(find.text('Your dream journal'), findsOneWidget);
  });
}
