import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:applypilot/main.dart';
import 'package:applypilot/core/theme.dart';
import 'package:applypilot/widgets/smart_widgets.dart';
import 'package:applypilot/widgets/interactive_charts.dart';
import 'package:applypilot/screens/ai_assistant_screen.dart';
import 'package:applypilot/core/motion.dart';

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

    // Verify semantic colors
    expect(AppColors.getSemanticColor("emerald", false), AppColors.emeraldLight);
    expect(AppColors.getSemanticColor("blue", true), AppColors.semanticBlueDark);
    expect(AppColors.getSemanticColor("coral", false), AppColors.coralLight);
    expect(AppColors.getSemanticColor("teal", true), AppColors.tealDark);
  });

  testWidgets('ApplicationGoalWidget and StatusDonutChart render accurately', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ListView(
          children: [
            ApplicationGoalWidget(
              goalData: const {
                "daily_target": 50,
                "daily_applied": 12,
                "daily_remaining": 38,
                "daily_percent": 24.0,
                "weekly_target": 250,
                "weekly_applied": 65,
                "weekly_remaining": 185,
                "weekly_percent": 26.0,
              },
              onAdjustTarget: () {},
            ),
            const StatusDonutChart(
              statusDistribution: {
                "submitted": 10,
                "interview": 2,
                "approved": 5,
                "evaluated": 8,
                "discovered": 20,
                "rejected": 4,
              },
              totalCount: 49,
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text("DAILY GOAL"), findsOneWidget);
    expect(find.text("12"), findsOneWidget);
    expect(find.text("24%"), findsOneWidget);
    expect(find.text("APPLICATION STATUS DISTRIBUTION"), findsOneWidget);
    expect(find.text("49"), findsOneWidget);
  });

  testWidgets('AiAssistantScreen renders career advisor header and quick prompts', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const AiAssistantScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text("Career Advisor"), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text("Review my top matched jobs today"), findsOneWidget);
  });

  testWidgets('AppMotion components render and handle interactions', (WidgetTester tester) async {
    bool tapped = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: ListView(
          children: [
            InteractivePressable(
              onTap: () => tapped = true,
              child: const Text("Pressable Target"),
            ),
            const MotionFadeSlide(
              index: 0,
              child: Text("Staggered Item 0"),
            ),
            const ShimmerSkeleton(width: 120, height: 20),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Pressable Target"), findsOneWidget);
    expect(find.text("Staggered Item 0"), findsOneWidget);
    expect(find.byType(ShimmerSkeleton), findsOneWidget);

    await tester.tap(find.text("Pressable Target"));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tapped, isTrue);
  });
}

