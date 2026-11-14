import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:applypilot/main.dart';

void main() {
  testWidgets('ApplyPilotApp boots properly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({"onboarding_complete": true});
    await tester.pumpWidget(const ApplyPilotApp(initialOnboardingDone: true));
    expect(find.byType(ApplyPilotApp), findsOneWidget);
  });
}
