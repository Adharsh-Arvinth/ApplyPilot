import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../widgets/smart_widgets.dart';

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

      final results = await Future.wait([
        healthFuture,
        statsFuture,
        analyticsFuture,
        profileFuture,
        logsFuture,
      ]);

      if (mounted) {
        setState(() {
          _health = results[0] as Map<String, dynamic>;
          _stats = results[1] as Map<String, dynamic>;
          _analytics = results[2] as Map<String, dynamic>;
          _profile = results[3] as Map<String, dynamic>;
          _logs = (results[4] as List<dynamic>).take(8).toList();
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
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
              decoration: BoxDecoration(
                color: accentGreen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadii.badge),
                border: Border.all(color: accentGreen.withOpacity(0.3), width: 0.8),
              ),
              child: Text(
                "APPLYPILOT",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: accentGreen,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              "Command Center",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: primaryTextColor,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined, size: 22),
            tooltip: "Customize Widgets",
            onPressed: _openCustomizer,
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, size: 22),
            tooltip: "Analytics",
            onPressed: widget.onNavigateToAnalytics,
          ),
          IconButton(
            icon: const Icon(Icons.tune_outlined, size: 22),
            tooltip: "Control Center",
            onPressed: widget.onNavigateToControlCenter,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: "Settings",
            onPressed: widget.onNavigateToSettings,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen),
            )
          : RefreshIndicator(
              onRefresh: () => _fetchDashboardData(),
              color: accentGreen,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.s16),
                children: [
                  // 1. Top Status & Personalization Header
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
                          const SizedBox(width: 6),
                          Text(
                            isOnline ? "Tailscale Connected" : "Host Offline",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildDateFilterChip("Today", _dateFilter == "Today"),
                          const SizedBox(width: 4),
                          _buildDateFilterChip("Week", _dateFilter == "Week"),
                          const SizedBox(width: 4),
                          _buildDateFilterChip("All", _dateFilter == "All"),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.s12),

                  // 2. Render Ordered Smart Widgets
                  ...finalWidgetOrder.map((key) {
                    final isPinned = _prefs.pinned.contains(key);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                      child: Stack(
                        children: [
                          _buildWidgetByKey(key, isDark, isPaused),
                          if (isPinned)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Icon(Icons.push_pin, size: 12, color: emerald.withOpacity(0.6)),
                            ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: AppSpacing.s16),

                  // 3. Live Execution Stream & Logs
                  Container(
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "LIVE OPERATION STREAM",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
                            ),
                            Text(
                              "Updated just now",
                              style: TextStyle(fontSize: 10, color: secondaryTextColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s10),
                        if (_logs.isEmpty)
                          Text("No execution events logged yet.", style: TextStyle(fontSize: 11, color: secondaryTextColor))
                        else
                          ..._logs.map((log) {
                            final msg = log["message"] ?? "";
                            final level = log["level"] ?? "info";
                            final isErr = level == "error" || level == "critical";
                            final color = isErr ? AppColors.getSemanticColor("coral", isDark) : secondaryTextColor;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.s6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("›", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      msg,
                                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isErr ? color : primaryTextColor),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            ),
    );
  }

  Widget _buildWidgetByKey(String key, bool isDark, bool isPaused) {
    switch (key) {
      case WidgetConfig.goal:
        return ApplicationGoalWidget(
          goalData: _analytics["goal"] ?? {},
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
}
