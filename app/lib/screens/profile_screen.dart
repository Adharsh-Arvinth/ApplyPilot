import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _profile;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _githubCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _dailyCapCtrl = TextEditingController();

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
    _salaryCtrl.dispose();
    _dailyCapCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() => _loading = true);
    try {
      final p = await _api.getProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _nameCtrl.text = p["full_name"] ?? "";
          _emailCtrl.text = p["email"] ?? "";
          _phoneCtrl.text = p["phone"] ?? "";
          _linkedinCtrl.text = p["linkedin"] ?? "";
          _githubCtrl.text = p["github"] ?? "";
          _salaryCtrl.text = (p["min_salary_inr"] ?? 700000).toString();
          _dailyCapCtrl.text = (p["daily_cap"] ?? 100).toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    final payload = {
      "full_name": _nameCtrl.text.trim(),
      "email": _emailCtrl.text.trim(),
      "phone": _phoneCtrl.text.trim(),
      "linkedin": _linkedinCtrl.text.trim(),
      "github": _githubCtrl.text.trim(),
      "min_salary_inr": int.tryParse(_salaryCtrl.text.trim()) ?? 700000,
      "daily_cap": int.tryParse(_dailyCapCtrl.text.trim()) ?? 100,
    };
    await _api.updateProfile(payload);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile saved successfully.")));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile & Filters", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
        actions: [
          TextButton(onPressed: _saveProfile, child: const Text("Save")),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.s20),
              children: [
                Text("Personal & Contact", style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Column(
                      children: [
                        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Full Name", isDense: true)),
                        const SizedBox(height: AppSpacing.s12),
                        TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: "Email", isDense: true)),
                        const SizedBox(height: AppSpacing.s12),
                        TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "Phone", isDense: true)),
                        const SizedBox(height: AppSpacing.s12),
                        TextField(controller: _linkedinCtrl, decoration: const InputDecoration(labelText: "LinkedIn URL", isDense: true)),
                        const SizedBox(height: AppSpacing.s12),
                        TextField(controller: _githubCtrl, decoration: const InputDecoration(labelText: "GitHub URL", isDense: true)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                Text("Application Filters & Targets", style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _salaryCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Minimum Salary (₹ INR/yr)",
                            helperText: "Roles listing less will be skipped automatically",
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        TextField(
                          controller: _dailyCapCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Daily Application Cap",
                            helperText: "Target: 100 applications per day",
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.s24),

                // Immutable Proof Points Section
                Text("Verified Proof Points (Immutable Truth)", style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  "These facts are the only evidence the AI may cite in resumes and answers. Zero fabrication.",
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: AppSpacing.s12),
                Card(
                  color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Text(
                      _profile?["proof_points_text"] ?? "",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
