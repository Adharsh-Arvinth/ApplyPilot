import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class AnswerBankScreen extends StatefulWidget {
  const AnswerBankScreen({super.key});

  @override
  State<AnswerBankScreen> createState() => _AnswerBankScreenState();
}

class _AnswerBankScreenState extends State<AnswerBankScreen> {
  final _api = ApiClient();
  bool _loading = true;
  List<dynamic> _answers = [];
  String _search = "";
  String? _categoryFilter;

  final List<String> _categories = [
    "All",
    "personal",
    "education",
    "work_auth",
    "preferences",
    "technical",
    "behavioral",
    "custom"
  ];

  @override
  void initState() {
    super.initState();
    _fetchAnswers();
  }

  Future<void> _fetchAnswers() async {
    setState(() => _loading = true);
    try {
      final list = await _api.getAnswerBank(
        search: _search,
        category: _categoryFilter == "All" ? null : _categoryFilter,
      );
      if (mounted) {
        setState(() {
          _answers = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddEditModal({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final qCtrl = TextEditingController(text: existing?["question_text"] ?? "");
    final aCtrl = TextEditingController(text: existing?["answer"] ?? "");
    String mode = existing?["mode"] ?? "always_use";
    String category = existing?["category"] ?? "general";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
          title: Text(isEdit ? "Edit Answer" : "Add New Answer", style: const TextStyle(fontWeight: FontWeight.w500)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: qCtrl,
                  decoration: const InputDecoration(labelText: "Question / Label", isDense: true),
                ),
                const SizedBox(height: AppSpacing.s12),
                TextField(
                  controller: aCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: "Your Answer", isDense: true),
                ),
                const SizedBox(height: AppSpacing.s16),
                DropdownButtonFormField<String>(
                  value: mode,
                  decoration: const InputDecoration(labelText: "Reuse Mode", isDense: true),
                  items: const [
                    DropdownMenuItem(value: "always_use", child: Text("Always use automatically")),
                    DropdownMenuItem(value: "ask_each_time", child: Text("Ask me each time")),
                  ],
                  onChanged: (v) => setModalState(() => mode = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentLight),
              onPressed: () async {
                if (qCtrl.text.trim().isEmpty || aCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final payload = {
                  "question_text": qCtrl.text.trim(),
                  "answer": aCtrl.text.trim(),
                  "mode": mode,
                  "category": category,
                  "field_type": "text"
                };
                if (isEdit) {
                  await _api.updateAnswer(existing["id"], payload);
                } else {
                  await _api.createAnswer(payload);
                }
                _fetchAnswers();
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAnswer(int id) async {
    await _api.deleteAnswer(id);
    _fetchAnswers();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Answer Bank", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 22),
            onPressed: () => _showAddEditModal(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search question or answer...",
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                _search = val;
                _fetchAnswers();
              },
            ),
          ),
          // Category selector chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s8),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final selected = (_categoryFilter ?? "All") == cat;
                return ChoiceChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  selectedColor: isDark ? AppColors.accentDark.withOpacity(0.2) : AppColors.accentLight.withOpacity(0.12),
                  onSelected: (val) {
                    setState(() => _categoryFilter = cat);
                    _fetchAnswers();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _answers.isEmpty
                    ? Center(child: Text("No answers found.", style: theme.textTheme.bodyMedium))
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        itemCount: _answers.length,
                        itemBuilder: (ctx, i) {
                          final item = _answers[i];
                          final isAlways = item["mode"] == "always_use";

                          return Card(
                            margin: const EdgeInsets.only(bottom: AppSpacing.s12),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item["question_text"] ?? "",
                                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                                        decoration: BoxDecoration(
                                          color: isAlways
                                              ? AppColors.accentLight.withOpacity(0.1)
                                              : AppColors.warningLight.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(AppRadii.badge),
                                        ),
                                        child: Text(
                                          isAlways ? "Always Use" : "Ask Each Time",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isAlways ? AppColors.accentLight : AppColors.warningLight,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.s8),
                                  Text(
                                    item["answer"] ?? "",
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Used ${item["usage_count"] ?? 0} times • ${item["category"] ?? "general"}",
                                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            onPressed: () => _showAddEditModal(existing: item),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.blockedLight),
                                            onPressed: () => _deleteAnswer(item["id"]),
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
