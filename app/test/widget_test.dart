import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:applypilot/main.dart';
import 'package:applypilot/core/theme.dart';

void main() {
  testWidgets('ApplyPilotApp boots to MainNavigationShell when onboarding is complete', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({"onboarding_complete": true});
    await tester.pumpWidget(const ApplyPilotApp(initialOnboardingDone: true));
    await tester.pumpAndSettle();

    expect(find.byType(ApplyPilotApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text("Dashboard"), findsOneWidget);
    expect(find.text("Discover"), findsOneWidget);
    expect(find.text("Tracker"), findsOneWidget);
    expect(find.text("Needs You"), findsOneWidget);
    expect(find.text("Hub"), findsOneWidget);
  });

  testWidgets('ApplyPilotApp boots to OnboardingScreen when onboarding is false', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({"onboarding_complete": false});
    await tester.pumpWidget(const ApplyPilotApp(initialOnboardingDone: false));
    await tester.pumpAndSettle();

    expect(find.byType(ApplyPilotApp), findsOneWidget);
    expect(find.text("ApplyPilot"), findsWidgets);
  });

  testWidgets('AppTheme defines British Racing Green and Obsidian Dark themes', (WidgetTester tester) async {
    final light = AppTheme.lightTheme;
    final dark = AppTheme.darkTheme;

    expect(light.colorScheme.primary, AppColors.racingGreen);
    expect(light.scaffoldBackgroundColor, AppColors.warmIvory);
    expect(dark.colorScheme.primary, AppColors.accentDark);
    expect(dark.scaffoldBackgroundColor, AppColors.canvasDark);
  });
}

