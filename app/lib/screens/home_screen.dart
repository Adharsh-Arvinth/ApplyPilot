import 'package:intl/intl.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/apple_music_theme.dart';
import '../widgets/smart_widgets.dart';
import 'ai_assistant_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToDiscover;
  final VoidCallback onNavigateToNeedsYou;
  final VoidCallback onNavigateToTracker;
  final VoidCallback onNavigateToAnalytics;
  final VoidCallback onNavigateToControlCenter;
  final VoidCallback onNavigateToSettings;

  const HomeScreen({
    super.key,
    required this.onNavigateToDiscover,
    required this.onNavigateToNeedsYou,
    required this.onNavigateToTracker,
    required this.onNavigateToAnalytics,
    required this.onNavigateToControlCenter,
    required this.onNavigateToSettings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiClient _api = ApiClient();
  Timer? _refreshTimer;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _health = {"status": "connecting"};
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _analytics = {};
  Map<String, dynamic> _profile = {};
  List<dynamic> _logs = [];
  List<dynamic> _needsYouItems = [];
  final Set<int> _expandedLogIndices = {};

  DashboardPreferences _prefs = DashboardPreferences.defaults();
  String _dateFilter = "Today"; // "Today", "This Week", "All Time"
  DateTime _lastSyncTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _fetchDashboardData();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted) _fetchDashboardData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final saved = await _api.loadWidgetPreferences();
      if (saved.isNotEmpty && mounted) {
        setState(() {
          _prefs = DashboardPreferences.fromJson(saved);
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchDashboardData({bool silent = false}) async {
    try {
      final healthFuture = _api.checkHealth();
      final statsFuture = _api.getStats();
      final analyticsFuture = _api.getAnalytics();
      final profileFuture = _api.getProfile();
      final logsFuture = _api.getRunLogs();
      final needsYouFuture = _api.getNeedsYou();

      final results = await Future.wait([
        healthFuture,
        statsFuture,
        analyticsFuture,
        profileFuture,
        logsFuture,
        needsYouFuture,
      ]).timeout(const Duration(seconds: 6));

      if (mounted) {
        setState(() {
          _health = results[0] as Map<String, dynamic>;
          _stats = results[1] as Map<String, dynamic>;
          _analytics = results[2] as Map<String, dynamic>;
          _profile = results[3] as Map<String, dynamic>;
          _logs = (results[4] as List<dynamic>).take(8).toList();
          _needsYouItems = results[5] as List<dynamic>;
          _lastSyncTime = DateTime.now();
          _error = null;
          _loading = false;
        });

        // Also check if remote profile had widget preferences
        final remoteWidgets = _profile["widget_preferences"];
        if (remoteWidgets is Map<String, dynamic> && remoteWidgets.isNotEmpty) {
          _prefs = DashboardPreferences.fromJson(remoteWidgets);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          if (!silent) _loading = false;
        });
      }
    }
  }

  Future<void> _quickResolveNeedsYou(int id, String answer) async {
    HapticFeedback.mediumImpact();
    try {
      await _api.resolveNeedsYou(id, answer, saveToBank: true, mode: "always_use");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.successEmerald,
            content: Text("Choice saved to Answer Bank! Automation resumed."),
          ),
        );
        _fetchDashboardData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.errorCoral,
            content: Text("Failed to submit answer: $e"),
          ),
        );
      }
    }
  }

  Future<void> _resumeAutomationFlow() async {
    HapticFeedback.mediumImpact();
    // 1. Optimistic state update: flip immediately to Running
    setState(() {
      _profile["is_paused"] = false;
      _stats["is_paused"] = false;
      _stats["automation_state"] = "running";
      _stats["pause_reason"] = "";
    });
    try {
      final res = await _api.resumeAutomation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.successEmerald,
            content: Text(res["message"] ?? "Automation resumed successfully!"),
            action: SnackBarAction(
              label: "PAUSE",
              textColor: AppColors.pureWhite,
              onPressed: _pauseAutomationFlow,
            ),
          ),
        );
      }
      _fetchDashboardData(silent: true);
    } catch (e) {
      if (mounted) {
        // Revert on error
        setState(() {
          _profile["is_paused"] = true;
          _stats["is_paused"] = true;
          _stats["automation_state"] = "paused_by_user";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.errorCoral,
            content: Text("Cannot resume: $e"),
          ),
        );
      }
    }
  }

  Future<void> _pauseAutomationFlow() async {
    HapticFeedback.mediumImpact();
    // 1. Optimistic state update: flip immediately to Paused
    setState(() {
      _profile["is_paused"] = true;
      _stats["is_paused"] = true;
      _stats["automation_state"] = "paused_by_user";
      _stats["pause_reason"] = "paused_by_user";
      _stats["pause_details"] = "Paused manually from dashboard";
      _stats["recovery_instruction"] = "Tap 'Resume Automation' to restart autonomous processing.";
    });
    try {
      await _api.pauseAutomation(reason: "paused_by_user", details: "Paused manually from dashboard");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Automation paused."),
            action: SnackBarAction(
              label: "RESUME",
              textColor: AppColors.successEmerald,
              onPressed: _resumeAutomationFlow,
            ),
          ),
        );
      }
      _fetchDashboardData(silent: true);
    } catch (e) {
      if (mounted) {
        // Revert on error
        setState(() {
          _profile["is_paused"] = false;
          _stats["is_paused"] = false;
          _stats["automation_state"] = "running";
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to pause: $e")));
      }
    }
  }

  Future<void> _togglePause() async {
    HapticFeedback.mediumImpact();
    try {
      await _api.togglePause();
      _fetchDashboardData(silent: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Action failed: $e")));
    }
  }

  Future<void> _triggerApplyNext() async {
    HapticFeedback.heavyImpact();
    try {
      final res = await _api.applyNext();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res["message"] ?? "Processing next application in queue...")),
      );
      _fetchDashboardData(silent: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Apply failed: $e")));
    }
  }

  void _openCustomizer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      builder: (context) {
        return WidgetCustomizerSheet(
          currentPrefs: _prefs,
          onSave: (newPrefs) async {
            setState(() => _prefs = newPrefs);
            await _api.saveWidgetPreferences(newPrefs.toJson());
          },
        );
      },
    );
  }

  void _openInterviewPrepModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final teal = AppColors.getSemanticColor("teal", isDark);

    final interview = _analytics["upcoming_interview"] as Map<String, dynamic>?;
    final company = interview?["company"] ?? "Interview Candidate";
    final title = interview?["title"] ?? "Role";
    final notes = interview?["notes"] ?? "Prepare system design & ML pipelines";
    final recruiter = interview?["recruiter_info"] ?? "Talent Lead";
    final proofs = (interview?["proof_points"] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.s24),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology_outlined, color: teal, size: 22),
                      const SizedBox(width: AppSpacing.s8),
                      Text("Interview Preparation Sheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryTextColor)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(company, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor)),
              Text(title, style: TextStyle(fontSize: 13, color: secondaryTextColor)),
              const Divider(height: 24),
              Text("RECRUITER & SOURCING CONTEXT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
              const SizedBox(height: 4),
              Text(recruiter, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
              const SizedBox(height: AppSpacing.s12),
              Text("TECHNICAL FOCUS & TOPICS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
              const SizedBox(height: 4),
              Text(notes, style: TextStyle(fontSize: 12, color: primaryTextColor)),
              const SizedBox(height: AppSpacing.s16),
              Text("VERIFIED PROOF POINTS TO HIGHLIGHT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: teal)),
              const SizedBox(height: AppSpacing.s8),
              ...proofs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: teal),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p, style: TextStyle(fontSize: 12, color: primaryTextColor))),
                  ],
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final emerald = AppColors.getSemanticColor("emerald", isDark);

    final isOnline = _health["status"] == "online" || _health["status"] == "healthy";
    final isPaused = _profile["is_paused"] ?? false;

    // Filter widgets by visibility and arrange by pinned then order
    final visibleOrder = _prefs.order.where((k) => _prefs.visible.contains(k)).toList();
    final pinnedList = visibleOrder.where((k) => _prefs.pinned.contains(k)).toList();
    final unpinnedList = visibleOrder.where((k) => !_prefs.pinned.contains(k)).toList();
    final finalWidgetOrder = [...pinnedList, ...unpinnedList];

    return Scaffold(
      backgroundColor: isDark ? AppleMusicTheme.background : AppColors.canvasLight,
      appBar: AppBar(
        titleSpacing: AppSpacing.s16,
        elevation: 0,
        backgroundColor: isDark ? AppleMusicTheme.background : AppColors.surfaceLight,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "ApplyPilot",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: isDark ? AppleMusicTheme.textPrimary : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppleMusicTheme.emeraldSubtle : AppColors.racingGreenSubtle,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark ? AppleMusicTheme.emerald.withOpacity(0.3) : AppColors.racingGreen.withOpacity(0.3),
                  width: 0.8,
                ),
              ),
              child: Text(
                "AUTONOMOUS",
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: isDark ? AppleMusicTheme.emerald : AppColors.racingGreen,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppleMusicTheme.violetSubtle,
                borderRadius: BorderRadius.circular(AppleMusicTheme.radiusControl),
                border: Border.all(color: AppleMusicTheme.violet.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 13, color: AppleMusicTheme.violet),
                  SizedBox(width: 4),
                  Text(
                    "AI Copilot",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppleMusicTheme.violet,
                    ),
                  ),
                ],
              ),
            ),
            tooltip: "Gemini Career Copilot",
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantScreen()));
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: secondaryTextColor),
            tooltip: "More Options",
            onSelected: (val) {
              if (val == "customize") _openCustomizer();
              if (val == "analytics") widget.onNavigateToAnalytics();
              if (val == "control") widget.onNavigateToControlCenter();
              if (val == "settings") widget.onNavigateToSettings();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: "customize",
                child: Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, size: 18),
                    SizedBox(width: 8),
                    Text("Customize Widgets"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: "analytics",
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 18),
                    SizedBox(width: 8),
                    Text("Analytics"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: "control",
                child: Row(
                  children: [
                    Icon(Icons.tune_outlined, size: 18),
                    SizedBox(width: 8),
                    Text("Control Center"),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: "settings",
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 18),
                    SizedBox(width: 8),
                    Text("Settings"),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 2.5, color: accentGreen),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    "Synchronizing Command Center...",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: secondaryTextColor),
                  ),
                ],
              ),
            )
          : (_error != null && _stats.isEmpty)
              ? _buildOfflineRecoveryView(context, isDark, primaryTextColor, secondaryTextColor, accentGreen)
              : RefreshIndicator(
                  onRefresh: () => _fetchDashboardData(),
                  color: accentGreen,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 900) {
                        return _buildDesktopDashboard(context, isDark, primaryTextColor, secondaryTextColor, cardBg, borderColor, accentGreen, emerald, isOnline, isPaused);
                      }
                      return _buildMobileDashboard(context, isDark, primaryTextColor, secondaryTextColor, cardBg, borderColor, accentGreen, emerald, isOnline, isPaused, finalWidgetOrder);
                    },
                  ),
                ),
    );
  }

  Widget _buildDesktopDashboard(
    BuildContext context,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color cardBg,
    Color borderColor,
    Color accentGreen,
    Color emerald,
    bool isOnline,
    bool isPaused,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Desktop Status Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? emerald : AppColors.getSemanticColor("coral", isDark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? "FastAPI & Tailscale Connected (Port 8000)" : "Host Connection Offline",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "• Synced ${_lastSyncTime.hour.toString().padLeft(2, '0')}:${_lastSyncTime.minute.toString().padLeft(2, '0')}:${_lastSyncTime.second.toString().padLeft(2, '0')}",
                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildDateFilterChip("Today", _dateFilter == "Today"),
                  const SizedBox(width: 6),
                  _buildDateFilterChip("Week", _dateFilter == "Week"),
                  const SizedBox(width: 6),
                  _buildDateFilterChip("All", _dateFilter == "All"),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Two-column responsive executive command center
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column (flex 6)
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAutomationStatusBanner(isDark),
                    const SizedBox(height: 16),
                    _buildDesktopKPIGrid(isDark, cardBg, borderColor, primaryTextColor, secondaryTextColor, accentGreen),
                    const SizedBox(height: 16),
                    _buildWidgetByKey(WidgetConfig.funnel, isDark, isPaused),
                    const SizedBox(height: 16),
                    _buildWidgetByKey(WidgetConfig.match, isDark, isPaused),
                    const SizedBox(height: 16),
                    _buildExecutionLogStream(isDark, cardBg, borderColor, primaryTextColor, secondaryTextColor, emerald),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              // Right Column (flex 4)
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNeedsYouDecisionCard(isDark, cardBg, borderColor, primaryTextColor, secondaryTextColor, accentGreen),
                    const SizedBox(height: 16),
                    _buildSystemDiagnosticsCard(isDark, cardBg, borderColor, primaryTextColor, secondaryTextColor, accentGreen),
                    const SizedBox(height: 16),
                    _buildWidgetByKey(WidgetConfig.goal, isDark, isPaused),
                    const SizedBox(height: 16),
                    _buildWidgetByKey(WidgetConfig.quickActions, isDark, isPaused),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMobileDashboard(
    BuildContext context,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color cardBg,
    Color borderColor,
    Color accentGreen,
    Color emerald,
    bool isOnline,
    bool isPaused,
    List<String> finalWidgetOrder,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 1. Top Header: Date, Status pill, and Serif "Hello, Alex"
        _buildStitchGreetingHeader(isDark),

        if (isPaused) ...[
          const SizedBox(height: 12),
          _buildAutomationStatusBanner(isDark),
        ],

        const SizedBox(height: 16),

        // 2. Section 1: Daily Quota Donut + Stacked Status Metrics
        _buildStitchQuotaAndKPIs(isDark),

        const SizedBox(height: 14),

        // 3. Section 2: 7-Day Weekly Dispatch Velocity
        _buildStitchWeeklyVelocity(isDark),

        const SizedBox(height: 14),

        // 4. Section 3: Pipeline Conversion Funnel
        _buildStitchConversionFunnel(isDark),

        const SizedBox(height: 14),

        // 5. Section 4: 24-Hour Dispatch Frequency Wave
        _buildStitchDispatchFrequency(isDark),

        const SizedBox(height: 14),

        // 6. Section 5: "Now Applying Live" Action Card
        _buildStitchNowApplying(isDark),

        const SizedBox(height: 14),

        // 7. Section 6: Live Activity Stream / Audit
        _buildStitchRecentActivity(isDark),

        if (_needsYouItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildNeedsYouDecisionCard(isDark, cardBg, borderColor, primaryTextColor, secondaryTextColor, accentGreen),
        ],

        const SizedBox(height: 14),

        _buildExecutionLogStream(isDark, cardBg, borderColor, primaryTextColor, secondaryTextColor, emerald),

        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildStatusChipsRow(bool isDark, Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    final goLive = _profile["go_live"] == true;
    final isOnline = _health["status"] == "online" || _health["status"] == "healthy";

    final liveDotColor = isDark ? const Color(0xFF7FD1A8) : const Color(0xFF2F6F4F);
    final dryDotColor = isDark ? const Color(0xFF8A908A) : const Color(0xFF6E736E);
    final onlineDotColor = isDark ? const Color(0xFF7FD1A8) : const Color(0xFF2F6F4F);
    final offlineDotColor = isDark ? const Color(0xFFE5736B) : const Color(0xFFC0392B);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: goLive ? liveDotColor : dryDotColor),
              ),
              const SizedBox(width: 6),
              Text(
                goLive ? "Live" : "Dry-run",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: goLive ? liveDotColor : secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: isOnline ? onlineDotColor : offlineDotColor),
              ),
              const SizedBox(width: 6),
              Text(
                isOnline ? "PC Active" : "PC Offline",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: isOnline ? primaryTextColor : offlineDotColor,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          "Synced ${_lastSyncTime.hour.toString().padLeft(2, '0')}:${_lastSyncTime.minute.toString().padLeft(2, '0')}",
          style: TextStyle(fontSize: 11, color: secondaryTextColor),
        ),
      ],
    );
  }

  Widget _buildProgressRingHero(bool isDark, Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor, Color accentGreen) {
    final int appliedToday = (_stats["daily_applied"] as num? ?? 0).toInt();
    final int realApplied = (_stats["real_applied_today"] as num? ?? 0).toInt();
    final int dryRunToday = (_stats["dry_run_today"] as num? ?? 0).toInt();
    final int dailyCap = (_stats["daily_cap"] as num? ?? 100).toInt();
    final double ratio = dailyCap > 0 ? (appliedToday / dailyCap).clamp(0.0, 1.0) : 0.0;

    final trackColor = isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF0F0EC);
    final progressColor = isDark ? const Color(0xFF7FD1A8) : const Color(0xFF2F6F4F);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: ratio),
                  duration: const Duration(milliseconds: 250),
                  curve: const Cubic(0.2, 0.0, 0.0, 1.0),
                  builder: (context, value, _) {
                    return SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 10,
                        backgroundColor: trackColor,
                        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                        strokeCap: StrokeCap.round,
                      ),
                    );
                  },
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: appliedToday),
                      duration: const Duration(milliseconds: 250),
                      curve: const Cubic(0.2, 0.0, 0.0, 1.0),
                      builder: (context, count, _) {
                        return Text(
                          "$count / $dailyCap",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: primaryTextColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "today",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "$realApplied real • $dryRunToday dry-run",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: secondaryTextColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreeQuietStatRows(bool isDark, Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor, Color accentGreen) {
    final int realAppliedToday = (_stats["real_applied_today"] as num? ?? 0).toInt();
    final int totalDryRun = (_stats["total_dry_run"] as num? ?? _stats["dry_run_today"] ?? 0).toInt();
    final int nyCount = (_stats["needs_you_count"] as num? ?? _needsYouItems.length).toInt();
    final int interviewCount = (_stats["interview_count"] as num? ?? 0).toInt();

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        children: [
          _buildQuietStatTile(
            label: "Applied",
            value: "$realAppliedToday real",
            subValue: "($totalDryRun dry-run total)",
            dotColor: isDark ? const Color(0xFF7FD1A8) : const Color(0xFF2F6F4F),
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToTracker,
            showDivider: true,
            borderColor: borderColor,
          ),
          _buildQuietStatTile(
            label: "Needs You",
            value: "$nyCount",
            subValue: nyCount > 0 ? "actions pending" : "inbox clear",
            dotColor: nyCount > 0 ? (isDark ? const Color(0xFFE6B450) : const Color(0xFF996500)) : (isDark ? const Color(0xFF8A908A) : const Color(0xFF6E736E)),
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToNeedsYou,
            showDivider: true,
            borderColor: borderColor,
          ),
          _buildQuietStatTile(
            label: "Interviews",
            value: "$interviewCount",
            subValue: "active rounds",
            dotColor: isDark ? const Color(0xFF7FD1A8) : const Color(0xFF2F6F4F),
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToTracker,
            showDivider: false,
            borderColor: borderColor,
          ),
        ],
      ),
    );
  }

  Widget _buildQuietStatTile({
    required String label,
    required String value,
    required String subValue,
    required Color dotColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required VoidCallback onTap,
    required bool showDivider,
    required Color borderColor,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: primaryTextColor),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  subValue,
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 16, color: secondaryTextColor),
              ],
            ),
          ),
          if (showDivider)
            Divider(height: 1, thickness: 1, color: borderColor, indent: 16, endIndent: 16),
        ],
      ),
    );
  }

  Widget _buildNeedsYouDecisionCard(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentGreen,
  ) {
    final amber = AppColors.getSemanticColor("amber", isDark);
    final emerald = AppColors.getSemanticColor("emerald", isDark);

    if (_needsYouItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: emerald.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: emerald.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_user_outlined, size: 18, color: emerald),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Autonomous ATS Shield Active",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primaryTextColor),
                      ),
                      Text(
                        "0 fields waiting for human choice",
                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "All applications are resolving autonomously via verified candidate intelligence and Answer Bank memories. When an employer form asks an unfamiliar question or dropdown, it appears here for you to choose.",
              style: TextStyle(fontSize: 11.5, height: 1.4, color: secondaryTextColor),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: amber.withOpacity(0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.ballot_outlined, size: 18, color: amber),
                  const SizedBox(width: 8),
                  Text(
                    "CHOOSE FROM THE BOX (${_needsYouItems.length} PENDING)",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: amber),
                  ),
                ],
              ),
              InkWell(
                onTap: widget.onNavigateToNeedsYou,
                child: Text(
                  "View All →",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "An employer's application form requires a selection. Click an option below to save to Answer Bank and submit:",
            style: TextStyle(fontSize: 11.5, color: secondaryTextColor),
          ),
          const SizedBox(height: 12),
          ..._needsYouItems.take(2).map((item) {
            final id = item["id"] as int;
            final company = (item["company"] ?? "Employer").toString();
            final role = (item["role"] ?? "Role").toString();
            final question = (item["question_text"] ?? "").toString();
            final options = (item["options"] as List<dynamic>?) ?? [];

            List<String> displayOptions = options.map((e) => e.toString()).toList();
            if (displayOptions.isEmpty) {
              final qLower = question.toLowerCase();
              if (qLower.contains("visa") || qLower.contains("sponsor") || qLower.contains("authorized") || qLower.contains("relocate") || qLower.contains("remote") || qLower.contains("require") || qLower.contains("are you") || qLower.contains("will you") || qLower.contains("do you")) {
                displayOptions = ["No", "Yes"];
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        company,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryTextColor),
                      ),
                      Text(
                        role,
                        style: TextStyle(fontSize: 10, color: secondaryTextColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                  ),
                  const SizedBox(height: 8),
                  if (displayOptions.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: displayOptions.map((opt) {
                        return ElevatedButton(
                          onPressed: () => _quickResolveNeedsYou(id, opt),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentGreen.withOpacity(0.15),
                            foregroundColor: accentGreen,
                            elevation: 0,
                            side: BorderSide(color: accentGreen.withOpacity(0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text(
                            opt,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.onNavigateToNeedsYou,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: accentGreen),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text("Answer in Needs You", style: TextStyle(fontSize: 11, color: accentGreen)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDesktopKPIGrid(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentGreen,
  ) {
    final queue = _stats["queue_count"] ?? 0;
    final dryRun = _stats["total_dry_run"] ?? 5;
    final liveSubmitted = _stats["total_submitted_real"] ?? 0;
    final needsInput = _needsYouItems.length;

    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: "ACTIVE QUEUE",
            value: "$queue",
            subtitle: "Ready for ATS fill",
            icon: Icons.layers_outlined,
            color: AppleMusicTheme.blue,
            cardBg: cardBg,
            borderColor: borderColor,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToTracker,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: "DRY-RUN VERIFIED",
            value: "$dryRun",
            subtitle: "DOM Proofs Captured",
            icon: Icons.checklist_rtl_rounded,
            color: AppleMusicTheme.amber,
            cardBg: cardBg,
            borderColor: borderColor,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToTracker,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: "LIVE SUBMISSIONS",
            value: "$liveSubmitted",
            subtitle: "Confirmed with ATS",
            icon: Icons.task_alt_rounded,
            color: AppleMusicTheme.emerald,
            cardBg: cardBg,
            borderColor: borderColor,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToTracker,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: "NEEDS ACTION",
            value: "$needsInput",
            subtitle: "Dropdown choices",
            icon: Icons.ballot_outlined,
            color: needsInput > 0 ? AppleMusicTheme.coral : secondaryTextColor,
            cardBg: cardBg,
            borderColor: borderColor,
            primaryTextColor: primaryTextColor,
            secondaryTextColor: secondaryTextColor,
            onTap: widget.onNavigateToNeedsYou,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: secondaryTextColor),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemDiagnosticsCard(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentGreen,
  ) {
    final emerald = AppColors.getSemanticColor("emerald", isDark);
    final isLive = _profile["go_live"] == true;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_outlined, size: 16, color: accentGreen),
              const SizedBox(width: 8),
              Text(
                "SYSTEM TELEMETRY & DIAGNOSTICS",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: secondaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDiagRow("FastAPI Engine", "Port 8000 (Online)", emerald, primaryTextColor, secondaryTextColor),
          const Divider(height: 14),
          _buildDiagRow("Persistence", "SQLite WAL Mode", emerald, primaryTextColor, secondaryTextColor),
          const Divider(height: 14),
          _buildDiagRow("Browser Worker", "Playwright Async Headless", emerald, primaryTextColor, secondaryTextColor),
          const Divider(height: 14),
          _buildDiagRow("AI Reasoning", "Gemini 1.5 Flash Copilot", AppleMusicTheme.violet, primaryTextColor, secondaryTextColor),
          const Divider(height: 14),
          _buildDiagRow("Safety Shield", isLive ? "Live Mode Active" : "Autonomous Dry-Run Active", isLive ? emerald : AppleMusicTheme.amber, primaryTextColor, secondaryTextColor),
        ],
      ),
    );
  }

  Widget _buildDiagRow(String label, String value, Color badgeColor, Color primaryTextColor, Color secondaryTextColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: secondaryTextColor)),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: badgeColor),
            ),
            const SizedBox(width: 6),
            Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor)),
          ],
        ),
      ],
    );
  }

  Widget _buildExecutionLogStream(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color emerald,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Execution Log",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
              Text(
                "Audit Trail",
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text("No execution events logged yet.", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
            )
          else
            ...List.generate(_logs.length, (idx) {
              final log = _logs[idx];
              final msg = (log["message"] ?? "").toString();
              final level = (log["level"] ?? "info").toString();
              final isErr = level == "error" || level == "critical";
              final isWarn = level == "warning";
              final company = (log["company"] ?? "").toString();
              final role = (log["role"] ?? "").toString();
              final timestamp = (log["timestamp"] ?? "").toString();
              final isExpanded = _expandedLogIndices.contains(idx);

              final Color dotColor = isErr
                  ? (isDark ? const Color(0xFFE5736B) : const Color(0xFFC0392B))
                  : (isWarn
                      ? (isDark ? const Color(0xFFE6B450) : const Color(0xFF996500))
                      : (isDark ? const Color(0xFF8A908A) : const Color(0xFF6E736E)));

              String timeDisplay = "";
              if (timestamp.isNotEmpty) {
                try {
                  timeDisplay = timestamp.contains("T")
                      ? timestamp.split("T")[1].substring(0, 5)
                      : (timestamp.length >= 5 ? timestamp.substring(0, 5) : timestamp);
                } catch (_) {}
              }

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedLogIndices.remove(idx);
                    } else {
                      _expandedLogIndices.add(idx);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (company.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  "$company ${role.isNotEmpty ? '• $role' : ''}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: primaryTextColor,
                                  ),
                                ),
                              ),
                            Text(
                              msg,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                                color: isErr ? dotColor : primaryTextColor,
                              ),
                              maxLines: null, // Full text, zero truncation
                            ),
                          ],
                        ),
                      ),
                      if (timeDisplay.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeDisplay,
                          style: TextStyle(
                            fontSize: 11,
                            color: secondaryTextColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildWidgetByKey(String key, bool isDark, bool isPaused) {
    switch (key) {
      case WidgetConfig.goal:
        return ApplicationGoalWidget(
          goalData: _analytics["goal"] ?? {},
          statsData: _stats,
          isCompact: _prefs.isCompact,
          onAdjustTarget: widget.onNavigateToControlCenter,
        );
      case WidgetConfig.interview:
        return InterviewCountdownWidget(
          interviewData: _analytics["upcoming_interview"],
          isCompact: _prefs.isCompact,
          onOpenPrep: _openInterviewPrepModal,
        );
      case WidgetConfig.match:
        return JobMatchWidget(
          matches: _analytics["top_matches"] ?? [],
          isCompact: _prefs.isCompact,
          onReviewMatch: (id) => widget.onNavigateToDiscover(),
          onQuickApply: (id) => _triggerApplyNext(),
        );
      case WidgetConfig.attention:
        return NeedsAttentionWidget(
          attentionData: _analytics["needs_attention"] ?? {},
          isCompact: _prefs.isCompact,
          onResolveInbox: widget.onNavigateToNeedsYou,
          onReviewApprovals: widget.onNavigateToTracker,
        );
      case WidgetConfig.streak:
        return CareerStreakWidget(
          streakData: _analytics["streak"] ?? {},
          isCompact: _prefs.isCompact,
        );
      case WidgetConfig.health:
        return BackendHealthWidget(
          healthData: _health,
          isCompact: _prefs.isCompact,
          onPingTest: () => _fetchDashboardData(),
        );
      case WidgetConfig.funnel:
        return ApplicationFunnelWidget(
          funnelData: _analytics["funnel"] ?? [],
          isCompact: _prefs.isCompact,
        );
      case WidgetConfig.quickActions:
        return QuickActionsWidget(
          isCompact: _prefs.isCompact,
          onFindJobs: widget.onNavigateToDiscover,
          onTailorResume: () => widget.onNavigateToDiscover(),
          onReviewQueue: widget.onNavigateToTracker,
          onUpdateAnswerBank: widget.onNavigateToSettings,
          onToggleAutomation: _togglePause,
          isPaused: isPaused,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDateFilterChip(String label, bool isSelected) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald = AppColors.getSemanticColor("emerald", isDark);

    return InkWell(
      onTap: () => setState(() => _dateFilter = label),
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? emerald : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: isSelected ? emerald : Colors.grey.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
          ),
        ),
      ),
    );
  }

  Widget _buildAutomationStatusBanner(bool isDark) {
    final state = (_stats["automation_state"] ?? (_profile["is_paused"] == true ? "paused_by_user" : "running")).toString();
    final isPaused = state.startsWith("paused") || (_profile["is_paused"] == true);
    final pauseReason = _stats["pause_reason"] ?? _profile["pause_reason"] ?? "Automation paused";
    final pauseDetails = _stats["pause_details"] ?? _profile["pause_details"] ?? "";
    final pausedAt = _stats["paused_at"] ?? _profile["paused_at"] ?? "";
    final recovery = _stats["recovery_instruction"] ?? "Resume automation to process queued applications.";
    final queueCount = _stats["queue_count"] ?? 0;

    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final coral = AppColors.getSemanticColor("coral", isDark);
    final amber = AppColors.getSemanticColor("amber", isDark);

    if (!isPaused) {
      return Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppleMusicTheme.surface : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppleMusicTheme.radiusCard),
          border: Border.all(color: isDark ? AppleMusicTheme.hairline : AppColors.borderHairlineLight),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppleMusicTheme.emerald,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                "Automation Active · $queueCount queued applications",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppleMusicTheme.textPrimary : AppColors.textPrimaryLight,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: _pauseAutomationFlow,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppleMusicTheme.coral,
                side: BorderSide(color: AppleMusicTheme.coral.withOpacity(0.5), width: 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppleMusicTheme.radiusControl)),
              ),
              child: const Text("Pause", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    final isCap = state == "paused_by_daily_cap";
    final isBreaker = state == "paused_by_circuit_breaker";
    final stateBadgeColor = isCap ? AppleMusicTheme.amber : (isBreaker ? AppleMusicTheme.coral : AppleMusicTheme.amber);
    final stateTitle = isCap
        ? "PAUSED BY DAILY CAP"
        : (isBreaker ? "PAUSED BY CIRCUIT BREAKER" : (state == "paused_by_captcha" ? "PAUSED BY CAPTCHA" : "AUTOMATION PAUSED"));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppleMusicTheme.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppleMusicTheme.radiusCard),
        border: Border.all(color: stateBadgeColor.withOpacity(0.6), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.pause_circle_outline, size: 16, color: stateBadgeColor),
                  const SizedBox(width: 6),
                  Text(
                    stateTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: stateBadgeColor,
                    ),
                  ),
                ],
              ),
              if (pausedAt.toString().isNotEmpty)
                Text(
                  pausedAt.toString().contains("T") ? "at ${pausedAt.toString().split('T')[1].substring(0, 5)} IST" : "",
                  style: TextStyle(fontSize: 10, color: isDark ? AppleMusicTheme.textTertiary : AppColors.textMutedLight),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pauseReason.toString().replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? AppleMusicTheme.textPrimary : AppColors.textPrimaryLight,
            ),
          ),
          if (pauseDetails.toString().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              pauseDetails.toString(),
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppleMusicTheme.textSecondary : AppColors.textSecondaryLight,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$queueCount jobs pending in queue",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppleMusicTheme.textSecondary : AppColors.textSecondaryLight,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _resumeAutomationFlow,
                icon: const Icon(Icons.play_arrow, size: 15),
                label: const Text("Resume Automation", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppleMusicTheme.emerald,
                  foregroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppleMusicTheme.radiusControl)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineRecoveryView(
    BuildContext context,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentGreen,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.s16),
              decoration: BoxDecoration(
                color: AppColors.errorCoral.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.errorCoral.withOpacity(0.3)),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.errorCoral),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              "Backend Host Offline",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              "Could not synchronize with ApplyPilot Windows backend at ${_api.baseUrl}.\nEnsure Tailscale is connected on both your PC and phone.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onNavigateToSettings,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text("Settings"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryTextColor,
                    side: BorderSide(color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                ElevatedButton.icon(
                  onPressed: () => _fetchDashboardData(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text("Retry Connection"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGreen,
                    foregroundColor: AppColors.pureWhite,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // GOOGLE STITCH WARM EDITORIAL COCKPIT WIDGETS
  // =========================================================================

  Widget _buildStitchGreetingHeader(bool isDark) {
    final now = DateTime.now();
    final dateStr = DateFormat("EEEE, MMMM d").format(now).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: Color(0xFF8E8E93),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF18181A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF2C2C2E)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF30D158),
                      boxShadow: [
                        BoxShadow(color: Color(0x6630D158), blurRadius: 4, spreadRadius: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "V4.2 Autonomous Active",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(fontFamily: 'Georgia', fontSize: 34, color: Colors.white, height: 1.1),
                children: [
                  TextSpan(text: "Hello, ", style: TextStyle(fontWeight: FontWeight.w400)),
                  TextSpan(
                    text: "Alex",
                    style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w300),
                  ),
                ],
              ),
            ),
            const Text(
              "Auto-Pilot: On",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStitchQuotaAndKPIs(bool isDark) {
    final int appliedToday = (_stats["daily_applied"] as num? ?? 42).toInt();
    final int dailyCap = (_stats["daily_cap"] as num? ?? 100).toInt();
    final double pacing = dailyCap > 0 ? (appliedToday / dailyCap) * 100 : 42.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Donut Quota Card (Flex 7)
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2C2C2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Daily Quota",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF8E8E93)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0x1F30D158),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        "+8 vs yest",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF30D158)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    width: 110,
                    height: 110,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(110, 110),
                          painter: _StitchDonutPainter(
                            progress: pacing / 100.0,
                            trackColor: const Color(0xFF242426),
                            startColor: const Color(0xFFF59E0B),
                            endColor: const Color(0xFFEA580C),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "$appliedToday",
                              style: const TextStyle(
                                fontFamily: 'Georgia',
                                fontSize: 32,
                                fontWeight: FontWeight.w400,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "of $dailyCap max",
                              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontWeight: FontWeight.w300),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Rate Cap", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                    Text(
                      "${pacing.toInt()}% pacing",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Stacked 3 KPIs (Flex 5)
        Expanded(
          flex: 5,
          child: Column(
            children: [
              // 1. Applied
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C2C2E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Applied", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500)),
                        Icon(Icons.send_rounded, size: 14, color: Color(0xFF8E8E93)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "$appliedToday",
                          style: const TextStyle(fontFamily: 'Georgia', fontSize: 22, color: Colors.white, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(width: 4),
                        const Text("today", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 2. Needs You
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C2C2E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Needs You", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500)),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFF59E0B),
                            boxShadow: [BoxShadow(color: Color(0x66F59E0B), blurRadius: 4)],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${_needsYouItems.isNotEmpty ? _needsYouItems.length : 3}",
                          style: const TextStyle(fontFamily: 'Georgia', fontSize: 22, color: Color(0xFFF59E0B), fontWeight: FontWeight.w400),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x24F59E0B),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text("Action", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 3. Leads
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C2C2E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Leads", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93), fontWeight: FontWeight.w500)),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF30D158)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "1",
                          style: TextStyle(fontFamily: 'Georgia', fontSize: 22, color: Color(0xFF30D158), fontWeight: FontWeight.w400),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x1F30D158),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text("Invite", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF30D158))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStitchWeeklyVelocity(bool isDark) {
    final bars = [
      {"day": "M", "val": 28, "pct": 0.48, "peak": false},
      {"day": "T", "val": 46, "pct": 0.74, "peak": false},
      {"day": "W", "val": 35, "pct": 0.56, "peak": false},
      {"day": "T", "val": 58, "pct": 0.92, "peak": true},
      {"day": "F", "val": 31, "pct": 0.50, "peak": false},
      {"day": "S", "val": 12, "pct": 0.22, "peak": false},
      {"day": "S", "val": 8,  "pct": 0.15, "peak": false},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Weekly Velocity",
                    style: TextStyle(fontFamily: 'Georgia', fontSize: 20, color: Colors.white, fontWeight: FontWeight.w400),
                  ),
                  SizedBox(height: 2),
                  Text("218 total · Target 50/day", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF242426),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF38383A)),
                ),
                child: const Text(
                  "7D Avg: 36.3",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 125,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: bars.map((b) {
                final isPeak = b["peak"] as bool;
                final pct = b["pct"] as double;
                final val = b["val"] as int;
                final day = b["day"] as String;

                return Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isPeak)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text("Peak", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        Text(
                          "$val${isPeak ? '*' : ''}",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isPeak ? FontWeight.w700 : FontWeight.w400,
                            color: isPeak ? const Color(0xFFF59E0B) : const Color(0xFF8E8E93),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 24,
                          height: 50 * pct,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            gradient: isPeak
                                ? const LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Color(0xFFEA580C), Color(0xFFF59E0B)],
                                  )
                                : null,
                            color: isPeak ? null : const Color(0xFF242426),
                            boxShadow: isPeak
                                ? [const BoxShadow(color: Color(0x55F59E0B), blurRadius: 8, spreadRadius: 1)]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          day,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isPeak ? FontWeight.w700 : FontWeight.w500,
                            color: isPeak ? const Color(0xFFF59E0B) : const Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStitchConversionFunnel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Conversion Funnel",
                    style: TextStyle(fontFamily: 'Georgia', fontSize: 20, color: Colors.white, fontWeight: FontWeight.w400),
                  ),
                  SizedBox(height: 2),
                  Text("Overall Conversion Rate: 6.02%", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x1F30D158),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text("Optimal", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF30D158))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Segmented Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(flex: 32, child: Container(color: const Color(0xFFF59E0B))),
                  const SizedBox(width: 1.5),
                  Expanded(flex: 25, child: Container(color: const Color(0xFFEA580C))),
                  const SizedBox(width: 1.5),
                  Expanded(flex: 18, child: Container(color: const Color(0xFFFB923C))),
                  const SizedBox(width: 1.5),
                  Expanded(flex: 17, child: Container(color: const Color(0xFF10B981))),
                  const SizedBox(width: 1.5),
                  Expanded(flex: 8, child: Container(color: const Color(0xFFD4AF37))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 2x2 Breakdown Grid
          Row(
            children: [
              Expanded(
                child: _buildFunnelTile("Discovered", "83", "100%", const Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFunnelTile("Tailored", "55", "66%", const Color(0xFFEA580C)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildFunnelTile("Pre-Filled", "37", "44%", const Color(0xFFFB923C)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFunnelTile("Submitted", "24", "29%", const Color(0xFF10B981)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Milestone Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x22D4AF37),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x44D4AF37)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFD4AF37),
                        boxShadow: [BoxShadow(color: Color(0x99D4AF37), blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Direct Recruiter Leads & Calls",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFBBF24)),
                    ),
                  ],
                ),
                const Text(
                  "5 roles (6.0%)",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunnelTile(String title, String count, String pct, Color dotColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF242426).withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
            ],
          ),
          Row(
            children: [
              Text(count, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(width: 3),
              Text("($pct)", style: const TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStitchDispatchFrequency(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Dispatch Frequency",
                    style: TextStyle(fontFamily: 'Georgia', fontSize: 20, color: Colors.white, fontWeight: FontWeight.w400),
                  ),
                  SizedBox(height: 2),
                  Text("Optimal Activity Window · Peak at 14:00", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x24F59E0B),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text("Active", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 70,
            width: double.infinity,
            child: CustomPaint(
              painter: _StitchWavePainter(),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("00:00", style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
              Text("06:00", style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
              Text("12:00", style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
              Text("18:00 (Now)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B))),
              Text("23:59", style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStitchNowApplying(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF30D158),
                      boxShadow: [BoxShadow(color: Color(0x6630D158), blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "NOW APPLYING LIVE",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
              const Text("Orchestrator #3", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Stripe", style: TextStyle(fontFamily: 'Georgia', fontSize: 22, color: Colors.white, fontWeight: FontWeight.w400)),
                  SizedBox(height: 2),
                  Text("Staff Product Designer · Remote", style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
                ],
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF242426),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF38383A)),
                ),
                alignment: Alignment.center,
                child: const Text("S", style: TextStyle(fontFamily: 'Georgia', fontSize: 20, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Step 3 of 4: Custom Questions & Pre-Fill", style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
              Text("68%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  Expanded(
                    flex: 68,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFF30D158)]),
                      ),
                    ),
                  ),
                  Expanded(flex: 32, child: Container(color: const Color(0xFF242426))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("✓ Grounded Resume", style: TextStyle(fontSize: 10, color: Colors.white)),
              Text("✓ Cover Letter", style: TextStyle(fontSize: 10, color: Colors.white)),
              Text("Filling Form...", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF30D158))),
              Text("Submission", style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStitchRecentActivity(bool isDark) {
    final activities = [
      {"action": "Applied to Zoho", "sub": "Senior Data Analyst · Workday Portal", "time": "2m ago", "color": const Color(0xFF30D158)},
      {"action": "Tailored Cover Letter", "sub": "Figma · Design Systems Lead", "time": "14m ago", "color": const Color(0xFFF59E0B)},
      {"action": "Action Needed: 2FA Code", "sub": "Notion · Security prompt requested", "time": "38m ago", "color": const Color(0xFFEA580C)},
      {"action": "Applied to Linear", "sub": "Founding Product Designer · Ashby", "time": "1h ago", "color": const Color(0xFF30D158)},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Recent Activity",
                style: TextStyle(fontFamily: 'Georgia', fontSize: 20, color: Colors.white, fontWeight: FontWeight.w400),
              ),
              GestureDetector(
                onTap: () => widget.onNavigateToTracker(),
                child: const Text(
                  "See All",
                  style: TextStyle(fontFamily: 'Georgia', fontStyle: FontStyle.italic, fontSize: 14, color: Color(0xFFF59E0B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: activities.map((a) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: a["color"] as Color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a["action"] as String,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            a["sub"] as String,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      a["time"] as String,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

}

class _StitchDonutPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color startColor;
  final Color endColor;

  _StitchDonutPainter({
    required this.progress,
    required this.trackColor,
    required this.startColor,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Active arc with gradient
    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: -1.5708, // -90 deg
        endAngle: 4.71239,   // 270 deg
        colors: [startColor, endColor],
      );

      final arcPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.0
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -1.5708, // start at top (-90 deg)
        progress * 2 * 3.1415926535,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StitchDonutPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _StitchWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.85);
    path.quadraticBezierTo(size.width * 0.15, size.height * 0.75, size.width * 0.35, size.height * 0.55);
    path.quadraticBezierTo(size.width * 0.55, size.height * 0.15, size.width * 0.75, size.height * 0.45);
    path.quadraticBezierTo(size.width * 0.88, size.height * 0.65, size.width, size.height * 0.75);

    // Fill path
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFF59E0B).withOpacity(0.4),
        const Color(0xFFEA580C).withOpacity(0.0),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Peak dot at (width * 0.55, height * 0.15)
    final peakOffset = Offset(size.width * 0.55, size.height * 0.15);
    final dotBg = Paint()..color = const Color(0xFF18181A);
    final dotBorder = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(peakOffset, 4.5, dotBg);
    canvas.drawCircle(peakOffset, 4.5, dotBorder);

    // Green dot near 18:00
    final greenDot = Paint()..color = const Color(0xFF30D158);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.5), 3.5, greenDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

