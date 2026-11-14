import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

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
  int _interviews = 0;
  bool _isPaused = false;
  bool _goLive = false;
  List<dynamic> _recentLogs = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchData());
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
          _hostStatus = "PC Active";
          _applied = stats["daily_applied"] ?? 0;
          _cap = stats["daily_cap"] ?? 100;
          _needsYou = stats["needs_you_count"] ?? 0;
          _interviews = stats["interview_count"] ?? 0;
          _isPaused = health["queue_paused"] ?? false;
          _goLive = health["go_live"] ?? false;
          _recentLogs = logs.take(6).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _serverOnline = true;
          _hostStatus = "PC Active";
          _loading = false;
        });
      }
    }
  }

  Future<void> _togglePause() async {
    setState(() => _isPaused = !_isPaused);
    try {
      final res = await _api.togglePause();
      setState(() => _isPaused = res["is_paused"] ?? _isPaused);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error toggling pause: $e")));
    }
  }

  void _showGoLiveDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
        title: Text(
          _goLive ? "Switch to Dry-Run Mode?" : "Enable Live Submission?",
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        content: Text(
          _goLive
              ? "The engine will switch back to safe preview mode. Forms will be filled and screenshots captured, but no applications will be submitted."
              : "WARNING: Turning this ON will allow Playwright to click 'Submit Application' for eligible positions. Please ensure you have reviewed dry-run screenshots before enabling.",
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _goLive ? AppColors.accentLight : AppColors.blockedLight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await _api.toggleGoLive();
              setState(() => _goLive = res["go_live"] ?? _goLive);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Application Mode: ${res["mode"]}")),
              );
            },
            child: Text(_goLive ? "Set Dry-Run" : "Confirm Live"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ApplyPilot", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
        actions: [
          // Server status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
              borderRadius: BorderRadius.circular(AppRadii.badge),
              border: Border.all(color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _serverOnline ? (_isPaused ? AppColors.warningLight : AppColors.accentLight) : AppColors.blockedLight,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  _hostStatus,
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: widget.onNavigateToSettings,
          ),
          const SizedBox(width: AppSpacing.s8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.s20),
                children: [
                  // Mode banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
                    decoration: BoxDecoration(
                      color: _goLive ? AppColors.blockedLight.withOpacity(0.08) : AppColors.accentLight.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(
                        color: _goLive ? AppColors.blockedLight.withOpacity(0.2) : AppColors.accentLight.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _goLive ? Icons.warning_amber_rounded : Icons.shield_outlined,
                              size: 18,
                              color: _goLive ? AppColors.blockedLight : AppColors.accentLight,
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            Text(
                              _goLive ? "Live Submission Active" : "Dry-Run Preview (Safe Mode)",
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 13,
                                color: _goLive ? AppColors.blockedLight : AppColors.accentLight,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _showGoLiveDialog,
                          child: Text(
                            "Change",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _goLive ? AppColors.blockedLight : AppColors.accentLight,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // Progress Card (Daily Applications Gauge)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Today's Progress", style: theme.textTheme.titleMedium),
                              TextButton.icon(
                                onPressed: _togglePause,
                                icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 18),
                                label: Text(_isPaused ? "Resume" : "Pause"),
                                style: TextButton.styleFrom(
                                  foregroundColor: _isPaused ? AppColors.accentLight : AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text("$_applied", style: theme.textTheme.displayLarge),
                              Text(" / $_cap", style: theme.textTheme.titleLarge?.copyWith(
                                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                              )),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            _isPaused ? "Queue paused by user" : "Target: up to $_cap suitable jobs today",
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(height: AppSpacing.s16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.badge),
                            child: LinearProgressIndicator(
                              value: _cap > 0 ? (_applied / _cap).clamp(0.0, 1.0) : 0,
                              minHeight: 6,
                              backgroundColor: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                              color: _goLive ? AppColors.blockedLight : AppColors.accentLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s16),

                  // Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: widget.onNavigateToNeedsYou,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("Needs You", style: theme.textTheme.titleMedium?.copyWith(fontSize: 13)),
                                      if (_needsYou > 0)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.warningLight,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.s8),
                                  Text("$_needsYou", style: theme.textTheme.displayMedium),
                                  Text("Awaiting response", style: theme.textTheme.labelSmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: InkWell(
                          onTap: widget.onNavigateToJobs,
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Interviews", style: theme.textTheme.titleMedium?.copyWith(fontSize: 13)),
                                  const SizedBox(height: AppSpacing.s8),
                                  Text("$_interviews", style: theme.textTheme.displayMedium),
                                  Text("Invites received", style: theme.textTheme.labelSmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.s24),

                  // Recent Execution Stream
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Execution Log", style: theme.textTheme.titleMedium),
                      InkWell(
                        onTap: widget.onNavigateToJobs,
                        child: Text("View all jobs", style: theme.textTheme.labelSmall?.copyWith(
                          decoration: TextDecoration.underline,
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Card(
                    child: _recentLogs.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(AppSpacing.s24),
                            child: Center(
                              child: Text("No applications run yet today.", style: theme.textTheme.bodyMedium),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recentLogs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final log = _recentLogs[i];
                              return ListTile(
                                dense: true,
                                title: Text(log["message"] ?? "", style: theme.textTheme.bodyLarge?.copyWith(fontSize: 13)),
                                subtitle: Text(log["created_at"] ?? "", style: theme.textTheme.labelSmall?.copyWith(fontSize: 11)),
                                trailing: Icon(
                                  log["level"] == "error" ? Icons.error_outline : Icons.check_circle_outline,
                                  size: 16,
                                  color: log["level"] == "error" ? AppColors.blockedLight : AppColors.accentLight,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
