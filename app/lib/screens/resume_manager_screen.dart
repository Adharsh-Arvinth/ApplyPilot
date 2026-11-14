import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class ResumeManagerScreen extends StatefulWidget {
  const ResumeManagerScreen({super.key});

  @override
  State<ResumeManagerScreen> createState() => _ResumeManagerScreenState();
}

class _ResumeManagerScreenState extends State<ResumeManagerScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  List<dynamic> _versions = [];

  // Tailoring Simulator Form
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  final TextEditingController _jdController = TextEditingController();
  bool _simulating = false;
  Map<String, dynamic>? _tailorResult;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  @override
  void dispose() {
    _companyController.dispose();
    _roleController.dispose();
    _jdController.dispose();
    super.dispose();
  }

  Future<void> _loadVersions() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getResumes();
      if (mounted) {
        setState(() {
          _versions = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMaster(int id) async {
    HapticFeedback.mediumImpact();
    try {
      await _api.setMasterResume(id);
      _loadVersions();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Master resume updated.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e")));
    }
  }

  Future<void> _runTailorSimulation() async {
    final company = _companyController.text.trim();
    final role = _roleController.text.trim();
    if (company.isEmpty || role.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Company and Role are required.")));
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _simulating = true);
    try {
      final res = await _api.tailorResumeSimulation({
        "company": company,
        "role": role,
        "job_description": _jdController.text.trim(),
      });
      if (mounted) {
        setState(() {
          _tailorResult = res;
          _simulating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _simulating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Simulation error: $e")));
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
          "Resume Intelligence",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadVersions),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              children: [
                // 1. Live Job Tailoring Simulator
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
                        children: [
                          Icon(Icons.tune, size: 18, color: accentGreen),
                          const SizedBox(width: AppSpacing.s8),
                          Text(
                            "JOB-SPECIFIC TAILORING SIMULATOR",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _companyController,
                              decoration: const InputDecoration(labelText: "Target Company", hintText: "e.g. Anthropic"),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: TextField(
                              controller: _roleController,
                              decoration: const InputDecoration(labelText: "Target Role", hintText: "e.g. AI Research Engineer"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      TextField(
                        controller: _jdController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: "Job Description Snippet (Optional)",
                          hintText: "Paste key technical requirements for keyword analysis...",
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _simulating ? null : _runTailorSimulation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentGreen,
                            foregroundColor: AppColors.pureWhite,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                          ),
                          icon: _simulating
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pureWhite))
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: const Text("Generate Tailored Resume & Keyword Audit", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),

                      // Simulation Results
                      if (_tailorResult != null) ...[
                        const SizedBox(height: AppSpacing.s20),
                        Divider(color: borderColor),
                        const SizedBox(height: AppSpacing.s12),
                        Row(
                          children: [
                            _buildStatBox("ATS SCORE", "${_tailorResult!['ats_score']}%", AppColors.successLight),
                            const SizedBox(width: AppSpacing.s12),
                            _buildStatBox("KEYWORD MATCH", "${_tailorResult!['keyword_coverage_percent']}%", accentGreen),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        Text("VERIFIED KEYWORDS COVERED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                        const SizedBox(height: AppSpacing.s6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: ((_tailorResult!["matched_keywords"] as List<dynamic>?) ?? []).map<Widget>((kw) {
                            return Chip(
                              label: Text(kw, style: const TextStyle(fontSize: 11)),
                              backgroundColor: accentGreen.withOpacity(0.12),
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                        if (((_tailorResult!["missing_qualifications"] as List<dynamic>?) ?? []).isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.s12),
                          Text("MISSING QUALIFICATIONS (NOT FABRICATED)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.warningLight)),
                          const SizedBox(height: AppSpacing.s6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: ((_tailorResult!["missing_qualifications"] as List<dynamic>?) ?? []).map<Widget>((kw) {
                              return Chip(
                                label: Text(kw, style: const TextStyle(fontSize: 11, color: AppColors.warningLight)),
                                backgroundColor: AppColors.warningLight.withOpacity(0.12),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.s12),
                        Text("DECISIONS APPLIED", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                        const SizedBox(height: AppSpacing.s4),
                        ...((_tailorResult!["changes_applied"] as List<dynamic>?) ?? []).map((ch) => Text("• $ch", style: TextStyle(fontSize: 12, color: primaryTextColor))),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // 2. Resume Version Portfolio
                Text("RESUME VERSION PORTFOLIO", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                const SizedBox(height: AppSpacing.s12),
                ..._versions.map((ver) {
                  final isMaster = ver["is_master"] == true;
                  final ats = ver["ats_score"] ?? 95.0;
                  final tags = (ver["keyword_tags"] as List<dynamic>?) ?? [];

                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.s12),
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: isMaster ? accentGreen : borderColor, width: isMaster ? 1.5 : 1.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                ver["version_name"] ?? "",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                              ),
                            ),
                            if (isMaster)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: accentGreen, borderRadius: BorderRadius.circular(AppRadii.badge)),
                                child: const Text("MASTER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text("Target: ${ver['target_role']} • ATS Score: $ats%", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                        const SizedBox(height: AppSpacing.s10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: tags.map<Widget>((t) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(AppRadii.badge)),
                              child: Text(t, style: TextStyle(fontSize: 10, color: primaryTextColor)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!isMaster)
                              TextButton(
                                onPressed: () => _setMaster(ver["id"]),
                                child: const Text("Set as Master"),
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

  Widget _buildStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
