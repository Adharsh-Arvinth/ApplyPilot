import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
      if (mounted) _fetchDashboardData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
          _error = null;
          _loading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final brassColor = isDark ? AppColors.brassDark : AppColors.mutedBrass;

    final isOnline = _health["status"] == "online" || _health["status"] == "healthy";
    final isPaused = _profile["is_paused"] ?? false;
    final isLive = _profile["go_live"] ?? false;

    final dailyApplied = _stats["daily_applied"] ?? 0;
    final dailyCap = _stats["daily_cap"] ?? 100;
    final pendingNeedsYou = _stats["needs_you_count"] ?? 0;
    final queuedCount = _stats["queue_count"] ?? 0;
    final interviewCount = _stats["interview_count"] ?? 0;
    final totalTracked = _stats["total_tracked"] ?? 0;

    final weeklyTrend = (_analytics["weekly_trend"] as List<dynamic>?) ?? [];

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
                  // 1. Host Connection & Operational Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline ? AppColors.successLight : AppColors.errorLight,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            isOnline
                                ? "Host Operational • Windows Tailscale Engine (v${_health['version'] ?? '1.2.0'})"
                                : "Host Disconnected • Tailscale Link Offline",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                          decoration: BoxDecoration(
                            color: (isLive ? AppColors.warningLight : accentGreen).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(
                            isLive ? "LIVE SUBMISSIONS" : "DRY-RUN SAFE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isLive ? AppColors.warningLight : accentGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s16),

                  // 2. Daily Application Target & Action Card
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s20),
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "TODAY'S TARGET",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                    color: secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      "$dailyApplied",
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                    Text(
                                      " / $dailyCap applications",
                                      style: TextStyle(fontSize: 14, color: secondaryTextColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Quick Action: Apply Next in Queue
                            ElevatedButton.icon(
                              onPressed: isPaused || queuedCount == 0 ? null : _triggerApplyNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentGreen,
                                foregroundColor: AppColors.pureWhite,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
                              ),
                              icon: const Icon(Icons.bolt, size: 18),
                              label: const Text("Apply Next", style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        // Linear Progress Meter
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          child: LinearProgressIndicator(
                            value: dailyCap > 0 ? (dailyApplied / dailyCap).clamp(0.0, 1.0) : 0.0,
                            minHeight: 8,
                            backgroundColor: borderColor,
                            valueColor: AlwaysStoppedAnimation<Color>(accentGreen),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isPaused ? "Engine paused by user" : "$queuedCount jobs ready in approved queue",
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                            ),
                            GestureDetector(
                              onTap: _togglePause,
                              child: Text(
                                isPaused ? "Resume Engine" : "Pause Queue",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isPaused ? AppColors.successLight : AppColors.errorLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s16),

                  // 3. Command Metrics Grid
                  Row(
                    children: [
                      // Pending Approvals / Needs You
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onNavigateToNeedsYou,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            decoration: BoxDecoration(
                              color: pendingNeedsYou > 0 ? brassColor.withOpacity(0.08) : cardBg,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(
                                color: pendingNeedsYou > 0 ? brassColor.withOpacity(0.5) : borderColor,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(Icons.help_outline, size: 20, color: brassColor),
                                    if (pendingNeedsYou > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: brassColor,
                                          borderRadius: BorderRadius.circular(AppRadii.badge),
                                        ),
                                        child: Text(
                                          "Action Required",
                                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.pureWhite),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.s12),
                                Text(
                                  "$pendingNeedsYou",
                                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: primaryTextColor),
                                ),
                                Text("Needs You Inbox", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      // Interviews
                      Expanded(
                        child: GestureDetector(
                          onTap: widget.onNavigateToTracker,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.event_available_outlined, size: 20, color: accentGreen),
                                const SizedBox(height: AppSpacing.s12),
                                Text(
                                  "$interviewCount",
                                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: primaryTextColor),
                                ),
                                Text("Active Interviews", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.s16),

                  // 4. Weekly Application Volume Trend
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s20),
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
                              "WEEKLY APPLICATION VOLUME",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: secondaryTextColor,
                              ),
                            ),
                            TextButton(
                              onPressed: widget.onNavigateToAnalytics,
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                              child: Text("Detailed Insights", style: TextStyle(fontSize: 12, color: accentGreen, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        if (weeklyTrend.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                              child: Text("No application activity recorded this week yet.", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                            ),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: weeklyTrend.map<Widget>((item) {
                              final count = (item["count"] ?? 0) as int;
                              final maxCount = weeklyTrend.map((e) => (e["count"] ?? 0) as int).reduce((a, b) => a > b ? a : b);
                              final heightPct = maxCount > 0 ? (count / maxCount).clamp(0.12, 1.0) : 0.12;
                              return Column(
                                children: [
                                  Text("$count", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: count > 0 ? accentGreen : secondaryTextColor)),
                                  const SizedBox(height: AppSpacing.s4),
                                  Container(
                                    width: 22,
                                    height: 70 * heightPct,
                                    decoration: BoxDecoration(
                                      color: count > 0 ? accentGreen : borderColor,
                                      borderRadius: BorderRadius.circular(AppRadii.badge),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  Text(
                                    item["day"] ?? "",
                                    style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s16),

                  // 5. Recent Autonomous Execution Logs
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
                              "ENGINE ACTIVITY STREAM",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: secondaryTextColor,
                              ),
                            ),
                            Icon(Icons.stream, size: 16, color: secondaryTextColor),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        if (_logs.isEmpty)
                          Text("No logs recorded yet.", style: TextStyle(fontSize: 12, color: secondaryTextColor))
                        else
                          ...(_logs.map<Widget>((log) {
                            final lvl = (log["level"] ?? "info").toString().toLowerCase();
                            final color = lvl == "error"
                                ? AppColors.errorLight
                                : (lvl == "warn" ? AppColors.warningLight : accentGreen);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 5),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                                  ),
                                  const SizedBox(width: AppSpacing.s8),
                                  Expanded(
                                    child: Text(
                                      log["message"] ?? "",
                                      style: TextStyle(fontSize: 12, height: 1.3, color: primaryTextColor),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s8),
                                  Text(
                                    log["created_at"] ?? "",
                                    style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            );
                          })),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s24),
                ],
              ),
            ),
    );
  }
}
