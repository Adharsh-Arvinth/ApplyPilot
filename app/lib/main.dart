import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'core/api_client.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/needs_you_screen.dart';
import 'screens/jobs_screen.dart';
import 'screens/answer_bank_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

void toggleThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  if (themeModeNotifier.value == ThemeMode.dark) {
    themeModeNotifier.value = ThemeMode.light;
    await prefs.setString("theme_mode", "light");
  } else {
    themeModeNotifier.value = ThemeMode.dark;
    await prefs.setString("theme_mode", "dark");
  }
}

void setThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  themeModeNotifier.value = mode;
  final str = mode == ThemeMode.light ? "light" : (mode == ThemeMode.dark ? "dark" : "system");
  await prefs.setString("theme_mode", str);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient().init();
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool("onboarding_complete") ?? false;
  
  final savedTheme = prefs.getString("theme_mode") ?? "dark";
  if (savedTheme == "light") {
    themeModeNotifier.value = ThemeMode.light;
  } else if (savedTheme == "system") {
    themeModeNotifier.value = ThemeMode.system;
  } else {
    themeModeNotifier.value = ThemeMode.dark;
  }

  runApp(ApplyPilotApp(initialOnboardingDone: onboardingDone));
}

class ApplyPilotApp extends StatefulWidget {
  final bool initialOnboardingDone;

  const ApplyPilotApp({super.key, required this.initialOnboardingDone});

  @override
  State<ApplyPilotApp> createState() => _ApplyPilotAppState();
}

class _ApplyPilotAppState extends State<ApplyPilotApp> {
  late bool _onboardingDone;

  @override
  void initState() {
    super.initState();
    _onboardingDone = widget.initialOnboardingDone;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'ApplyPilot',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: _onboardingDone
              ? const MainNavigationShell()
              : OnboardingScreen(
                  onFinish: () {
                    setState(() {
                      _onboardingDone = true;
                    });
                  },
                ),
        );
      },
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = [
      HomeScreen(
        onNavigateToNeedsYou: () => setState(() => _currentIndex = 1),
        onNavigateToJobs: () => setState(() => _currentIndex = 2),
        onNavigateToSettings: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
      const NeedsYouScreen(),
      const JobsScreen(),
      const AnswerBankScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        indicatorColor: AppColors.appleMusicRose.withOpacity(0.15),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded, color: AppColors.appleMusicRose),
            label: "Cockpit",
          ),
          NavigationDestination(
            icon: const Icon(Icons.mark_chat_unread_outlined),
            selectedIcon: const Icon(Icons.mark_chat_unread_rounded, color: AppColors.appleMusicRose),
            label: "Needs You",
          ),
          NavigationDestination(
            icon: const Icon(Icons.work_outline_rounded),
            selectedIcon: const Icon(Icons.work_rounded, color: AppColors.appleMusicRose),
            label: "Jobs",
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book_rounded, color: AppColors.appleMusicRose),
            label: "Answers",
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded, color: AppColors.appleMusicRose),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
