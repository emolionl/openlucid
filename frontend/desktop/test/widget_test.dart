import 'package:flutter_test/flutter_test.dart';
import 'package:lucid_desktop/main.dart';

void main() {
  testWidgets('shows the wave button before asking', (tester) async {
    await tester.pumpWidget(const LucidApp());

    expect(find.text('Wave at the Diary Keeper'), findsOneWidget);
    expect(find.text('Not asked yet.'), findsOneWidget);
  });
}
