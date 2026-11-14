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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient().init();
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool("onboarding_complete") ?? false;
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
    return MaterialApp(
      title: 'ApplyPilot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
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
        indicatorColor: AppColors.accentLight.withOpacity(0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.accentLight),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.mark_chat_unread_outlined),
            selectedIcon: Icon(Icons.mark_chat_unread_rounded, color: AppColors.accentLight),
            label: "Needs You",
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline_rounded),
            selectedIcon: Icon(Icons.work_rounded, color: AppColors.accentLight),
            label: "Jobs",
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded, color: AppColors.accentLight),
            label: "Answers",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.accentLight),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
