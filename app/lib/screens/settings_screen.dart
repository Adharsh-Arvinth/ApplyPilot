import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiClient();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  String _pingResult = "";
  bool _testing = false;
  bool _goLive = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = _api.baseUrl;
    _tokenCtrl.text = _api.token;
    _loadProfileState();
  }

  Future<void> _loadProfileState() async {
    try {
      final p = await _api.getProfile();
      if (mounted) {
        setState(() {
          _goLive = p["go_live"] ?? false;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _pingResult = "Pinging Windows host...";
    });
    await _api.saveConnectionSettings(_urlCtrl.text, _tokenCtrl.text);
    final health = await _api.checkHealth();
    if (mounted) {
      setState(() {
        _testing = false;
        if (health["status"] == "online") {
          _pingResult = "Connected! Windows PC online (${health["database"]}). Uptime: ${health["uptime_seconds"]}s";
        } else {
          _pingResult = "Connection failed: ${health["error"] ?? "Cannot reach server"}";
        }
      });
    }
  }

  Future<void> _toggleGoLive() async {
    final resp = await _api.toggleGoLive();
    if (mounted) {
      setState(() => _goLive = resp["go_live"] ?? false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _goLive ? AppColors.iosRed : AppColors.iosGreen,
          content: Text(_goLive ? "WARNING: Go-Live Mode ENABLED. Live submissions active." : "Safety ON: Running in Dry-Run Preview Mode."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings & Connection", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s16),
        children: [
          // 1. APPEARANCE / DARK MODE
          _buildSectionHeader("APPEARANCE & THEME", isDark),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (ctx, currentMode, _) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.dark_mode_outlined, color: AppColors.appleCrimson, size: 20),
                              SizedBox(width: 8),
                              Text("Interface Theme", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          Text(
                            currentMode == ThemeMode.dark
                                ? "Dark (OLED)"
                                : currentMode == ThemeMode.light
                                    ? "Light"
                                    : "System",
                            style: const TextStyle(color: AppColors.appleCrimson, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildThemeOption(
                            label: "System",
                            icon: Icons.brightness_auto,
                            isSelected: currentMode == ThemeMode.system,
                            onTap: () => setThemeMode(ThemeMode.system),
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            label: "Dark",
                            icon: Icons.dark_mode,
                            isSelected: currentMode == ThemeMode.dark,
                            onTap: () => setThemeMode(ThemeMode.dark),
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            label: "Light",
                            icon: Icons.light_mode,
                            isSelected: currentMode == ThemeMode.light,
                            onTap: () => setThemeMode(ThemeMode.light),
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.s24),

          // 2. SAFETY SWITCH (GO LIVE)
          _buildSectionHeader("APPLICATION SAFETY RAILS", isDark),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Go-Live Live Submissions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              _goLive
                                  ? "ACTIVE: Submitting live applications directly to ATS portals."
                                  : "DRY-RUN: Filling forms, testing validations and capturing proof screenshots without final submission.",
                              style: TextStyle(
                                fontSize: 12,
                                color: _goLive ? AppColors.iosRed : AppColors.iosGreen,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _goLive,
                        activeColor: AppColors.iosRed,
                        onChanged: (_) => _toggleGoLive(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.s24),

          // 3. PC SERVER CONNECTION
          _buildSectionHeader("TAILSCALE PRIVATE CONNECTION", isDark),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Column(
                children: [
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: "Tailscale PC Server URL",
                      hintText: "http://100.97.30.113:8000",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: "Bearer Auth Token",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.appleCrimson),
                        ),
                        icon: _testing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.appleCrimson))
                            : const Icon(Icons.wifi_tethering, size: 16, color: AppColors.appleCrimson),
                        label: const Text("Test Ping", style: TextStyle(color: AppColors.appleCrimson)),
                        onPressed: _testing ? null : _testConnection,
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.appleCrimson),
                        onPressed: () async {
                          await _api.saveConnectionSettings(_urlCtrl.text, _tokenCtrl.text);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: AppColors.iosGreen,
                                content: Text("Connection settings saved."),
                              ),
                            );
                          }
                        },
                        child: const Text("Save"),
                      ),
                    ],
                  ),
                  if (_pingResult.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _pingResult,
                      style: TextStyle(
                        fontSize: 12,
                        color: _pingResult.startsWith("Connected") ? AppColors.iosGreen : AppColors.iosRed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.s24),

          // 4. SYSTEM & RELIABILITY
          _buildSectionHeader("SYSTEM RELIABILITY & STORAGE", isDark),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.schedule, color: AppColors.appleCrimson),
                  title: Text("Nightly Database Backup"),
                  subtitle: Text("Daily at 03:00 IST to local backups/ folder with atomic hash"),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.shield_outlined, color: AppColors.iosGreen),
                  title: Text("Safety Circuit Breaker"),
                  subtitle: Text("Auto-stops on 3 consecutive CAPTCHAs or rapid failure bursts"),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
        color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
      ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.appleCrimson.withOpacity(0.18)
                : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.appleCrimson : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isSelected ? AppColors.appleCrimson : null),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.appleCrimson : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
