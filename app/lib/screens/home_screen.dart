import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToNeedsYou;
  final VoidCallback onNavigateToJobs;
  final VoidCallback onNavigateToSettings;

  const HomeScreen({
    super.key,
    required this.onNavigateToNeedsYou,
    required this.onNavigateToJobs,
    required this.onNavigateToSettings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient();
  Timer? _pollingTimer;

  bool _loading = true;
  bool _serverOnline = false;
  String _hostStatus = "Connecting...";

  int _applied = 0;
  int _cap = 100;
  int _needsYou = 0;
  int _maybe = 0;
  int _blocked = 0;
  int _queue = 0;
  int _interviews = 0;
  int _total = 0;

  bool _isPaused = false;
  bool _goLive = false;
  List<dynamic> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
    // 2-second real-time polling loop
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchData());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final health = await _api.checkHealth();
    final isOnline = health["status"] == "online";

    if (!isOnline) {
      if (mounted) {
        setState(() {
          _serverOnline = false;
          _hostStatus = "Host Offline";
          _loading = false;
        });
      }
      return;
    }

    try {
      final stats = await _api.getStats();
      final logs = await _api.getRunLogs();

      if (mounted) {
        setState(() {
          _serverOnline = true;
          _hostStatus = "PC Online (Tailscale)";
          _applied = stats["daily_applied"] ?? 0;
          _cap = stats["daily_cap"] ?? 100;
          _needsYou = stats["needs_you_count"] ?? 0;
          _maybe = stats["maybe_count"] ?? 0;
          _blocked = stats["blocked_count"] ?? 0;
          _queue = stats["queue_count"] ?? 0;
          _interviews = stats["interview_count"] ?? 0;
          _total = stats["total_tracked"] ?? 0;

          _isPaused = health["queue_paused"] ?? false;
          _goLive = health["go_live"] ?? false;
          _recentLogs = logs.take(8).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePause() async {
    final res = await _api.togglePause();
    setState(() => _isPaused = res["is_paused"] ?? false);
  }

  Future<void> _toggleGoLive() async {
    final res = await _api.toggleGoLive();
    setState(() => _goLive = res["go_live"] ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _serverOnline ? AppColors.successDark : AppColors.blockedDark,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text("ApplyPilot", style: theme.textTheme.titleLarge),
            const SizedBox(width: AppSpacing.s8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.appleMusicRose.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: const Text(
                "LIVE 2s",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.appleMusicRose,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Toggle Theme",
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
            onPressed: () => toggleThemeMode(),
          ),
          IconButton(
            tooltip: "Settings",
            icon: const Icon(Icons.settings_outlined),
            onPressed: widget.onNavigateToSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.appleMusicRose))
          : RefreshIndicator(
              color: AppColors.appleMusicRose,
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s16),
                children: [
                  // 1. Apple Music Hero Progress Ring & Status
                  _buildHeroCockpitCard(theme, isDark),
                  const SizedBox(height: AppSpacing.s20),

                  // 2. Safety Controls (Pause / Go-Live)
                  _buildSafetyControls(theme, isDark),
                  const SizedBox(height: AppSpacing.s24),

                  // 3. Category Breakdown Cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Categories & Status", style: theme.textTheme.titleLarge),
                      Text("Total: $_total jobs", style: theme.textTheme.bodyMedium),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  _buildCategoryGrid(theme, isDark),
                  const SizedBox(height: AppSpacing.s24),

                  // 4. Live Activity Stream
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Live Engine Stream", style: theme.textTheme.titleLarge),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          "Auto-updating",
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  _buildLiveLogs(theme, isDark),
                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroCockpitCard(ThemeData theme, bool isDark) {
    final progress = _cap > 0 ? (_applied / _cap).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // Circular Progress Indicator
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 8,
                  backgroundColor: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                  color: AppColors.appleMusicRose,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Text(
                    "${(progress * 100).toInt()}%",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s20),
          // Progress Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("TODAY'S SUBMISSIONS", style: theme.textTheme.labelSmall),
                const SizedBox(height: AppSpacing.s4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      "$_applied",
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: AppColors.appleMusicRose,
                      ),
                    ),
                    Text(
                      " / $_cap cap",
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Row(
                  children: [
                    Icon(
                      _serverOnline ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
                      size: 14,
                      color: _serverOnline ? AppColors.successDark : AppColors.blockedDark,
                    ),
                    const SizedBox(width: 4),
                    Text(_hostStatus, style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyControls(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isPaused ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    color: _isPaused ? AppColors.warningDark : AppColors.appleMusicRose,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Auto-Apply Queue", style: theme.textTheme.titleMedium),
                      Text(
                        _isPaused ? "Paused by safety switch" : "Active & monitoring jobs",
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: !_isPaused,
                activeColor: AppColors.appleMusicRose,
                onChanged: (_) => _togglePause(),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _goLive ? Icons.send_rounded : Icons.visibility_rounded,
                    color: _goLive ? AppColors.successDark : AppColors.blueDark,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _goLive ? "LIVE SUBMISSION ON" : "DRY-RUN PREVIEW MODE",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _goLive ? AppColors.successDark : AppColors.blueDark,
                        ),
                      ),
                      Text(
                        _goLive ? "Submitting applications to ATS" : "Screenshots & verifies before submit",
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _goLive,
                activeColor: AppColors.successDark,
                onChanged: (_) => _toggleGoLive(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(ThemeData theme, bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildCategoryCard(
                theme: theme,
                isDark: isDark,
                title: "Applied",
                count: _applied,
                subtitle: "View Proofs & Screenshots",
                icon: Icons.verified_rounded,
                color: AppColors.successDark,
                onTap: widget.onNavigateToJobs,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _buildCategoryCard(
                theme: theme,
                isDark: isDark,
                title: "Needs You",
                count: _needsYou,
                subtitle: _needsYou > 0 ? "Action Required" : "All answered",
                icon: Icons.mark_chat_unread_rounded,
                color: _needsYou > 0 ? AppColors.appleMusicRose : AppColors.textMutedDark,
                onTap: widget.onNavigateToNeedsYou,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: _buildCategoryCard(
                theme: theme,
                isDark: isDark,
                title: "In Queue",
                count: _queue,
                subtitle: "Score >= 4.0",
                icon: Icons.hourglass_top_rounded,
                color: AppColors.blueDark,
                onTap: widget.onNavigateToJobs,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _buildCategoryCard(
                theme: theme,
                isDark: isDark,
                title: "Maybe",
                count: _maybe,
                subtitle: "Swipe Review",
                icon: Icons.swipe_rounded,
                color: AppColors.purpleDark,
                onTap: widget.onNavigateToJobs,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: _buildCategoryCard(
                theme: theme,
                isDark: isDark,
                title: "Blocked",
                count: _blocked,
                subtitle: "Below 7 LPA / Senior",
                icon: Icons.block_rounded,
                color: AppColors.blockedDark,
                onTap: widget.onNavigateToJobs,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _buildCategoryCard(
                theme: theme,
                isDark: isDark,
                title: "Interviews",
                count: _interviews,
                subtitle: "Scheduled",
                icon: Icons.emoji_events_rounded,
                color: AppColors.warningDark,
                onTap: widget.onNavigateToJobs,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required ThemeData theme,
    required bool isDark,
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: color),
                Text(
                  "$count",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s4),
            Text(subtitle, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveLogs(ThemeData theme, bool isDark) {
    if (_recentLogs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Center(
          child: Text("No engine events recorded yet.", style: theme.textTheme.bodyMedium),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
          width: 0.8,
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _recentLogs.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
        ),
        itemBuilder: (_, idx) {
          final log = _recentLogs[idx];
          return ListTile(
            dense: true,
            leading: Icon(
              Icons.radio_button_checked,
              size: 12,
              color: AppColors.appleMusicRose,
            ),
            title: Text(log["message"] ?? "", style: theme.textTheme.bodyMedium),
            trailing: Text(log["created_at"] ?? "", style: theme.textTheme.labelSmall),
          );
        },
      ),
    );
  }
}
