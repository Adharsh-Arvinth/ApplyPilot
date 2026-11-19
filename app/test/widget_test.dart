import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:applypilot/main.dart';
import 'package:applypilot/shell/connect_screen.dart';
import 'package:applypilot/shell/shell_config.dart';
import 'package:applypilot/shell/shell_theme.dart';
import 'package:applypilot/core/theme.dart';
import 'package:applypilot/widgets/smart_widgets.dart';
import 'package:applypilot/widgets/interactive_charts.dart';
import 'package:applypilot/screens/ai_assistant_screen.dart';
import 'package:applypilot/core/motion.dart';

void main() {
  testWidgets('A fresh install opens the connect screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final cfg = await ShellConfig.load();
    expect(cfg.ready, isFalse);

    await tester.pumpWidget(ApplyPilotApp(initialConfig: cfg));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing); // nothing to go back to yet
  });

  test('Settings saved by the previous app carry over, so upgrades skip setup', () async {
    SharedPreferences.setMockInitialValues({'server_url': 'http://100.1.2.3:8000/', 'auth_token': 'abc'});
    final cfg = await ShellConfig.load();
    expect(cfg.ready, isTrue);
    expect(cfg.serverUrl, 'http://100.1.2.3:8000');
    expect(cfg.cockpitUri().toString(), 'http://100.1.2.3:8000/app/?token=abc');
  });

  test('Cockpit theme messages drive the native bar colours', () {
    final light = ShellPalette.fromMessage('theme:#F4F4F2:light')!;
    expect(light.bg, const Color(0xFFF4F4F2));
    expect(light.dark, isFalse);
    expect(light.overlay.statusBarIconBrightness, Brightness.dark); // dark icons on a light bar

    final midnight = ShellPalette.fromMessage('theme:#070B18:dark')!;
    expect(midnight.bg, const Color(0xFF070B18));
    expect(midnight.overlay.statusBarIconBrightness, Brightness.light);

    expect(ShellPalette.fromMessage('change-server'), isNull);
    expect(ShellPalette.fromMessage('theme:not-a-colour:dark'), isNull);
  });

  test('Server addresses are normalized', () {
    expect(ShellConfig.normalizeUrl(' 100.64.0.1:8000 '), 'http://100.64.0.1:8000');
    expect(ShellConfig.normalizeUrl('https://pc.tail.net/app/'), 'https://pc.tail.net');
    expect(ShellConfig.normalizeUrl('http://pc:8000//'), 'http://pc:8000');
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

