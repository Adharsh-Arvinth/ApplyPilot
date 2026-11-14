import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
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

  Future<void> _resumeAutomationFlow() async {
    HapticFeedback.mediumImpact();
    try {
      final res = await _api.resumeAutomation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.successEmerald,
            content: Text(res["message"] ?? "Automation resumed successfully!"),
          ),
        );
      }
      _fetchDashboardData(silent: true);
    } catch (e) {
      if (mounted) {
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
    try {
      await _api.pauseAutomation(reason: "paused_by_user", details: "Paused manually from dashboard");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Automation paused.")),
        );
      }
      _fetchDashboardData(silent: true);
    } catch (e) {
      if (mounted) {
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
      appBar: AppBar(
        titleSpacing: AppSpacing.s12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
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
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: accentGreen,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: Text(
                "Command Center",
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: primaryTextColor,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: ApplyPilotColors.aiViolet.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: ApplyPilotColors.aiViolet),
            ),
            tooltip: "Gemini Career Advisor",
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_customize_outlined, size: 22),
            tooltip: "Customize Widgets",
            onPressed: _openCustomizer,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 22),
            tooltip: "More Options",
            onSelected: (val) {
              if (val == "analytics") widget.onNavigateToAnalytics();
              if (val == "control") widget.onNavigateToControlCenter();
              if (val == "settings") widget.onNavigateToSettings();
            },
            itemBuilder: (ctx) => [
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

                  // Prominent Authoritative Automation Status Banner
                  _buildAutomationStatusBanner(isDark),

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
                              "Real-time audit log",
                              style: TextStyle(fontSize: 10, color: secondaryTextColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s10),
                        if (_logs.isEmpty)
                          Text("No execution events logged yet.", style: TextStyle(fontSize: 11, color: secondaryTextColor))
                        else
                          ...List.generate(_logs.length, (idx) {
                            final log = _logs[idx];
                            final msg = (log["message"] ?? "").toString();
                            final level = (log["level"] ?? "info").toString();
                            final isErr = level == "error" || level == "critical";
                            final isWarn = level == "warning";
                            final outcome = (log["outcome"] ?? "").toString();
                            final company = (log["company"] ?? "").toString();
                            final role = (log["role"] ?? "").toString();
                            final timestamp = (log["timestamp"] ?? "").toString();
                            final details = (log["details_json"] ?? "").toString();
                            final isExpanded = _expandedLogIndices.contains(idx);

                            final color = isErr
                                ? AppColors.getSemanticColor("coral", isDark)
                                : (isWarn ? AppColors.getSemanticColor("amber", isDark) : emerald);

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
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.s8),
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: isExpanded ? borderColor.withOpacity(0.2) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("›", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      company.isNotEmpty ? "$company · $role" : msg,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        fontFamily: 'monospace',
                                                        color: isErr ? color : primaryTextColor,
                                                      ),
                                                      maxLines: isExpanded ? null : 1,
                                                      overflow: isExpanded ? null : TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (outcome.isNotEmpty)
                                                    Container(
                                                      margin: const EdgeInsets.only(left: 6),
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: color.withOpacity(0.12),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: Text(
                                                        outcome.toUpperCase(),
                                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              if (company.isNotEmpty && msg.isNotEmpty && msg != company)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    msg,
                                                    style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                                    maxLines: isExpanded ? null : 1,
                                                    overflow: isExpanded ? null : TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isExpanded) ...[
                                      const SizedBox(height: 6),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 18),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (timestamp.isNotEmpty)
                                              Text("Time: $timestamp", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                                            if (details.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text("Details: $details", style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: secondaryTextColor)),
                                            ],
                                          ],
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: accentGreen.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentGreen,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                "Automation Running · $queueCount queued applications",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
              ),
            ),
            InkWell(
              onTap: _pauseAutomationFlow,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text("Pause", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: amber)),
              ),
            ),
          ],
        ),
      );
    }

    final isCap = state == "paused_by_daily_cap";
    final isBreaker = state == "paused_by_circuit_breaker";
    final stateBadgeColor = isCap ? amber : (isBreaker ? coral : amber);
    final stateTitle = isCap
        ? "PAUSED BY DAILY CAP"
        : (isBreaker ? "PAUSED BY CIRCUIT BREAKER" : (state == "paused_by_captcha" ? "PAUSED BY CAPTCHA" : "AUTOMATION PAUSED"));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.s12),
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: stateBadgeColor.withOpacity(0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.pause_circle_filled, size: 16, color: stateBadgeColor),
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    stateTitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: stateBadgeColor,
                    ),
                  ),
                ],
              ),
              if (pausedAt.toString().isNotEmpty)
                Text(
                  pausedAt.toString().contains("T") ? "at ${pausedAt.toString().split('T')[1].substring(0, 5)} IST" : "",
                  style: TextStyle(fontSize: 10, color: secondaryTextColor),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            pauseReason.toString().replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
          ),
          if (pauseDetails.toString().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              pauseDetails.toString(),
              style: TextStyle(fontSize: 11, height: 1.35, color: secondaryTextColor),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: secondaryTextColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  recovery.toString(),
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: secondaryTextColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$queueCount jobs pending in queue",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor),
              ),
              ElevatedButton.icon(
                onPressed: _resumeAutomationFlow,
                icon: const Icon(Icons.play_arrow, size: 15),
                label: const Text("Resume Automation", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentGreen,
                  foregroundColor: AppColors.pureWhite,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
