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

  static const Map<String, String> _categoryDisplayNames = {
    "all": "All Categories",
    "personal": "Personal Contact",
    "education": "Education & Degrees",
    "work_auth": "Work Authorization",
    "technical": "Technical Skills",
    "behavioral": "Behavioral",
    "preferences": "Job Preferences",
    "demographics": "Demographics",
    "custom": "Custom Answers",
  };

  final List<String> _categories = [
    "all", "personal", "education", "work_auth", "technical", "behavioral", "preferences", "demographics", "custom"
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F0F10) : AppColors.surfaceLight,
        elevation: 0,
        title: Text(
          "Answers",
          style: TextStyle(fontFamily: 'Georgia', fontSize: 24, fontWeight: FontWeight.w400, color: primaryTextColor),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: "Add Entry",
            onPressed: () => _openEditModal(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: "Refresh Answers",
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
                    prefixIcon: Icon(Icons.search, size: 18, color: secondaryTextColor),
                    filled: true,
                    fillColor: cardBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: AppSpacing.s12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentGreen, width: 1.5)),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                // Category Pills (Wrapping with Human-Readable Labels)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        final label = _categoryDisplayNames[cat] ?? cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedCategory = cat);
                              _loadAnswers();
                            },
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: isSelected ? accentGreen : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                                border: Border.all(color: isSelected ? accentGreen : borderColor),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected ? (isDark ? const Color(0xFF0E0F0E) : Colors.white) : secondaryTextColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
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
                    ? Center(
                        child: Text("No entries found in Answer Bank.", style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        itemCount: _answers.length,
                        itemBuilder: (context, idx) {
                          final ans = _answers[idx];
                          final id = ans["id"] as int;
                          final isVerified = ans["is_verified"] == true;
                          final evidence = ans["supporting_evidence"] ?? "";
                          final allowReuse = ans["allow_reuse"] != false;
                          final usageCount = (ans["usage_count"] as int?) ?? 0;
                          final catKey = (ans["category"] ?? "").toString().toLowerCase();
                          final catLabel = _categoryDisplayNames[catKey] ?? (ans["display_category"] ?? catKey);

                          return MotionFadeSlide(
                            index: idx,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.s12),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor, width: 1.0),
                              ),
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header: Question + Verification Badge + Usage Count
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          ans["question_text"] ?? "",
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primaryTextColor),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.s8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (isVerified ? accentGreen : Colors.amber).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: (isVerified ? accentGreen : Colors.amber).withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(isVerified ? Icons.verified : Icons.lightbulb_outline, size: 10, color: isVerified ? accentGreen : Colors.amber),
                                            const SizedBox(width: 4),
                                            Text(
                                              isVerified ? "Verified Fact" : "AI Learned",
                                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isVerified ? accentGreen : Colors.amber),
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
                                      color: isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF3F4F1),
                                      borderRadius: BorderRadius.circular(8),
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
                                          Icon(Icons.shield_outlined, size: 12, color: secondaryTextColor),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text("Evidence: $evidence", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Footer: Human-readable category, Usage Count, Edit/Delete
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: accentGreen.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              catLabel,
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accentGreen),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Times used: $usageCount",
                                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 16),
                                            tooltip: "Edit Answer",
                                            onPressed: () => _openEditModal(existing: ans),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.errorLight),
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
                          );
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

  static const Map<String, String> _categories = {
    "personal": "Personal Contact",
    "education": "Education & Degrees",
    "work_auth": "Work Authorization",
    "technical": "Technical Skills",
    "behavioral": "Behavioral",
    "preferences": "Job Preferences",
    "demographics": "Demographics",
    "custom": "Custom Answers",
  };

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _qController = TextEditingController(text: ex?["question_text"] ?? "");
    _aController = TextEditingController(text: ex?["answer"] ?? "");
    _evidenceController = TextEditingController(text: ex?["supporting_evidence"] ?? "");
    _category = ex?["category"] ?? "education";
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primaryTextColor),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Expanded(
            child: ListView(
              children: [
                Text("QUESTION OR FORM PROMPT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(controller: _qController, decoration: const InputDecoration(hintText: "e.g. Highest degree completed")),
                const SizedBox(height: AppSpacing.s16),

                Text("CATEGORY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _categories.containsKey(_category) ? _category : "education",
                  items: _categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _category = val);
                  },
                ),
                const SizedBox(height: AppSpacing.s16),

                Text("ANSWER TEXT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(controller: _aController, maxLines: 3, decoration: const InputDecoration(hintText: "e.g. MTech Integrated CSE")),
                const SizedBox(height: AppSpacing.s16),

                Text("SUPPORTING EVIDENCE / CITATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(controller: _evidenceController, decoration: const InputDecoration(hintText: "e.g. Academic Transcript / facts.py")),
                const SizedBox(height: AppSpacing.s16),

                Row(
                  children: [
                    Checkbox(value: _isVerified, activeColor: accentGreen, onChanged: (v) => setState(() => _isVerified = v ?? true)),
                    Text("Verified Fact (Single source of truth)", style: TextStyle(fontSize: 12, color: primaryTextColor)),
                  ],
                ),
                Row(
                  children: [
                    Checkbox(value: _allowReuse, activeColor: accentGreen, onChanged: (v) => setState(() => _allowReuse = v ?? true)),
                    Text("Allow automatic reuse in ATS forms", style: TextStyle(fontSize: 12, color: primaryTextColor)),
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
                foregroundColor: isDark ? const Color(0xFF0E0F0E) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: const Text("Save Entry", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
