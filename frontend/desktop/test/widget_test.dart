import 'package:flutter_test/flutter_test.dart';
import 'package:openlucid/main.dart';

void main() {
  testWidgets('shows the wave button before asking', (tester) async {
    await tester.pumpWidget(const OpenLucidApp());

    expect(find.text('Wave at the Diary Keeper'), findsOneWidget);
    expect(find.text('Not asked yet.'), findsOneWidget);
  });

  testWidgets('Fake Moose is the default and can start listening', (tester) async {
    await tester.pumpWidget(const OpenLucidApp());

    expect(find.text('Start listening'), findsOneWidget);
    expect(find.text('The live signal appears here.'), findsOneWidget);
  });
}
