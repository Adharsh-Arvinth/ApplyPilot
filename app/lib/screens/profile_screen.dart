import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/hallmark_tokens.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  Map<String, dynamic> _lockedFacts = {};

  final TextEditingController _gradController = TextEditingController();
  final TextEditingController _noticeController = TextEditingController();
  final TextEditingController _workAuthController = TextEditingController();
  final TextEditingController _salaryController = TextEditingController();

  List<String> _targetRoles = [];
  List<String> _locations = [];
  List<String> _excludedCompanies = [];

  final TextEditingController _newRoleController = TextEditingController();
  final TextEditingController _newLocController = TextEditingController();
  final TextEditingController _newExcludedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _gradController.dispose();
    _noticeController.dispose();
    _workAuthController.dispose();
    _salaryController.dispose();
    _newRoleController.dispose();
    _newLocController.dispose();
    _newExcludedController.dispose();
    super.dispose();
  }

  String _formatIndianCurrency(int val) {
    String s = val.toString();
    if (s.length <= 3) return "₹$s";
    String last3 = s.substring(s.length - 3);
    String rest = s.substring(0, s.length - 3);
    RegExp reg = RegExp(r'(\d+?)(?=(\d\d)+$)');
    String formatted = rest.replaceAllMapped(reg, (Match m) => '${m[1]},');
    return "₹$formatted,$last3";
  }

  Future<void> _loadProfileData() async {
    setState(() => _loading = true);
    try {
      final pFuture = _api.getProfile();
      final factsFuture = _api.getLockedFacts();
      final results = await Future.wait([pFuture, factsFuture]);

      final p = results[0] as Map<String, dynamic>;
      final facts = results[1] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _lockedFacts = facts;
          _gradController.text = p["graduation_date"] ?? "";
          _noticeController.text = p["notice_period"] ?? "";
          _workAuthController.text = p["work_authorization"] ?? "";
          _salaryController.text = (p["min_salary_inr"] ?? 700000).toString();

          _targetRoles = List<String>.from(p["target_roles"] ?? []);
          _locations = List<String>.from(p["locations"] ?? []);
          _excludedCompanies = List<String>.from(p["excluded_companies"] ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      final salary = int.tryParse(_salaryController.text.trim()) ?? 700000;
      await _api.updateProfile({
        "graduation_date": _gradController.text.trim(),
        "notice_period": _noticeController.text.trim(),
        "work_authorization": _workAuthController.text.trim(),
        "min_salary_inr": salary < 700000 ? 700000 : salary,
        "target_roles": _targetRoles,
        "locations": _locations,
        "excluded_companies": _excludedCompanies,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile preferences saved successfully.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save profile: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadResume() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (file != null) {
        setState(() => _uploading = true);
        final bytes = await file.readAsBytes();
        await _api.uploadResume(bytes, file.name);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Master resume uploaded and parsed.")),
          );
        }
        _loadProfileData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickGraduationDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 1, 5),
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
      helpText: "CONFIRM EXPECTED GRADUATION DATE",
    );
    if (picked != null) {
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      setState(() {
        _gradController.text = "${months[picked.month - 1]} ${picked.year}";
      });
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

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F10) : AppColors.canvasLight,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F0F10) : AppColors.surfaceLight,
        elevation: 0,
        title: Text(
          "Profile",
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 24,
            fontWeight: FontWeight.w400,
            color: primaryTextColor,
          ),
        ),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 20),
            tooltip: "Save Profile",
            onPressed: _saving ? null : _saveProfile,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              children: [
                // 1. LOCKED FACTS CARD AT THE TOP (PADLOCK ICON + TWO-COLUMN GRID)
                _buildLockedFactsCard(isDark, primaryTextColor, secondaryTextColor, accentGreen, cardBg, borderColor),

                const SizedBox(height: AppSpacing.s20),

                // 2. MASTER RESUME UPLOAD CARD
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentGreen.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.upload_file_outlined, color: accentGreen, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Master Resume PDF", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                            const SizedBox(height: 2),
                            Text("Single-column, text-selectable A4 resume.", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _uploading ? null : _pickAndUploadResume,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColorOrAccent(primaryTextColor, accentGreen),
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _uploading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text("Upload PDF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s20),

                // 3. EDITABLE CANDIDATE PREFERENCES
                Text(
                  "EDITABLE PREFERENCES",
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
                      // Graduation Date Picker
                      Text("Expected Graduation Date", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickGraduationDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, size: 16, color: accentGreen),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _gradController.text.isEmpty ? "Tap to confirm expected graduation (e.g. May 2027)" : _gradController.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _gradController.text.isEmpty ? FontWeight.w400 : FontWeight.w600,
                                    color: _gradController.text.isEmpty ? secondaryTextColor : primaryTextColor,
                                  ),
                                ),
                              ),
                              Icon(Icons.arrow_drop_down, color: secondaryTextColor),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),

                      // Notice Period
                      Text("Notice Period / Earliest Start", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _noticeController,
                        decoration: InputDecoration(
                          hintText: "e.g. Immediate, 15 Days, 1 Month",
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentGreen, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: ["Immediate", "15 Days", "30 Days", "Negotiable"].map((opt) {
                          return ActionChip(
                            label: Text(opt, style: TextStyle(fontSize: 11, color: primaryTextColor)),
                            backgroundColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                            side: BorderSide(color: borderColor),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _noticeController.text = opt);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.s16),

                      // Work Authorization
                      Text("Work Authorization", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _workAuthController,
                        decoration: InputDecoration(
                          hintText: "e.g. Citizen of India, No sponsorship required",
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentGreen, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: ["Citizen of India", "Authorized to work in India", "Requires sponsorship"].map((opt) {
                          return ActionChip(
                            label: Text(opt, style: TextStyle(fontSize: 11, color: primaryTextColor)),
                            backgroundColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                            side: BorderSide(color: borderColor),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _workAuthController.text = opt);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.s16),

                      // Minimum Salary (₹ Floor)
                      Text("Minimum Salary Expectation (INR)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _salaryController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: "₹ ",
                          helperText: "Floor: ${_formatIndianCurrency(int.tryParse(_salaryController.text.trim()) ?? 700000)} (Minimum ₹7 LPA per eligibility rules)",
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentGreen, width: 1.5)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s20),

                // 4. CAREER CRITERIA: TARGET ROLES & LOCATIONS
                Text(
                  "TARGET ROLES & LOCATIONS",
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
                      Text("Target Roles (0-2 Years / Fresher)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _targetRoles.map((r) => Chip(
                          label: Text(r, style: TextStyle(fontSize: 11, color: primaryTextColor)),
                          backgroundColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          side: BorderSide(color: borderColor),
                          onDeleted: () => setState(() => _targetRoles.remove(r)),
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newRoleController,
                              decoration: const InputDecoration(hintText: "Add role (e.g. AI Engineer, Software Engineer)"),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle, color: accentGreen),
                            onPressed: () {
                              if (_newRoleController.text.trim().isNotEmpty) {
                                setState(() {
                                  _targetRoles.add(_newRoleController.text.trim());
                                  _newRoleController.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),

                      Text("Target Locations (India Only)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _locations.map((l) => Chip(
                          label: Text(l, style: TextStyle(fontSize: 11, color: primaryTextColor)),
                          backgroundColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          side: BorderSide(color: borderColor),
                          onDeleted: () => setState(() => _locations.remove(l)),
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newLocController,
                              decoration: const InputDecoration(hintText: "Add location (e.g. Bangalore, Remote-India)"),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle, color: accentGreen),
                            onPressed: () {
                              if (_newLocController.text.trim().isNotEmpty) {
                                setState(() {
                                  _locations.add(_newLocController.text.trim());
                                  _newLocController.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),

                      Text("Excluded Companies (Blacklist)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _excludedCompanies.map((c) => Chip(
                          label: Text(c, style: const TextStyle(fontSize: 11, color: AppColors.errorLight)),
                          backgroundColor: AppColors.errorLight.withOpacity(0.08),
                          side: BorderSide(color: AppColors.errorLight.withOpacity(0.3)),
                          onDeleted: () => setState(() => _excludedCompanies.remove(c)),
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newExcludedController,
                              decoration: const InputDecoration(hintText: "Add company to blacklist..."),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: AppColors.errorLight),
                            onPressed: () {
                              if (_newExcludedController.text.trim().isNotEmpty) {
                                setState(() {
                                  _excludedCompanies.add(_newExcludedController.text.trim());
                                  _newExcludedController.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // Save Profile Button
                ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGreen,
                    foregroundColor: isDark ? const Color(0xFF0E0F0E) : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Save Preferences", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: AppSpacing.s24),
              ],
            ),
    );
  }

  Color primaryColorOrAccent(Color primary, Color accent) {
    return primary;
  }

  Widget _buildLockedFactsCard(
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
    Color accentColor,
    Color cardBg,
    Color borderColor,
  ) {
    final candidate = (_lockedFacts["candidate"] as Map<String, dynamic>?) ?? {};
    final education = (_lockedFacts["education"] as Map<String, dynamic>?) ?? {};
    final patents = (_lockedFacts["patents"] as List<dynamic>?) ?? [];
    final project = (_lockedFacts["project"] as Map<String, dynamic>?) ?? {};
    final certs = (_lockedFacts["certifications"] as List<dynamic>?) ?? [];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Padlock
          Row(
            children: [
              Icon(Icons.lock_outline, size: 20, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Locked Ground Truth Facts",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryColor),
                    ),
                    Text(
                      "Single source of truth · Edit via facts.py on your PC",
                      style: TextStyle(fontSize: 11, color: secondaryColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accentColor.withOpacity(0.3)),
                ),
                child: Text(
                  "READ-ONLY",
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.s16),

          // Two-Column Grid for Personal Facts
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFactItem("CANDIDATE", candidate["name"] ?? "Alex Morgan", primaryColor, secondaryColor)),
              const SizedBox(width: AppSpacing.s12),
              Expanded(child: _buildFactItem("PHONE", candidate["phone"] ?? "+1 555 0100", primaryColor, secondaryColor)),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFactItem("PRIMARY EMAIL", candidate["email"] ?? "alex.morgan@example.com", primaryColor, secondaryColor)),
              const SizedBox(width: AppSpacing.s12),
              Expanded(child: _buildFactItem("DEGREE & CGPA", "${education['degree'] ?? 'MTech CSE'} • ${education['cgpa'] ?? '8.10/10'}", primaryColor, secondaryColor)),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFactItem("INSTITUTION", education["institution"] ?? "Example Institute of Technology (VIT)", primaryColor, secondaryColor)),
              const SizedBox(width: AppSpacing.s12),
              Expanded(child: _buildFactItem("ATTENDANCE", "Sep 2022 – Present", primaryColor, secondaryColor)),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.s12),

          // Verified Patents
          Text("PUBLISHED PATENTS (EXACT TITLES)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryColor)),
          const SizedBox(height: 6),
          if (patents.isNotEmpty) ...patents.map((p) {
            final title = p is Map ? (p["title"] ?? "") : p.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified, size: 13, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: primaryColor))),
                ],
              ),
            );
          }) else ...[
            Text("• A Low-Power Soil Moisture Controller", style: TextStyle(fontSize: 12, color: primaryColor)),
            const SizedBox(height: 2),
            Text("• Ultrasonic Presence Verification for Secure Sessions", style: TextStyle(fontSize: 12, color: primaryColor)),
          ],

          const SizedBox(height: AppSpacing.s12),

          // Verified Project
          Text("SYSTEM BENCHMARK PROJECT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryColor)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.analytics_outlined, size: 14, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${project['name'] ?? 'Code Retrieval Engine'}: 10,000 Python programs; 18% NDCG@10 vs 5% baseline; 40–60 ms CPU latency",
                  style: TextStyle(fontSize: 12, height: 1.35, color: primaryColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.s12),

          // Verified Certifications
          Text("CERTIFICATIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryColor)),
          const SizedBox(height: 4),
          if (certs.isNotEmpty) ...certs.map((c) {
            final title = c is Map ? (c["title"] ?? "") : c.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text("• $title", style: TextStyle(fontSize: 12, color: primaryColor)),
            );
          }) else ...[
            Text("• AWS Cloud Solutions Architect", style: TextStyle(fontSize: 12, color: primaryColor)),
            Text("• Generative AI Fundamentals", style: TextStyle(fontSize: 12, color: primaryColor)),
          ],
        ],
      ),
    );
  }

  Widget _buildFactItem(String label, String value, Color primary, Color secondary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondary)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: primary)),
      ],
    );
  }
}
