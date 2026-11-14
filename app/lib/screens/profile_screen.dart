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
  List<dynamic> _candidateRecords = [];
  String _selectedRecordCategory = "all";

  final TextEditingController _newRoleController = TextEditingController();
  final TextEditingController _newLocController = TextEditingController();
  final TextEditingController _newExcludedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadCandidateRecords();
  }

  Future<void> _loadCandidateRecords() async {
    try {
      final records = await _api.fetchCandidateRecords();
      if (mounted) {
        setState(() {
          _candidateRecords = records;
        });
      }
    } catch (_) {}
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

  void _openAddEditRecordModal({Map<String, dynamic>? record}) {
    final isEditing = record != null;
    final catController = TextEditingController(text: record?["category"] ?? "education");
    final subcatController = TextEditingController(text: record?["subcategory"] ?? "university");
    final titleController = TextEditingController(text: record?["title"] ?? "");
    final descController = TextEditingController(text: record?["description"] ?? "");
    final evidenceController = TextEditingController(text: record?["source_evidence"] ?? "");
    String status = record?["verification_status"] ?? "verified";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
            final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
            final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
            final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;

            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.s20,
                right: AppSpacing.s20,
                top: AppSpacing.s20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.s24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isEditing ? "Edit Candidate Record" : "Add Verifiable Proof Point",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primaryTextColor),
                        ),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    DropdownButtonFormField<String>(
                      value: catController.text,
                      decoration: const InputDecoration(labelText: "Category"),
                      items: const [
                        DropdownMenuItem(value: "education", child: Text("Education")),
                        DropdownMenuItem(value: "patents", child: Text("Patents")),
                        DropdownMenuItem(value: "projects", child: Text("Projects / Benchmarks")),
                        DropdownMenuItem(value: "certifications", child: Text("Certifications")),
                        DropdownMenuItem(value: "technical_skills", child: Text("Technical Skills")),
                        DropdownMenuItem(value: "work_experience", child: Text("Work Experience")),
                        DropdownMenuItem(value: "achievements", child: Text("Achievements")),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => catController.text = val);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      controller: subcatController,
                      decoration: const InputDecoration(
                        labelText: "Subcategory / Tag (e.g. university, published_patent, system_benchmark)",
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: "Title / Name"),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: "Description & Specific Facts"),
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      controller: evidenceController,
                      decoration: const InputDecoration(labelText: "Verification Evidence / Credential Link / Patent #"),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: "Verification Status"),
                      items: const [
                        DropdownMenuItem(value: "verified", child: Text("Verified Ground Truth")),
                        DropdownMenuItem(value: "pending_verification", child: Text("Pending Verification")),
                        DropdownMenuItem(value: "unverified", child: Text("Unverified")),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => status = val);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: AppColors.pureWhite,
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
                        ),
                        onPressed: () async {
                          final payload = {
                            "category": catController.text,
                            "subcategory": subcatController.text.trim(),
                            "title": titleController.text.trim(),
                            "description": descController.text.trim(),
                            "source_evidence": evidenceController.text.trim(),
                            "verification_status": status,
                            "is_verified": status == "verified",
                          };
                          Navigator.pop(ctx);
                          if (isEditing) {
                            await _api.updateCandidateRecord(record["id"] as int, payload);
                          } else {
                            await _api.createCandidateRecord(payload);
                          }
                          _loadCandidateRecords();
                        },
                        child: Text(isEditing ? "Update Record" : "Save Verifiable Record", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteRecord(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Record?"),
        content: const Text("Are you sure you want to remove this proof point?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: AppColors.errorLight))),
        ],
      ),
    );
    if (confirmed == true) {
      await _api.deleteCandidateRecord(id);
      _loadCandidateRecords();
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

                // 5. Structured Verifiable Candidate Records
                Row(
                  children: [
                    _buildSectionHeader("STRUCTURED CANDIDATE INTELLIGENCE", secondaryTextColor),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.add, size: 16, color: AppColors.racingGreen),
                      label: const Text("Add Proof Point", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.racingGreen)),
                      onPressed: () => _openAddEditRecordModal(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),

                // Category Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      "all", "education", "patents", "projects", "certifications", "technical_skills", "achievements"
                    ].map((cat) {
                      final isSel = _selectedRecordCategory == cat;
                      final label = cat == "all"
                          ? "All (${_candidateRecords.length})"
                          : "${cat[0].toUpperCase()}${cat.substring(1).replaceAll('_', ' ')}";
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(label, style: TextStyle(fontSize: 11, color: isSel ? AppColors.pureWhite : primaryTextColor)),
                          selected: isSel,
                          selectedColor: accentGreen,
                          backgroundColor: cardBg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _selectedRecordCategory = cat);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),

                // Render Filtered Records
                ..._candidateRecords.where((r) {
                  if (_selectedRecordCategory == "all") return true;
                  return r["category"] == _selectedRecordCategory;
                }).map((record) {
                  final isVerified = record["is_verified"] == true;
                  final subcat = record["subcategory"] ?? "";
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.s10),
                    padding: const EdgeInsets.all(AppSpacing.s14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(color: isVerified ? brassColor.withOpacity(0.35) : borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isVerified ? AppColors.successEmerald : AppColors.mutedBrass).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(AppRadii.badge),
                              ),
                              child: Text(
                                subcat.toString().replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isVerified ? AppColors.successEmerald : brassColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            if (isVerified)
                              const Icon(Icons.verified, size: 14, color: AppColors.successEmerald),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: secondaryTextColor,
                              onPressed: () => _openAddEditRecordModal(record: record),
                            ),
                            const SizedBox(width: AppSpacing.s10),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: AppColors.errorLight,
                              onPressed: () => _deleteRecord(record["id"] as int),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          record["title"] ?? "",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primaryTextColor),
                        ),
                        if ((record["description"] ?? "").toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            record["description"] ?? "",
                            style: TextStyle(fontSize: 12, height: 1.35, color: secondaryTextColor),
                          ),
                        ],
                        if ((record["source_evidence"] ?? "").toString().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.link, size: 12, color: brassColor),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  "Evidence: ${record['source_evidence']}",
                                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: brassColor),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: AppSpacing.s16),

                // 6. Immutable Verified Proof Points Text
                _buildSectionHeader("PROOF POINTS QUICK SUMMARY (PROMPT INJECTION)", secondaryTextColor),
                const SizedBox(height: AppSpacing.s8),
                _buildCard(cardBg, borderColor, [
                  Text("Ground Truth Prompt Ingestion (Immutable Baseline)", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
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
