import 'package:auralyze_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Auralyze product shell renders', (tester) async {
    await tester.pumpWidget(const AuralyzeApp());
    await tester.pump();

    expect(find.text('Auralyze'), findsOneWidget);
    expect(find.text('AI AUDIO DIAGNOSIS COPILOT'), findsOneWidget);
    expect(find.text('Run demo analysis'), findsOneWidget);
  });
}
