import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/theme_mode.dart';

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
  final bool _syncingCloud = false;

  bool _loadingProfile = true;
  bool _goLive = false;
  int _dailyCap = 50;

  bool _geminiEnabled = true;
  double _geminiMinConfidence = 0.85;
  int _geminiDailyCap = 30;
  int _geminiAnswersToday = 0;
  int _savedMinutes = 0;
  List<String> _sensitiveCategories = [
    "consent_legal",
    "work_auth_visa",
    "salary_notice_relocation",
    "demographics_identity",
    "criminal_background",
    "legal_attestation",
    "ask_each_time"
  ];

  @override
  void initState() {
    super.initState();
    _urlController.text = _api.baseUrl;
    _tokenController.text = _api.token;
    _loadProfileSettings();
  }

  Future<void> _loadProfileSettings() async {
    try {
      final p = await _api.getProfile();
      final g = await _api.getGeminiSettings();
      if (mounted) {
        setState(() {
          _goLive = p["go_live"] == true;
          _dailyCap = (p["daily_cap"] as int?) ?? 50;
          if (g.isNotEmpty) {
            _geminiEnabled = g["gemini_auto_answer_enabled"] != false;
            _geminiMinConfidence = (g["gemini_min_confidence"] as num?)?.toDouble() ?? 0.85;
            _geminiDailyCap = (g["gemini_daily_cap"] as int?) ?? 30;
            _geminiAnswersToday = (g["gemini_answers_today"] as int?) ?? 0;
            _savedMinutes = (g["saved_minutes"] as int?) ?? 0;
            if (g["gemini_sensitive_categories"] is List) {
              _sensitiveCategories = List<String>.from(g["gemini_sensitive_categories"]);
            }
          }
          _loadingProfile = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _updateGeminiToggle(bool val) async {
    setState(() => _geminiEnabled = val);
    try {
      await _api.updateGeminiSettings({"gemini_auto_answer_enabled": val});
    } catch (_) {}
  }

  Future<void> _updateGeminiConfidence(double val) async {
    setState(() => _geminiMinConfidence = val);
    try {
      await _api.updateGeminiSettings({"gemini_min_confidence": val});
    } catch (_) {}
  }

  Future<void> _updateGeminiDailyCap(double val) async {
    final cap = val.round();
    setState(() => _geminiDailyCap = cap);
    try {
      await _api.updateGeminiSettings({"gemini_daily_cap": cap});
    } catch (_) {}
  }

  Future<bool?> _showGoLiveConfirmationDialog() async {
    final textController = TextEditingController();
    bool canConfirm = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final coral = AppColors.getSemanticColor("coral", isDark);

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF161816) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: coral, size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "Activate Live Mode?",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Live mode will submit REAL applications to external employer ATS portals with your official email address and resume.",
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "To prevent accidental submission, type GO LIVE below:",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: "Type GO LIVE",
                      filled: true,
                      fillColor: isDark ? const Color(0xFF0E0F0E) : const Color(0xFFF3F4F1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        canConfirm = val.trim().toUpperCase() == "GO LIVE";
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: canConfirm
                      ? () {
                          Navigator.pop(ctx, true);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: coral,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark ? const Color(0xFF262926) : Colors.grey.shade300,
                  ),
                  child: const Text("Confirm & Go Live"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleGoLiveToggle(bool val) async {
    HapticFeedback.mediumImpact();
    if (val) {
      final confirmed = await _showGoLiveConfirmationDialog();
      if (confirmed == true) {
        try {
          final res = await _api.toggleGoLive();
          setState(() => _goLive = res["go_live"] ?? true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Live mode ACTIVE. Real applications enabled.")),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error toggling mode: $e")));
          }
        }
      }
    } else {
      try {
        final res = await _api.toggleGoLive();
        setState(() => _goLive = res["go_live"] ?? false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Dry-run mode ACTIVE. No live submissions will occur.")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error toggling mode: $e")));
        }
      }
    }
  }

  Future<void> _updateDailyCap(double val) async {
    final newCap = val.round();
    setState(() => _dailyCap = newCap);
    try {
      await _api.updateProfile({"daily_cap": newCap});
    } catch (_) {}
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Backup created at: ${res['backup_path'] ?? 'backups/'}")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Backup failed: $e")));
      }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res["message"])));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Rotation failed: $e")));
        }
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
    final coral = AppColors.getSemanticColor("coral", isDark);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Settings & Connectivity",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primaryTextColor),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          // 1. APPLICATION MODE & GO-LIVE SAFETY SWITCH
          Text(
            "SUBMISSION SAFETY MODE",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _goLive ? coral.withOpacity(0.5) : borderColor,
                width: _goLive ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _goLive ? Icons.warning_amber_rounded : Icons.shield_outlined,
                      size: 20,
                      color: _goLive ? coral : accentGreen,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _goLive ? "Live Submission Mode" : "Dry-Run Safety Mode",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _goLive ? coral : primaryTextColor,
                            ),
                          ),
                          Text(
                            _goLive
                                ? "Real applications being submitted to employer portals"
                                : "Forms filled & screenshots taken without submitting",
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _goLive,
                      activeColor: coral,
                      inactiveThumbColor: accentGreen,
                      onChanged: _loadingProfile ? null : (val) => _handleGoLiveToggle(val),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.s16),

                // Daily Cap Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Daily Cap: $_dailyCap applications", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                    Text("Cap resets midnight", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                  ],
                ),
                Slider(
                  value: _dailyCap.toDouble().clamp(10, 100),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  activeColor: accentGreen,
                  label: "$_dailyCap",
                  onChanged: (val) => setState(() => _dailyCap = val.round()),
                  onChangeEnd: _updateDailyCap,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // GEMINI AUTO-ANSWER INTELLIGENCE
          Text(
            "GEMINI AUTO-ANSWER INTELLIGENCE",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
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
                          Text(
                            "Auto-answer unlisted questions",
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Uses Gemini to answer truthfully from locked facts before Needs You.",
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _geminiEnabled,
                      activeColor: accentGreen,
                      onChanged: _updateGeminiToggle,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.s12),

                Container(
                  padding: const EdgeInsets.all(AppSpacing.s12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 18, color: accentGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Gemini answered $_geminiAnswersToday questions today (saved ~$_savedMinutes mins)",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Minimum Confidence: ${(_geminiMinConfidence * 100).toInt()}%",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                    ),
                    Text("Range 70% – 99%", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                  ],
                ),
                Slider(
                  value: _geminiMinConfidence.clamp(0.70, 0.99),
                  min: 0.70,
                  max: 0.99,
                  divisions: 29,
                  activeColor: accentGreen,
                  label: "${(_geminiMinConfidence * 100).toInt()}%",
                  onChanged: (val) => setState(() => _geminiMinConfidence = val),
                  onChangeEnd: _updateGeminiConfidence,
                ),

                const SizedBox(height: AppSpacing.s8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Daily Cap: $_geminiDailyCap calls/day", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                    Text("Prevents runaway usage", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                  ],
                ),
                Slider(
                  value: _geminiDailyCap.toDouble().clamp(5, 100),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  activeColor: accentGreen,
                  label: "$_geminiDailyCap",
                  onChanged: (val) => setState(() => _geminiDailyCap = val.round()),
                  onChangeEnd: _updateGeminiDailyCap,
                ),

                const SizedBox(height: AppSpacing.s12),
                Text(
                  "SENSITIVE CATEGORIES (NEVER SENT TO GEMINI)",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: secondaryTextColor),
                ),
                const SizedBox(height: AppSpacing.s8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _sensitiveCategories.map((cat) {
                    final label = cat.replaceAll("_", " ").split(" ").map((w) => w.isNotEmpty ? "${w[0].toUpperCase()}${w.substring(1)}" : "").join(" ");
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined, size: 11, color: secondaryTextColor),
                          const SizedBox(width: 4),
                          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: primaryTextColor)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 2. SYSTEM INTEGRATION CHIPS
          Text(
            "INTEGRATION STATUS",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip("Gmail OTP Matcher", true, accentGreen, primaryTextColor, isDark),
                _buildStatusChip("Telegram Bot", true, accentGreen, primaryTextColor, isDark),
                _buildStatusChip("SQLite WAL Mode", true, accentGreen, primaryTextColor, isDark),
                _buildStatusChip("Tailscale Mesh", true, accentGreen, primaryTextColor, isDark),
                _buildStatusChip("Playwright Engine", true, accentGreen, primaryTextColor, isDark),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 3. SAFETY GUARANTEES & STRICT RULES
          Text(
            "ACTIVE SAFETY GUARANTEES",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRuleRow(Icons.check_circle_outline, "Seniority Guard", "Fresher / 0–2 years only. Rejects senior, staff, lead, principal, manager, director, or 3+ years requirements.", accentGreen, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 12),
                _buildRuleRow(Icons.check_circle_outline, "India-Only & Pay Floor", "India only (Remote or major tech hubs). Minimum ₹7 LPA when pay listed; internships under ₹25k skipped.", accentGreen, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 12),
                _buildRuleRow(Icons.check_circle_outline, "Assist-Only Enforcement", "LinkedIn Easy Apply, Indeed, Naukri, Workday require candidate review. Auto-submit allowed only on Greenhouse, Lever, Ashby, Workable.", accentGreen, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 12),
                _buildRuleRow(Icons.check_circle_outline, "Zero Hallucination", "All claims strictly checked against facts.py. Unverified metrics, patents, or certifications block application and route to Needs You.", accentGreen, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 12),
                _buildRuleRow(Icons.check_circle_outline, "Proof-Backed Application", "Marked as Applied only with confirmed screenshot & ATS confirmation text. Retries are strictly idempotent.", accentGreen, primaryTextColor, secondaryTextColor),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 4. DATA PRESERVATION & IMMEDIATE BACKUP
          Text(
            "DATA INTEGRITY & BACKUPS",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Nightly Backups & WAL Snapshots", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                const SizedBox(height: 2),
                Text("Database snapshots are stored in /backups with timestamped archives.", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                const SizedBox(height: AppSpacing.s12),
                OutlinedButton.icon(
                  onPressed: _triggerBackup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryTextColor,
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.backup_outlined, size: 16),
                  label: const Text("Create Immediate Backup Now", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 5. TAILSCALE PC HOST CONNECTION
          Text(
            "TAILSCALE HOST CONNECTION",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
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
                          foregroundColor: isDark ? const Color(0xFF0E0F0E) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        icon: _testing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text("Verify Connection", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    OutlinedButton(
                      onPressed: _rotateToken,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryTextColor,
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                      child: const Text("Rotate Token", style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _testResult!.startsWith("Connection Verified") ? AppColors.successLight : coral,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.s20),

          // 6. APPEARANCE & THEME
          Text(
            "THEME",
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s8),

          Container(
            padding: const EdgeInsets.all(AppSpacing.s12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, currentMode, _) {
                return Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text("Dark Theme (#0E0F0E)", style: TextStyle(fontSize: 13)),
                      value: ThemeMode.dark,
                      groupValue: currentMode,
                      activeColor: accentGreen,
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("Light Theme (#FAFAF7)", style: TextStyle(fontSize: 13)),
                      value: ThemeMode.light,
                      groupValue: currentMode,
                      activeColor: accentGreen,
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text("System Default", style: TextStyle(fontSize: 13)),
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
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, bool active, Color accent, Color textColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? accent.withOpacity(0.3) : Colors.grey.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? accent : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildRuleRow(IconData icon, String title, String description, Color accent, Color primaryColor, Color secondaryColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryColor)),
              const SizedBox(height: 2),
              Text(description, style: TextStyle(fontSize: 11, height: 1.35, color: secondaryColor)),
            ],
          ),
        ),
      ],
    );
  }
}
