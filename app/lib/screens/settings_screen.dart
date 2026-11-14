import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onNavigateToResumes;
  final VoidCallback? onNavigateToControlCenter;

  const SettingsScreen({
    super.key,
    this.onNavigateToProfile,
    this.onNavigateToResumes,
    this.onNavigateToControlCenter,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _urlController.text = _api.baseUrl;
    _tokenController.text = _api.token;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _testAndSaveConnection() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _testing = true;
      _testResult = null;
    });

    await _api.saveConnectionSettings(_urlController.text, _tokenController.text);
    final health = await _api.checkHealth();
    setState(() {
      _testing = false;
      if (health["status"] == "online" || health["status"] == "healthy") {
        _testResult = "Connection Verified: Host Operational (v${health['version'] ?? '1.2.0'})";
      } else {
        _testResult = "Connection Failed: ${health['error'] ?? 'Unreachable host'}";
      }
    });
  }

  Future<void> _triggerBackup() async {
    HapticFeedback.lightImpact();
    try {
      final res = await _api.triggerBackup();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Backup created at: ${res['backup_path'] ?? 'backups/'}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup failed: $e")));
    }
  }

  Future<void> _rotateToken() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rotate Security Bearer Token"),
        content: const Text(
          "Rotating the token generates a fresh cryptographically random token on the PC host "
          "and updates this mobile device automatically.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Rotate Token")),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final res = await _api.rotateToken();
        _tokenController.text = _api.token;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res["message"])));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Rotation failed: $e")));
      }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Settings & Connectivity",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          // 1. Appearance / Theme
          _buildSectionHeader("APPEARANCE & THEME", secondaryTextColor),
          const SizedBox(height: AppSpacing.s8),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: borderColor),
            ),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, currentMode, _) {
                return Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text("Warm Ivory (Light Editorial)"),
                      subtitle: const Text("Ivory #FAFAF7, British Racing Green & Muted Brass"),
                      value: ThemeMode.light,
                      groupValue: currentMode,
                      activeColor: accentGreen,
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("Deep Forest Obsidian (Dark Editorial)"),
                      subtitle: const Text("Deep Forest Slate & Emerald Racing Green"),
                      value: ThemeMode.dark,
                      groupValue: currentMode,
                      activeColor: accentGreen,
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("System Default"),
                      value: ThemeMode.system,
                      groupValue: currentMode,
                      activeColor: accentGreen,
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 2. Tailscale PC Host Connection
          _buildSectionHeader("TAILSCALE PC HOST CONNECTION", secondaryTextColor),
          const SizedBox(height: AppSpacing.s8),
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
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(labelText: "Tailscale PC Server URL", hintText: "http://100.x.y.z:8000"),
                ),
                const SizedBox(height: AppSpacing.s12),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Bearer Auth Token"),
                ),
                const SizedBox(height: AppSpacing.s16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testing ? null : _testAndSaveConnection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: AppColors.pureWhite,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                        ),
                        icon: _testing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pureWhite))
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text("Verify Connection"),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    OutlinedButton(
                      onPressed: _rotateToken,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12, horizontal: AppSpacing.s12),
                      ),
                      child: const Text("Rotate Token"),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _testResult!.startsWith("Connection Verified") ? AppColors.successLight : AppColors.errorLight,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 3. Database & Backups
          _buildSectionHeader("DATA PRESERVATION & BACKUPS", secondaryTextColor),
          const SizedBox(height: AppSpacing.s8),
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
                Text("Nightly Backups & Integrity", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor)),
                const SizedBox(height: 4),
                Text("Database snapshots are stored in /backups with timestamped tar archives.", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                const SizedBox(height: AppSpacing.s12),
                OutlinedButton.icon(
                  onPressed: _triggerBackup,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  ),
                  icon: const Icon(Icons.backup_outlined, size: 16),
                  label: const Text("Trigger Immediate Nightly Backup"),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 4. About & Version
          Center(
            child: Column(
              children: [
                Text("ApplyPilot • Autonomous Career Cockpit v1.2.0", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 2),
                Text("FastAPI + Playwright on Windows Host ↔ Flutter on Android", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Text(
      title,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: color),
    );
  }
}
