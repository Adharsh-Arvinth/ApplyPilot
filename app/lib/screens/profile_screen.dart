import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiClient();
  bool _loading = true;
  bool _saving = false;
  bool _uploadingResume = false;
  String _resumeUploadStatus = "Adharsh_Arvinth_Master_Resume.pdf";

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _githubCtrl = TextEditingController();
  final _educationCtrl = TextEditingController();
  final _cgpaCtrl = TextEditingController();
  final _gradDateCtrl = TextEditingController();
  final _noticePeriodCtrl = TextEditingController();
  final _workAuthCtrl = TextEditingController();
  final _relocationCtrl = TextEditingController();
  final _workModeCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _dailyCapCtrl = TextEditingController();
  final _rolesCtrl = TextEditingController();
  final _locationsCtrl = TextEditingController();
  final _proofPointsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _linkedinCtrl.dispose();
    _githubCtrl.dispose();
    _educationCtrl.dispose();
    _cgpaCtrl.dispose();
    _gradDateCtrl.dispose();
    _noticePeriodCtrl.dispose();
    _workAuthCtrl.dispose();
    _relocationCtrl.dispose();
    _workModeCtrl.dispose();
    _salaryCtrl.dispose();
    _dailyCapCtrl.dispose();
    _rolesCtrl.dispose();
    _locationsCtrl.dispose();
    _proofPointsCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() => _loading = true);
    try {
      final p = await _api.getProfile();
      if (mounted) {
        setState(() {
          _nameCtrl.text = p["full_name"] ?? "";
          _emailCtrl.text = p["email"] ?? "";
          _phoneCtrl.text = p["phone"] ?? "";
          _linkedinCtrl.text = p["linkedin"] ?? "";
          _githubCtrl.text = p["github"] ?? "";
          _educationCtrl.text = p["education"] ?? "";
          _cgpaCtrl.text = p["cgpa"] ?? "";
          _gradDateCtrl.text = p["graduation_date"] ?? "";
          _noticePeriodCtrl.text = p["notice_period"] ?? "";
          _workAuthCtrl.text = p["work_authorization"] ?? "";
          _relocationCtrl.text = p["relocation_preference"] ?? "";
          _workModeCtrl.text = p["preferred_work_mode"] ?? "";
          _salaryCtrl.text = (p["min_salary_inr"] ?? 700000).toString();
          _dailyCapCtrl.text = (p["daily_cap"] ?? 100).toString();
          _rolesCtrl.text = ((p["target_roles"] as List<dynamic>?) ?? []).join(", ");
          _locationsCtrl.text = ((p["locations"] as List<dynamic>?) ?? []).join(", ");
          _proofPointsCtrl.text = p["proof_points_text"] ?? "";
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadResume() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isEmpty) return;
      final file = files.first;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Selected resume file is empty.")),
          );
        }
        return;
      }

      setState(() => _uploadingResume = true);
      final resp = await _api.uploadResume(bytes, file.name);

      if (mounted) {
        setState(() {
          _resumeUploadStatus = "${file.name} (Parsed & Active)";
          _uploadingResume = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.iosGreen,
            content: Text(resp["summary"] ?? "Master resume uploaded and parsed successfully!"),
          ),
        );
        _fetchProfile();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingResume = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.iosRed,
            content: Text("Resume upload failed: $e"),
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final roles = _rolesCtrl.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final locations = _locationsCtrl.text
        .split(",")
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = {
      "full_name": _nameCtrl.text.trim(),
      "email": _emailCtrl.text.trim(),
      "phone": _phoneCtrl.text.trim(),
      "linkedin": _linkedinCtrl.text.trim(),
      "github": _githubCtrl.text.trim(),
      "education": _educationCtrl.text.trim(),
      "cgpa": _cgpaCtrl.text.trim(),
      "graduation_date": _gradDateCtrl.text.trim(),
      "notice_period": _noticePeriodCtrl.text.trim(),
      "work_authorization": _workAuthCtrl.text.trim(),
      "relocation_preference": _relocationCtrl.text.trim(),
      "preferred_work_mode": _workModeCtrl.text.trim(),
      "min_salary_inr": int.tryParse(_salaryCtrl.text.trim()) ?? 700000,
      "daily_cap": int.tryParse(_dailyCapCtrl.text.trim()) ?? 100,
      "target_roles": roles,
      "locations": locations,
      "proof_points_text": _proofPointsCtrl.text.trim(),
    };

    try {
      await _api.updateProfile(payload);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.iosGreen,
            content: Text("Profile and application rules saved successfully!"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.iosRed, content: Text("Save failed: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile & Verification", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.appleCrimson)),
                )
              : TextButton(
                  onPressed: _saveProfile,
                  child: const Text("Save", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.appleCrimson)),
                ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.appleCrimson))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s16),
              children: [
                // 1. MASTER RESUME UPLOAD CARD
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(
                      color: AppColors.appleCrimson.withOpacity(0.35),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.upload_file, color: AppColors.appleCrimson, size: 22),
                              SizedBox(width: 8),
                              Text("Master Resume", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.iosGreen.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text("ACTIVE", style: TextStyle(color: AppColors.iosGreen, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Upload or update your master PDF resume anytime. ApplyPilot parses it with PyPDF and extracts candidate facts for 1-click auto-tailoring.",
                        style: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366), height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.picture_as_pdf, color: AppColors.appleCrimson, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _resumeUploadStatus,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.appleCrimson),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                          ),
                          icon: _uploadingResume
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.appleCrimson))
                              : const Icon(Icons.cloud_upload_outlined, color: AppColors.appleCrimson, size: 18),
                          label: Text(
                            _uploadingResume ? "Parsing Master Resume..." : "Upload New Resume (PDF)",
                            style: const TextStyle(color: AppColors.appleCrimson, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _uploadingResume ? null : _pickAndUploadResume,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // 2. CONTACT & IDENTIFIERS
                _buildSectionHeader("PERSONAL & IDENTITY", isDark),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Column(
                      children: [
                        _buildTextField(_nameCtrl, "Full Name"),
                        const SizedBox(height: 12),
                        _buildTextField(_emailCtrl, "Email Address", keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: 12),
                        _buildTextField(_phoneCtrl, "Phone Number", keyboardType: TextInputType.phone),
                        const SizedBox(height: 12),
                        _buildTextField(_linkedinCtrl, "LinkedIn URL", hint: "https://linkedin.com/in/..."),
                        const SizedBox(height: 12),
                        _buildTextField(_githubCtrl, "GitHub URL", hint: "https://github.com/..."),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // 3. TARGET ROLES & CRITERIA
                _buildSectionHeader("TARGET CRITERIA & SALARY", isDark),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Column(
                      children: [
                        _buildTextField(
                          _rolesCtrl,
                          "Target Roles (Comma-separated)",
                          helper: "e.g. Data Scientist, ML Engineer, AI/GenAI Engineer",
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          _locationsCtrl,
                          "Permitted Locations (Comma-separated)",
                          helper: "India only: Remote-India, Bengaluru, Chennai, Hyderabad, Pune",
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          _salaryCtrl,
                          "Minimum Salary (₹ INR / Year)",
                          keyboardType: TextInputType.number,
                          helper: "Skip postings offering under ₹7 LPA",
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          _dailyCapCtrl,
                          "Daily Application Cap",
                          keyboardType: TextInputType.number,
                          helper: "Configurable target (default: 100 applications/day)",
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // 4. EDUCATION & WORK AUTH
                _buildSectionHeader("EDUCATION & AVAILABILITY", isDark),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Column(
                      children: [
                        _buildTextField(_educationCtrl, "Education Program", helper: "MTech Integrated CSE (Data Science), VIT Vellore"),
                        const SizedBox(height: 12),
                        _buildTextField(_cgpaCtrl, "CGPA", helper: "7.62 / 10"),
                        const SizedBox(height: 12),
                        _buildTextField(_gradDateCtrl, "Graduation Date", helper: "e.g. June 2027"),
                        const SizedBox(height: 12),
                        _buildTextField(_noticePeriodCtrl, "Notice Period", helper: "Immediate / Available from Month-Year"),
                        const SizedBox(height: 12),
                        _buildTextField(_workAuthCtrl, "Work Authorization", helper: "Indian Citizen, No Sponsorship Needed"),
                        const SizedBox(height: 12),
                        _buildTextField(_relocationCtrl, "Willingness to Relocate", helper: "Yes / No / Hybrid"),
                        const SizedBox(height: 12),
                        _buildTextField(_workModeCtrl, "Preferred Work Mode", helper: "Remote / Hybrid / Onsite"),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // 5. IMMUTABLE PROOF POINTS (EDITABLE AS NEEDED)
                _buildSectionHeader("VERIFIED PROOF POINTS & PATENTS", isDark),
                const SizedBox(height: 4),
                Text(
                  "These verified facts form the strict truth source for all AI tailoring. Update any patents, metrics, or certifications whenever you wish.",
                  style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: TextField(
                      controller: _proofPointsCtrl,
                      maxLines: 8,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "Enter bullet points of patents, projects, and certifications...",
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Save button banner
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.appleCrimson,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                    ),
                    onPressed: _saving ? null : _saveProfile,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Save All Profile Changes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        isDense: true,
      ),
    );
  }
}
