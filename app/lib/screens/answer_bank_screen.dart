import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/hallmark_tokens.dart';
import '../core/motion.dart';

class AnswerBankScreen extends StatefulWidget {
  const AnswerBankScreen({super.key});

  @override
  State<AnswerBankScreen> createState() => _AnswerBankScreenState();
}

class _AnswerBankScreenState extends State<AnswerBankScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  String _searchQuery = "";
  String _selectedCategory = "all";
  bool? _verifiedFilter;
  List<dynamic> _answers = [];

  final List<String> _categories = [
    "all", "personal", "education", "work_auth", "technical", "behavioral", "preferences", "custom"
  ];

  @override
  void initState() {
    super.initState();
    _loadAnswers();
  }

  Future<void> _loadAnswers() async {
    setState(() => _loading = true);
    try {
      final category = _selectedCategory == "all" ? null : _selectedCategory;
      final answers = await _api.getAnswerBank(
        search: _searchQuery.isEmpty ? null : _searchQuery,
        category: category,
        isVerified: _verifiedFilter,
      );
      if (mounted) {
        setState(() {
          _answers = answers;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEditModal({dynamic existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AnswerEditSheet(existing: existing, onSaved: _loadAnswers),
    );
  }

  Future<void> _deleteAnswer(int id) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Answer"),
        content: const Text("Are you sure you want to remove this answer entry from your Answer Bank?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorLight),
            child: const Text("Delete", style: TextStyle(color: AppColors.pureWhite)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.deleteAnswer(id);
        _loadAnswers();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Answer Bank",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Add Entry",
            onPressed: () => _openEditModal(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnswers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s12),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) {
                    _searchQuery = val;
                    _loadAnswers();
                  },
                  decoration: InputDecoration(
                    hintText: "Search questions, answers, or categories...",
                    hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                    prefixIcon: Icon(Icons.search, size: 20, color: secondaryTextColor),
                    filled: true,
                    fillColor: cardBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: AppSpacing.s12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.control), borderSide: BorderSide(color: borderColor)),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                // Category Pills (Wrapping)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return InkWell(
                        onTap: () {
                          setState(() => _selectedCategory = cat);
                          _loadAnswers();
                        },
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected ? accentGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            border: Border.all(color: isSelected ? accentGreen : borderColor),
                          ),
                          child: Text(
                            cat.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppColors.pureWhite : secondaryTextColor,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Answers List
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
                : _answers.isEmpty
                    ? Center(child: Text("No entries found in Answer Bank.", style: TextStyle(color: secondaryTextColor)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        itemCount: _answers.length,
                        itemBuilder: (context, idx) {
                          final ans = _answers[idx];
                          final id = ans["id"] as int;
                          final isVerified = ans["is_verified"] == true;
                          final evidence = ans["supporting_evidence"] ?? "";
                          final allowReuse = ans["allow_reuse"] != false;

                          return MotionFadeSlide(
                            index: idx,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.s12),
                              decoration: BoxDecoration(
                                color: isDark ? HallmarkConsole.panel : cardBg,
                                borderRadius: BorderRadius.circular(HallmarkConsole.radiusPanel),
                                border: Border.all(color: isDark ? HallmarkConsole.rule : borderColor, width: HallmarkConsole.ruleWidth),
                              ),
                              child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: Question + Verification Badge
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          ans["question_text"] ?? "",
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryTextColor),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.s8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (isVerified ? AppColors.successLight : AppColors.warningLight).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(AppRadii.badge),
                                          border: Border.all(color: (isVerified ? AppColors.successLight : AppColors.warningLight).withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(isVerified ? Icons.verified : Icons.lightbulb_outline, size: 11, color: isVerified ? AppColors.successLight : AppColors.warningLight),
                                            const SizedBox(width: 4),
                                            Text(
                                              isVerified ? "Verified Fact" : "AI Suggestion",
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isVerified ? AppColors.successLight : AppColors.warningLight),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.s8),

                                  // Answer Body
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(AppSpacing.s12),
                                    decoration: BoxDecoration(
                                      color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                                      borderRadius: BorderRadius.circular(AppRadii.control),
                                    ),
                                    child: Text(
                                      ans["answer"] ?? "",
                                      style: TextStyle(fontSize: 13, height: 1.4, color: primaryTextColor),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s8),

                                  // Evidence & Source
                                  if (evidence.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.shield_outlined, size: 13, color: secondaryTextColor),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text("Evidence: $evidence", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Footer: Category, Reuse Permission, Edit/Delete
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: HallmarkConsole.tagDecoration(),
                                            child: Text(
                                              ans['category'].toString().toLowerCase(),
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: secondaryTextColor),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            allowReuse ? "Auto-reuse permitted" : "Confirm before use",
                                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            tooltip: "Edit Answer",
                                            onPressed: () => _openEditModal(existing: ans),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.errorLight),
                                            tooltip: "Delete Answer",
                                            onPressed: () => _deleteAnswer(id),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ));
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _AnswerEditSheet extends StatefulWidget {
  final dynamic existing;
  final VoidCallback onSaved;

  const _AnswerEditSheet({this.existing, required this.onSaved});

  @override
  State<_AnswerEditSheet> createState() => _AnswerEditSheetState();
}

class _AnswerEditSheetState extends State<_AnswerEditSheet> {
  final ApiClient _api = ApiClient();
  late TextEditingController _qController;
  late TextEditingController _aController;
  late TextEditingController _evidenceController;
  late String _category;
  late String _mode;
  late bool _isVerified;
  late bool _allowReuse;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _qController = TextEditingController(text: ex?["question_text"] ?? "");
    _aController = TextEditingController(text: ex?["answer"] ?? "");
    _evidenceController = TextEditingController(text: ex?["supporting_evidence"] ?? "");
    _category = ex?["category"] ?? "general";
    _mode = ex?["mode"] ?? "always_use";
    _isVerified = ex?["is_verified"] ?? true;
    _allowReuse = ex?["allow_reuse"] ?? true;
  }

  @override
  void dispose() {
    _qController.dispose();
    _aController.dispose();
    _evidenceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = _qController.text.trim();
    final a = _aController.text.trim();
    if (q.isEmpty || a.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question and answer are required.")));
      return;
    }

    final data = {
      "question_text": q,
      "answer": a,
      "category": _category,
      "mode": _mode,
      "field_type": "text",
      "supporting_evidence": _evidenceController.text.trim(),
      "is_verified": _isVerified,
      "allow_reuse": _allowReuse,
      "source": widget.existing?["source"] ?? "manual_entry",
    };

    try {
      if (widget.existing != null) {
        await _api.updateAnswer(widget.existing["id"], data);
      } else {
        await _api.createAnswer(data);
      }
      widget.onSaved();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.existing != null ? "Edit Answer Bank Entry" : "New Candidate Fact",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Expanded(
            child: ListView(
              children: [
                Text("QUESTION OR FIELD LABEL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(controller: _qController, decoration: const InputDecoration(hintText: "e.g. Years of Python experience")),
                const SizedBox(height: AppSpacing.s16),

                Text("ANSWER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(controller: _aController, maxLines: 3, decoration: const InputDecoration(hintText: "e.g. 2+ years through academic R&D")),
                const SizedBox(height: AppSpacing.s16),

                Text("SUPPORTING EVIDENCE / CITATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(controller: _evidenceController, decoration: const InputDecoration(hintText: "e.g. Published patent #202441058291")),
                const SizedBox(height: AppSpacing.s16),

                Row(
                  children: [
                    Checkbox(value: _isVerified, activeColor: accentGreen, onChanged: (v) => setState(() => _isVerified = v ?? true)),
                    Text("Verified Fact (High confidence truth)", style: TextStyle(fontSize: 12, color: primaryTextColor)),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(value: _allowReuse, activeColor: accentGreen, onChanged: (v) => setState(() => _allowReuse = v ?? true)),
                    Text("Allow Automatic Reuse in ATS forms", style: TextStyle(fontSize: 12, color: primaryTextColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGreen,
                foregroundColor: AppColors.pureWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              ),
              child: const Text("Save Entry", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
