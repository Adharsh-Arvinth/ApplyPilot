import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme.dart';
import 'core/api_client.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/needs_you_screen.dart';
import 'screens/application_tracker_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/answer_bank_screen.dart';
import 'screens/resume_manager_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/automation_control_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/ai_assistant_screen.dart';

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

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

  final savedTheme = prefs.getString("theme_mode") ?? "light";
  if (savedTheme == "dark") {
    themeModeNotifier.value = ThemeMode.dark;
  } else if (savedTheme == "system") {
    themeModeNotifier.value = ThemeMode.system;
  } else {
    themeModeNotifier.value = ThemeMode.light;
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

  void _navigateToTab(int index) {
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  void _pushScreen(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onNavigateToDiscover: () => _navigateToTab(1),
        onNavigateToTracker: () => _navigateToTab(2),
        onNavigateToNeedsYou: () => _navigateToTab(3),
        onNavigateToAnalytics: () => _pushScreen(const AnalyticsScreen()),
        onNavigateToControlCenter: () => _pushScreen(const AutomationControlScreen()),
        onNavigateToSettings: () => _pushScreen(const SettingsScreen()),
      ),
      const DiscoverScreen(),
      const ApplicationTrackerScreen(),
      const NeedsYouScreen(),
      HubScreen(
        onOpenAnalytics: () => _pushScreen(const AnalyticsScreen()),
        onOpenResumes: () => _pushScreen(const ResumeManagerScreen()),
        onOpenAnswerBank: () => _pushScreen(const AnswerBankScreen()),
        onOpenProfile: () => _pushScreen(const ProfileScreen()),
        onOpenAutomation: () => _pushScreen(const AutomationControlScreen()),
        onOpenSettings: () => _pushScreen(const SettingsScreen()),
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _navigateToTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: "Dashboard",
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: "Discover",
          ),
          NavigationDestination(
            icon: Icon(Icons.view_kanban_outlined),
            selectedIcon: Icon(Icons.view_kanban),
            label: "Tracker",
          ),
          NavigationDestination(
            icon: Icon(Icons.help_outline),
            selectedIcon: Icon(Icons.help),
            label: "Needs You",
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: "Hub",
          ),
        ],
      ),
    );
  }
}

class HubScreen extends StatelessWidget {
  final VoidCallback onOpenAnalytics;
  final VoidCallback onOpenResumes;
  final VoidCallback onOpenAnswerBank;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenAutomation;
  final VoidCallback onOpenSettings;

  const HubScreen({
    super.key,
    required this.onOpenAnalytics,
    required this.onOpenResumes,
    required this.onOpenAnswerBank,
    required this.onOpenProfile,
    required this.onOpenAutomation,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final brassColor = isDark ? AppColors.brassDark : AppColors.mutedBrass;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Career Hub",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          Text(
            "INTELLIGENCE & AI COPILOT",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "AI Career Advisor (Gemini 2.5)",
            "Real-time interview coach, resume strategy & offer negotiation",
            Icons.auto_awesome,
            AppColors.getSemanticColor("violet", isDark),
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantScreen())),
          ),
          const SizedBox(height: AppSpacing.s20),
          Text(
            "CANDIDATE INTELLIGENCE & ASSETS",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "Candidate Profile",
            "Personal facts, target roles, locations & master resume",
            Icons.person_outline,
            accentGreen,
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            onOpenProfile,
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "Resume Manager",
            "Multiple versions, ATS scoring & job-specific tailoring",
            Icons.description_outlined,
            accentGreen,
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            onOpenResumes,
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "Answer Bank",
            "Verified truth repository & past ATS form memories",
            Icons.menu_book_outlined,
            brassColor,
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            onOpenAnswerBank,
          ),

          const SizedBox(height: AppSpacing.s20),

          Text(
            "ENGINE OPERATIONS & INSIGHTS",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "Analytics & Conversion Funnel",
            "Weekly trends, match distributions & platform stats",
            Icons.bar_chart_outlined,
            AppColors.successLight,
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            onOpenAnalytics,
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "Automation Control Center",
            "Live/Dry-Run switch, rate limits & emergency pause",
            Icons.tune_outlined,
            brassColor,
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            onOpenAutomation,
          ),
          const SizedBox(height: AppSpacing.s8),
          _buildHubTile(
            "Settings & Connectivity",
            "Tailscale connection, token rotation, theme & backups",
            Icons.settings_outlined,
            secondaryTextColor,
            cardBg,
            borderColor,
            primaryTextColor,
            secondaryTextColor,
            onOpenSettings,
          ),
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }

  Widget _buildHubTile(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    VoidCallback onTap,
  ) {
    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: borderColor),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
        leading: Container(
          padding: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 11, color: secondaryTextColor)),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}
