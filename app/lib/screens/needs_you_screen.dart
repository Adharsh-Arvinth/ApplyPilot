import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class NeedsYouScreen extends StatefulWidget {
  const NeedsYouScreen({super.key});

  @override
  State<NeedsYouScreen> createState() => _NeedsYouScreenState();
}

class _NeedsYouScreenState extends State<NeedsYouScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  List<dynamic> _items = [];
  Map<String, dynamic> _summary = {};
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, bool> _saveToBank = {};
  final Map<int, String> _modes = {};
  int _currentIndex = 0;
  bool _loadingGemini = false;
  List<dynamic> _geminiAnswers = [];

  @override
  void initState() {
    super.initState();
    _loadNeedsYou();
    _loadGeminiAnswers();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNeedsYou() async {
    setState(() => _loading = true);
    try {
      final itemsFuture = _api.getNeedsYou();
      final summaryFuture = _api.fetchNeedsYouSummary();
      final results = await Future.wait([itemsFuture, summaryFuture]);
      final items = results[0] as List<dynamic>;
      final summary = results[1] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _items = items;
          _summary = summary;
          if (_currentIndex >= items.length) {
            _currentIndex = items.isNotEmpty ? items.length - 1 : 0;
          }
          _loading = false;
        });
        for (final item in items) {
          final id = item["id"] as int;
          if (!_controllers.containsKey(id)) {
            _controllers[id] = TextEditingController(text: item["suggested_answer"] ?? item["answer"] ?? "");
            _saveToBank[id] = true;
            _modes[id] = "always_use";
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadGeminiAnswers() async {
    setState(() => _loadingGemini = true);
    try {
      final answers = await _api.getGeminiAnswers();
      if (mounted) {
        setState(() {
          _geminiAnswers = answers;
          _loadingGemini = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGemini = false);
    }
  }

  Future<void> _approveGeminiAnswer(int id) async {
    HapticFeedback.lightImpact();
    try {
      await _api.approveGeminiAnswer(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Answer approved and marked as 'Always Use'.")),
        );
      }
      _loadGeminiAnswers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Approval failed: $e")));
      }
    }
  }

  Future<void> _editGeminiAnswer(int id, String currentAnswer) async {
    final editController = TextEditingController(text: currentAnswer);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit AI Answer", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: editController,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "Enter corrected answer...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Save & Approve"),
          ),
        ],
      ),
    );

    if (confirmed == true && editController.text.trim().isNotEmpty) {
      try {
        await _api.editGeminiAnswer(id, editController.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Answer updated and approved.")),
          );
        }
        _loadGeminiAnswers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Edit failed: $e")));
        }
      }
    }
  }

  Future<void> _rejectGeminiAnswer(int id, String questionText) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Reject AI Answer?",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.errorCoral),
        ),
        content: Text(
          "This will delete the answer from the Answer Bank and flag any applications that used it.\n\nNext time this question appears, it will be sent directly to you.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorCoral, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reject & Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.rejectGeminiAnswer(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("AI answer deleted and affected applications flagged.")),
          );
        }
        _loadGeminiAnswers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Rejection failed: $e")));
        }
      }
    }
  }

  Future<void> _resolveItem(int id) async {
    HapticFeedback.mediumImpact();
    final answerText = _controllers[id]?.text.trim() ?? "";
    if (answerText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please provide an answer before submitting.")),
      );
      return;
    }

    try {
      await _api.resolveNeedsYou(
        id,
        answerText,
        saveToBank: _saveToBank[id] ?? true,
        mode: _modes[id] ?? "always_use",
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Answer saved! Application resumed automatically.")),
      );
      _loadNeedsYou();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to resolve: $e")));
    }
  }

  Future<void> _dismissItem(int id) async {
    HapticFeedback.lightImpact();
    try {
      await _api.dismissNeedsYou(id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question skipped.")));
      _loadNeedsYou();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _rejectItem(int id, {bool blockCompany = false, String reason = "Rejected by candidate"}) async {
    HapticFeedback.mediumImpact();
    try {
      final res = await _api.rejectNeedsYou(id, blockCompany: blockCompany, reason: reason);
      final company = res["company"] ?? "Application";
      final msg = blockCompany
          ? "Rejected & permanently blocked '$company' from future job discovery."
          : "Rejected application for '$company'.";
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: blockCompany ? AppColors.errorCoral : AppColors.racingGreen,
          content: Text(msg),
        ));
      }
      _loadNeedsYou();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _showRejectDialog(dynamic item) {
    final id = item["id"] as int;
    final company = item["company"] ?? "this company";
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coral = AppColors.getSemanticColor("coral", isDark);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 22, color: coral),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  "Reject $company",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              "Choose whether to decline only this specific application, or permanently block $company from your future job search.",
              style: TextStyle(fontSize: 12, height: 1.4, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
            ),
            const SizedBox(height: AppSpacing.s16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: coral.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.cancel_outlined, size: 20, color: coral),
              ),
              title: const Text("Reject this application only", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text("Skips this position. You can still apply to other roles at this company.", style: TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _rejectItem(id, blockCompany: false);
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.errorCoral.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.block_outlined, size: 20, color: AppColors.errorCoral),
              ),
              title: Text("Reject & Block $company", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.errorCoral)),
              subtitle: Text("Permanently adds $company to your excluded companies list. ApplyPilot will never scan or apply there again.", style: const TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _rejectItem(id, blockCompany: true);
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateForController(TextEditingController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month + 6),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: "SELECT GRADUATION / AVAILABILITY DATE",
    );
    if (picked != null) {
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      final formatted = "${months[picked.month - 1]} ${picked.year}";
      setState(() {
        controller.text = formatted;
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
    final coral = AppColors.getSemanticColor("coral", isDark);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF0F0F10) : AppColors.surfaceLight,
          elevation: 0,
          title: Row(
            children: [
              Text(
                "Needs You",
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2C2C2E)),
                ),
                child: const Text(
                  "Autonomous Mode Active",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF8E8E93)),
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: "Refresh Inbox",
              onPressed: () {
                _loadNeedsYou();
                _loadGeminiAnswers();
              },
            ),
          ],
          bottom: TabBar(
            indicatorColor: accentGreen,
            labelColor: primaryTextColor,
            unselectedLabelColor: secondaryTextColor,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Candidate Questions"),
                    if (_items.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: coral,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${_items.length}",
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("AI Answered"),
                    if (_geminiAnswers.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentGreen,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${_geminiAnswers.length}",
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Candidate questions
            _loading
                ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
                : _items.isEmpty
                    ? _buildEmptyState(isDark, primaryTextColor, secondaryTextColor, accentGreen, cardBg, borderColor)
                    : _buildQuestionCarousel(isDark, primaryTextColor, secondaryTextColor, accentGreen, cardBg, borderColor, coral),
            
            // Tab 2: AI Answered
            _buildAiAnsweredTab(isDark, primaryTextColor, secondaryTextColor, accentGreen, cardBg, borderColor, coral),
          ],
        ),
      ),
    );
  }

  Widget _buildAiAnsweredTab(
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
    Color accentColor,
    Color cardBg,
    Color borderColor,
    Color coral,
  ) {
    if (_loadingGemini) {
      return Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentColor));
    }

    if (_geminiAnswers.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor.withOpacity(0.3)),
                ),
                child: Icon(Icons.auto_awesome, size: 32, color: accentColor),
              ),
              const SizedBox(height: AppSpacing.s16),
              Text(
                "No Pending AI Answers",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primaryColor),
              ),
              const SizedBox(height: AppSpacing.s8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(
                  "When Gemini auto-answers unlisted form questions truthfully from your locked facts, they will appear here for your review and approval.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.4, color: secondaryColor),
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              OutlinedButton.icon(
                onPressed: _loadGeminiAnswers,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Refresh List"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: borderColor),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: _geminiAnswers.length,
      itemBuilder: (context, index) {
        final item = _geminiAnswers[index] as Map<String, dynamic>;
        final id = item["id"] as int;
        final question = item["question"] ?? "";
        final answer = item["answer"] ?? "";
        final company = item["company"] ?? "Various";
        final role = item["role"] ?? "";
        final confidence = (item["confidence"] as num?)?.toDouble() ?? 0.95;
        final factsUsed = (item["facts_used"] as List<dynamic>?) ?? [];

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.s16),
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Company/Role + Confidence Tag
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "$company • ${role.isNotEmpty ? role : 'Form Question'}",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accentColor.withOpacity(0.3), width: 0.5),
                    ),
                    child: Text(
                      "${(confidence * 100).toInt()}% match",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accentColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),

              // Question Text
              Text(
                question,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryColor),
              ),
              const SizedBox(height: AppSpacing.s12),

              // Gemini Answer Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 13, color: accentColor),
                        const SizedBox(width: 5),
                        Text(
                          "GEMINI ANSWER",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: accentColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      answer,
                      style: TextStyle(fontSize: 13, height: 1.4, color: primaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s12),

              // Facts Used Chips
              if (factsUsed.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: factsUsed.map<Widget>((fact) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor, width: 0.5),
                      ),
                      child: Text(
                        "Fact: $fact",
                        style: TextStyle(fontSize: 10, color: secondaryColor),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],

              // Actions: Approve, Edit, Reject
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () => _approveGeminiAnswer(id),
                      icon: const Icon(Icons.check, size: 15),
                      label: const Text("Approve · Always use", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: isDark ? AppColors.forestInk : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _editGeminiAnswer(id, answer),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Edit", style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _rejectGeminiAnswer(id, question),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: coral,
                      side: BorderSide(color: coral.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Reject", style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
    Color accentColor,
    Color cardBg,
    Color borderColor,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
              ),
              child: Icon(Icons.check_circle_outline, size: 38, color: accentColor),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              "Inbox Zero · No Pending Questions",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primaryColor),
            ),
            const SizedBox(height: AppSpacing.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                "All active applications are moving forward autonomously without blockers.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.45, color: secondaryColor),
              ),
            ),
            const SizedBox(height: AppSpacing.s24),
            OutlinedButton.icon(
              onPressed: _loadNeedsYou,
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s12),
              ),
              icon: Icon(Icons.refresh, size: 16, color: accentColor),
              label: const Text("Re-run Auto-Resolve", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: AppSpacing.s32),
            // Quiet metrics row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildQuietSummaryChip(
                  "Auto-resolved",
                  "${_summary['auto_processed_count'] ?? 0}",
                  accentColor,
                  cardBg,
                  borderColor,
                  primaryColor,
                  secondaryColor,
                ),
                const SizedBox(width: AppSpacing.s12),
                _buildQuietSummaryChip(
                  "Candidate confirmed",
                  "${_summary['resolved_count'] ?? 0}",
                  primaryColor,
                  cardBg,
                  borderColor,
                  primaryColor,
                  secondaryColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuietSummaryChip(
    String label,
    String value,
    Color dotColor,
    Color bg,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, color: textSecondary)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary)),
        ],
      ),
    );
  }

  Widget _buildQuestionCarousel(
    bool isDark,
    Color primaryColor,
    Color secondaryColor,
    Color accentColor,
    Color cardBg,
    Color borderColor,
    Color coral,
  ) {
    if (_currentIndex >= _items.length) {
      _currentIndex = _items.isNotEmpty ? _items.length - 1 : 0;
    }
    final item = _items[_currentIndex];
    final id = item["id"] as int;
    final controller = _controllers[id] ?? TextEditingController();
    final options = (item["options"] as List<dynamic>?) ?? [];
    final questionText = (item["question_text"] ?? "").toString();
    final qLower = questionText.toLowerCase();
    final isDateQuestion = (item["field_type"] == "date") ||
        qLower.contains("graduat") ||
        qLower.contains("passing year") ||
        qLower.contains("completion year");
    final isSalaryQuestion = (item["field_type"] == "salary") ||
        qLower.contains("salary") ||
        qLower.contains("ctc") ||
        qLower.contains("compensation") ||
        qLower.contains("expectation");

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Carousel Top Counter & Navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Question ${_currentIndex + 1} of ${_items.length}",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryColor),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 20),
                        tooltip: "Previous question",
                        onPressed: _currentIndex > 0
                            ? () => setState(() => _currentIndex--)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20),
                        tooltip: "Next question",
                        onPressed: _currentIndex < _items.length - 1
                            ? () => setState(() => _currentIndex++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),

              // Main Question Card (16px radius, 1px border, no shadow)
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                padding: const EdgeInsets.all(AppSpacing.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Target Header
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item["company"] ?? "Target Company",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item["role"] ?? "Application",
                                style: TextStyle(fontSize: 12, color: secondaryColor),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: accentColor.withOpacity(0.25)),
                          ),
                          child: Text(
                            (item["field_type"] ?? "text").toString().toUpperCase(),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accentColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.s16),

                    // Question Text
                    Text(
                      "QUESTION",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: secondaryColor),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      questionText,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35, color: primaryColor),
                    ),
                    const SizedBox(height: AppSpacing.s20),

                    // FIELD TYPE AWARE INPUTS
                    // Case 1: Date / Graduation Date
                    if (isDateQuestion) ...[
                      Text("EXPECTED DATE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryColor)),
                      const SizedBox(height: AppSpacing.s8),
                      InkWell(
                        onTap: () => _pickDateForController(controller),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, size: 18, color: accentColor),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  controller.text.isEmpty ? "Tap to select graduation / completion date" : controller.text,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: controller.text.isEmpty ? FontWeight.w400 : FontWeight.w600,
                                    color: controller.text.isEmpty ? secondaryColor : primaryColor,
                                  ),
                                ),
                              ),
                              Icon(Icons.arrow_drop_down, color: secondaryColor),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                    ]

                    // Case 2: Salary / Compensation
                    else if (isSalaryQuestion) ...[
                      Text("COMPENSATION EXPECTATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryColor)),
                      const SizedBox(height: AppSpacing.s8),
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          prefixText: "₹ ",
                          hintText: "e.g. 8,00,000 or 8-12 LPA",
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Wrap(
                        spacing: 8,
                        children: ["₹7,00,000", "₹8,00,000 - ₹12,00,000", "₹12,00,000+", "As per company standard"].map((sug) {
                          return ActionChip(
                            label: Text(sug, style: TextStyle(fontSize: 11, color: primaryColor)),
                            backgroundColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                            side: BorderSide(color: borderColor),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => controller.text = sug);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                    ]

                    // Case 3: Multiple choice (options provided)
                    else if (options.isNotEmpty) ...[
                      Text("SELECT AN OPTION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryColor)),
                      const SizedBox(height: AppSpacing.s8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: options.map((opt) {
                          final optStr = opt.toString();
                          final isSelected = controller.text == optStr;
                          return ChoiceChip(
                            label: Text(
                              optStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                color: isSelected ? accentColor : primaryColor,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: accentColor.withOpacity(0.12),
                            backgroundColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                            side: BorderSide(color: isSelected ? accentColor : borderColor),
                            onSelected: (selected) {
                              if (selected) {
                                HapticFeedback.selectionClick();
                                setState(() => controller.text = optStr);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                    ]

                    // Case 4: Free text
                    else ...[
                      Text("YOUR ANSWER", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryColor)),
                      const SizedBox(height: AppSpacing.s8),
                      TextField(
                        controller: controller,
                        maxLines: (item["field_type"] == "textarea") ? 4 : 2,
                        decoration: InputDecoration(
                          hintText: "Enter your answer...",
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                    ],

                    // Prominent "Remember this answer" toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF8F9F8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Remember this answer",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryColor),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Save to Answer Bank for future applications",
                                  style: TextStyle(fontSize: 11, color: secondaryColor),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _saveToBank[id] ?? true,
                            activeColor: accentColor,
                            onChanged: (val) => setState(() => _saveToBank[id] = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s20),

                    // Primary Action: Save & Resume Application
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _resolveItem(id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: isDark ? const Color(0xFF0E0F0E) : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: const Text("Save & Resume Application", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s12),

                    // Secondary Action Buttons: Reject & Skip
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _showRejectDialog(item),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: coral,
                              side: BorderSide(color: coral.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Reject Role", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: TextButton(
                            onPressed: () => _dismissItem(id),
                            style: TextButton.styleFrom(
                              foregroundColor: secondaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Skip Question", style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
