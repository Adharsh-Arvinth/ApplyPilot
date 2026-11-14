import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

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

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _linkedinController = TextEditingController();
  final TextEditingController _githubController = TextEditingController();
  final TextEditingController _educationController = TextEditingController();
  final TextEditingController _cgpaController = TextEditingController();
  final TextEditingController _gradController = TextEditingController();
  final TextEditingController _noticeController = TextEditingController();
  final TextEditingController _workAuthController = TextEditingController();
  final TextEditingController _salaryController = TextEditingController();
  final TextEditingController _proofPointsController = TextEditingController();

  List<String> _targetRoles = [];
  List<String> _locations = [];
  List<String> _excludedCompanies = [];

  final TextEditingController _newRoleController = TextEditingController();
  final TextEditingController _newLocController = TextEditingController();
  final TextEditingController _newExcludedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _linkedinController.dispose();
    _githubController.dispose();
    _educationController.dispose();
    _cgpaController.dispose();
    _gradController.dispose();
    _noticeController.dispose();
    _workAuthController.dispose();
    _salaryController.dispose();
    _proofPointsController.dispose();
    _newRoleController.dispose();
    _newLocController.dispose();
    _newExcludedController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final p = await _api.getProfile();
      if (mounted) {
        setState(() {
          _nameController.text = p["full_name"] ?? "";
          _emailController.text = p["email"] ?? "";
          _phoneController.text = p["phone"] ?? "";
          _linkedinController.text = p["linkedin"] ?? "";
          _githubController.text = p["github"] ?? "";
          _educationController.text = p["education"] ?? "";
          _cgpaController.text = p["cgpa"] ?? "";
          _gradController.text = p["graduation_date"] ?? "";
          _noticeController.text = p["notice_period"] ?? "";
          _workAuthController.text = p["work_authorization"] ?? "";
          _salaryController.text = (p["min_salary_inr"] ?? 700000).toString();
          _proofPointsController.text = p["proof_points_text"] ?? "";

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
      await _api.updateProfile({
        "full_name": _nameController.text.trim(),
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
        "linkedin": _linkedinController.text.trim(),
        "github": _githubController.text.trim(),
        "education": _educationController.text.trim(),
        "cgpa": _cgpaController.text.trim(),
        "graduation_date": _gradController.text.trim(),
        "notice_period": _noticeController.text.trim(),
        "work_authorization": _workAuthController.text.trim(),
        "min_salary_inr": int.tryParse(_salaryController.text.trim()) ?? 700000,
        "proof_points_text": _proofPointsController.text.trim(),
        "target_roles": _targetRoles,
        "locations": _locations,
        "excluded_companies": _excludedCompanies,
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Candidate Profile saved successfully.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save failed: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadResume() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt'],
      );

      if (files != null && files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          setState(() => _uploading = true);
          final res = await _api.uploadResume(bytes, file.name);
          setState(() => _uploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Resume uploaded! Extracted: ${res['message']}")),
          );
          _loadProfile();
        }
      }
    } catch (e) {
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload error: $e")));
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
          "Candidate Profile",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
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
                // 1. Master Resume Upload Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        decoration: BoxDecoration(
                          color: accentGreen.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.upload_file_outlined, color: accentGreen, size: 28),
                      ),
                      const SizedBox(width: AppSpacing.s16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Master Resume Document", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor)),
                            const SizedBox(height: 2),
                            Text("Upload your latest PDF resume. PyPDF extracts facts automatically.", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _uploading ? null : _pickAndUploadResume,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: AppColors.pureWhite,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                        ),
                        child: _uploading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pureWhite))
                            : const Text("Upload PDF", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s16),

                // 2. Personal Information
                _buildSectionHeader("PERSONAL & CONTACT DETAILS", secondaryTextColor),
                const SizedBox(height: AppSpacing.s8),
                _buildCard(cardBg, borderColor, [
                  _buildTextField("Full Name", _nameController),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("Primary Email", _emailController),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("Mobile Number", _phoneController),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("LinkedIn Profile URL", _linkedinController),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("GitHub Profile URL", _githubController),
                ]),

                const SizedBox(height: AppSpacing.s16),

                // 3. Education & Credentials
                _buildSectionHeader("ACADEMIC & WORK AUTHORIZATION", secondaryTextColor),
                const SizedBox(height: AppSpacing.s8),
                _buildCard(cardBg, borderColor, [
                  _buildTextField("Highest Degree & Discipline", _educationController),
                  const SizedBox(height: AppSpacing.s12),
                  Row(
                    children: [
                      Expanded(child: _buildTextField("CGPA / GPA", _cgpaController)),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(child: _buildTextField("Graduation Date", _gradController)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("Notice Period / Availability", _noticeController),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("Work Authorization", _workAuthController),
                  const SizedBox(height: AppSpacing.s12),
                  _buildTextField("Minimum Salary Expectation (INR)", _salaryController, keyboardType: TextInputType.number),
                ]),

                const SizedBox(height: AppSpacing.s16),

                // 4. Target Roles & Locations
                _buildSectionHeader("CAREER CRITERIA & TARGET ROLES", secondaryTextColor),
                const SizedBox(height: AppSpacing.s8),
                _buildCard(cardBg, borderColor, [
                  Text("Target Roles", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _targetRoles.map((r) => Chip(
                      label: Text(r, style: const TextStyle(fontSize: 11)),
                      onDeleted: () => setState(() => _targetRoles.remove(r)),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _newRoleController, decoration: const InputDecoration(hintText: "Add role (e.g. AI Engineer)"))),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.racingGreen),
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

                  Text("Target Locations", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _locations.map((l) => Chip(
                      label: Text(l, style: const TextStyle(fontSize: 11)),
                      onDeleted: () => setState(() => _locations.remove(l)),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _newLocController, decoration: const InputDecoration(hintText: "Add location (e.g. Bangalore)"))),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.racingGreen),
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

                  Text("Excluded Companies", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _excludedCompanies.map((c) => Chip(
                      label: Text(c, style: const TextStyle(fontSize: 11, color: AppColors.errorLight)),
                      backgroundColor: AppColors.errorLight.withOpacity(0.08),
                      onDeleted: () => setState(() => _excludedCompanies.remove(c)),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _newExcludedController, decoration: const InputDecoration(hintText: "Add company to blacklist..."))),
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
                ]),

                const SizedBox(height: AppSpacing.s16),

                // 5. Immutable Verified Proof Points
                _buildSectionHeader("VERIFIED PROOF POINTS & PATENTS", secondaryTextColor),
                const SizedBox(height: AppSpacing.s8),
                _buildCard(cardBg, borderColor, [
                  Text("Ground Truth Facts (Zero Fabrication Source)", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _proofPointsController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: "List published patents, benchmarked research implementations, and verified certifications...",
                    ),
                  ),
                ]),

                const SizedBox(height: AppSpacing.s24),
                ElevatedButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGreen,
                    foregroundColor: AppColors.pureWhite,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  ),
                  child: const Text("Save Complete Profile", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

  Widget _buildCard(Color cardBg, Color borderColor, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
