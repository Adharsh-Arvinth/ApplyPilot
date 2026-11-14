import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class AutomationControlScreen extends StatefulWidget {
  const AutomationControlScreen({super.key});

  @override
  State<AutomationControlScreen> createState() => _AutomationControlScreenState();
}

class _AutomationControlScreenState extends State<AutomationControlScreen> {
  final ApiClient _api = ApiClient();
  Timer? _logTimer;
  bool _loading = true;
  Map<String, dynamic> _profile = {};
  List<dynamic> _logs = [];

  final TextEditingController _dailyCapController = TextEditingController();
  final TextEditingController _hourlyCapController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _logTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadLogs();
    });
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _dailyCapController.dispose();
    _hourlyCapController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final p = await _api.getProfile();
      final l = await _api.getRunLogs();
      if (mounted) {
        setState(() {
          _profile = p;
          _logs = l;
          _dailyCapController.text = (p["daily_cap"] ?? 100).toString();
          _hourlyCapController.text = (p["hourly_cap"] ?? 10).toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLogs() async {
    try {
      final l = await _api.getRunLogs();
      if (mounted) setState(() => _logs = l);
    } catch (_) {}
  }

  Future<void> _togglePause() async {
    HapticFeedback.heavyImpact();
    try {
      final res = await _api.togglePause();
      setState(() => _profile["is_paused"] = res["is_paused"]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res["is_paused"] ? "Application engine PAUSED globally." : "Application engine RESUMED.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _toggleGoLive() async {
    final currentGoLive = _profile["go_live"] ?? false;
    if (!currentGoLive) {
      // Require explicit safety confirmation modal
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warningLight),
              SizedBox(width: 8),
              Text("Enable Live Submissions?"),
            ],
          ),
          content: const Text(
            "Live submissions will submit real applications to employer ATS portals on your behalf. "
            "Leave in Dry-Run mode to review form fills and proof screenshots first.\n\n"
            "Are you sure you want to go live?",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Keep in Dry-Run")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warningLight),
              child: const Text("Confirm Live Submissions", style: TextStyle(color: AppColors.pureWhite, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    HapticFeedback.heavyImpact();
    try {
      final res = await _api.toggleGoLive();
      setState(() => _profile["go_live"] = res["go_live"]);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Mode switched: ${res['mode']}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _saveLimits() async {
    HapticFeedback.mediumImpact();
    final daily = int.tryParse(_dailyCapController.text.trim()) ?? 100;
    final hourly = int.tryParse(_hourlyCapController.text.trim()) ?? 10;
    try {
      await _api.updateProfile({"daily_cap": daily, "hourly_cap": hourly});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Application limits updated.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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

    final isPaused = _profile["is_paused"] ?? false;
    final isLive = _profile["go_live"] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Automation Control",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              children: [
                // 1. Emergency Global Stop / Pause Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  decoration: BoxDecoration(
                    color: isPaused ? AppColors.errorLight.withOpacity(0.08) : cardBg,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: isPaused ? AppColors.errorLight : borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        decoration: BoxDecoration(
                          color: (isPaused ? AppColors.errorLight : accentGreen).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(isPaused ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 28, color: isPaused ? AppColors.errorLight : accentGreen),
                      ),
                      const SizedBox(width: AppSpacing.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPaused ? "Engine Paused" : "Engine Active",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            Text(
                              isPaused ? "All queue processing halted" : "Draining approved applications",
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _togglePause,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPaused ? AppColors.successLight : AppColors.errorLight,
                          foregroundColor: AppColors.pureWhite,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                        ),
                        child: Text(isPaused ? "Resume" : "Emergency Pause", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s16),

                // 2. Strict Dry-Run vs Live Gate Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  decoration: BoxDecoration(
                    color: isLive ? AppColors.warningLight.withOpacity(0.08) : cardBg,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: isLive ? AppColors.warningLight : borderColor),
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
                                isLive ? "LIVE SUBMISSION MODE" : "DRY-RUN SAFE MODE (DEFAULT)",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isLive ? AppColors.warningLight : accentGreen,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isLive
                                    ? "Applications are submitted directly to employers"
                                    : "Fills forms, captures screenshots, strictly no submission",
                                style: TextStyle(fontSize: 11, color: secondaryTextColor),
                              ),
                            ],
                          ),
                          Switch(
                            value: isLive,
                            activeColor: AppColors.warningLight,
                            onChanged: (_) => _toggleGoLive(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s16),

                // 3. Rate Limits & Guardrails
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
                      Text("RATE LIMITS & SAFETY GUARDRAILS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                      const SizedBox(height: AppSpacing.s12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _dailyCapController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: "Daily Application Cap", hintText: "100"),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: TextField(
                              controller: _hourlyCapController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: "Hourly Velocity Limit", hintText: "10"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _saveLimits,
                          child: const Text("Save Rate Limits"),
                        ),
                      ),
                      Divider(color: borderColor),
                      const SizedBox(height: AppSpacing.s8),
                      _buildSafetyItem("Circuit Breaker", "Trips after 3 consecutive errors", Icons.health_and_safety_outlined, accentGreen),
                      const SizedBox(height: AppSpacing.s6),
                      _buildSafetyItem("Per-Company Cooldown", "30-day deduplication cooldown window", Icons.calendar_month_outlined, accentGreen),
                      const SizedBox(height: AppSpacing.s6),
                      _buildSafetyItem("CAPTCHA / OTP Policy", "Zero bypass; escalates to Needs You Inbox", Icons.security_outlined, brassColor),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s16),

                // 4. Live Engine Log Stream
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
                          Text("ENGINE EXECUTION STREAM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                          const Icon(Icons.sync, size: 14, color: AppColors.mutedGray),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      ..._logs.take(15).map((log) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log["created_at"] ?? "", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(log["message"] ?? "", style: TextStyle(fontSize: 11, height: 1.3, color: primaryTextColor)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),
              ],
            ),
    );
  }

  Widget _buildSafetyItem(String title, String subtitle, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.mutedGray)),
          ],
        ),
      ],
    );
  }
}
