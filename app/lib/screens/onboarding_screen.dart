import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final _api = ApiClient();
  int _currentStep = 0;

  final _urlCtrl = TextEditingController(text: ApiClient.defaultTailscaleUrl);
  final _tokenCtrl = TextEditingController(text: ApiClient.defaultAuthToken);

  @override
  void initState() {
    super.initState();
    _loadStoredCredentials();
  }

  Future<void> _loadStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString("server_url") ?? "";
    final token = prefs.getString("auth_token") ?? "";
    if (mounted) {
      if (url.isNotEmpty && !url.contains("100.x.y.z")) {
        _urlCtrl.text = url;
      } else {
        _urlCtrl.text = ApiClient.defaultTailscaleUrl;
      }
      if (token.isNotEmpty) {
        _tokenCtrl.text = token;
      } else {
        _tokenCtrl.text = ApiClient.defaultAuthToken;
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await _api.saveConnectionSettings(_urlCtrl.text, _tokenCtrl.text);
    await prefs.setBool("onboarding_complete", true);
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("ApplyPilot", style: theme.textTheme.titleMedium),
                  Text("Step ${_currentStep + 1} of 3", style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Step 1: Candidate Fact Review
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.s24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Profile & Verified Facts", style: theme.textTheme.displayMedium),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          "Your profile has been seeded from career-ops. These proof points form the strict immutable truth for all applications.",
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Candidate Profile & Fact Base", style: TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                const Text("Education: MTech Integrated CSE (Data Science), Example Institute (CGPA 8.10)"),
                                const SizedBox(height: 8),
                                const Text("Verified Achievements:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                const Text("• Patent 1: Smart Irrigation Controller", style: TextStyle(fontSize: 12)),
                                const Text("• Patent 2: Ultrasonic Presence Verification for Secure Sessions", style: TextStyle(fontSize: 12)),
                                const Text("• Code Retrieval Engine (18% NDCG@10 on MTEB)", style: TextStyle(fontSize: 12)),
                                const Text("• AWS Certified Solutions Architect", style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Step 2: Target Criteria & Safety Rails
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.s24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Filters & Safety Rails", style: theme.textTheme.displayMedium),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          "ApplyPilot executes under strict candidate-first safeguards.",
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                ListTile(
                                  dense: true,
                                  leading: Icon(Icons.check_circle_outline, color: AppColors.accentLight, size: 20),
                                  title: Text("Locations: India Only (Remote, BLR, MAA, HYD, PNQ, CJB, BOM, DEL)"),
                                ),
                                ListTile(
                                  dense: true,
                                  leading: Icon(Icons.check_circle_outline, color: AppColors.accentLight, size: 20),
                                  title: Text("Minimum CTC: ₹7,00,000 / yr (skips low pay roles)"),
                                ),
                                ListTile(
                                  dense: true,
                                  leading: Icon(Icons.check_circle_outline, color: AppColors.accentLight, size: 20),
                                  title: Text("Daily Application Cap: 100/day with jitter delays"),
                                ),
                                ListTile(
                                  dense: true,
                                  leading: Icon(Icons.shield_outlined, color: AppColors.accentLight, size: 20),
                                  title: Text("Dry-Run Default: Form preview only until you switch 'Go Live'"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Step 3: Server Connection (Tailscale)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.s24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Connect to PC", style: theme.textTheme.displayMedium),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          "Enter your Windows PC's Tailscale IP address to connect the mobile cockpit.",
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        TextField(
                          controller: _urlCtrl,
                          decoration: const InputDecoration(
                            labelText: "Tailscale PC Server URL",
                            hintText: "http://100.x.y.z:8000",
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        TextField(
                          controller: _tokenCtrl,
                          decoration: const InputDecoration(labelText: "Bearer Auth Token"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentLight,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  ),
                  onPressed: () {
                    if (_currentStep < 2) {
                      setState(() => _currentStep++);
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      );
                    } else {
                      _completeOnboarding();
                    }
                  },
                  child: Text(_currentStep < 2 ? "Continue" : "Start ApplyPilot"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
