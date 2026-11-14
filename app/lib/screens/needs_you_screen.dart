import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class NeedsYouScreen extends StatefulWidget {
  const NeedsYouScreen({super.key});

  @override
  State<NeedsYouScreen> createState() => _NeedsYouScreenState();
}

class _NeedsYouScreenState extends State<NeedsYouScreen> {
  final _api = ApiClient();
  bool _loading = true;
  List<dynamic> _items = [];
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, bool> _saveToBank = {};

  // Quick-answer chips strictly grounded in candidate's verified proof points
  final List<String> _proofPointChips = [
    "Yes, authorized to work in India with no sponsorship needed.",
    "MTech Integrated CSE (Data Science), VIT Vellore (CGPA 7.62/10).",
    "Inventor of 2 published patents (Driver Accident Predictor & Doppler Session Guard).",
    "Built Agentic Code Intelligence benchmarked at 25.59% NDCG@10 on MTEB.",
    "AWS Certified Solutions Architect with Python/PyTorch/FastAPI experience.",
    "Immediate / Negotiable for academic schedule.",
    "Expected CTC: ₹7,00,000 per year minimum, negotiable."
  ];

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchItems() async {
    setState(() => _loading = true);
    try {
      final items = await _api.getNeedsYou();
      if (mounted) {
        setState(() {
          _items = items;
          for (var item in items) {
            final id = item["id"] as int;
            if (!_controllers.containsKey(id)) {
              _controllers[id] = TextEditingController(text: item["suggested_answer"] ?? "");
              _saveToBank[id] = true;
            }
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resolveItem(int id) async {
    final text = _controllers[id]?.text.trim() ?? "";
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide an answer.")));
      return;
    }

    try {
      await _api.resolveNeedsYou(id, text, saveToBank: _saveToBank[id] ?? true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Answer saved! Application resumed automatically.")),
      );
      _fetchItems();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Needs You", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _fetchItems),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.done_all_rounded,
                          size: 40,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                        const SizedBox(height: AppSpacing.s16),
                        Text("Inbox Clear", style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          "All eligible applications have been answered from the Answer Bank. No human intervention needed.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.s20),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final id = item["id"] as int;
                    final controller = _controllers[id]!;
                    final options = (item["options"] as List<dynamic>?) ?? [];

                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s20),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Company & Role badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item["company"] ?? "",
                                  style: theme.textTheme.titleLarge?.copyWith(fontSize: 16),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s8,
                                    vertical: AppSpacing.s4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.warningLight.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(AppRadii.badge),
                                  ),
                                  child: Text(
                                    "Awaiting Input",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppColors.warningDark : AppColors.warningLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              item["role"] ?? "",
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s16),
                            const Divider(height: 1),
                            const SizedBox(height: AppSpacing.s16),

                            // Question
                            Text("Question:", style: theme.textTheme.labelSmall),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              item["question_text"] ?? "",
                              style: theme.textTheme.titleMedium?.copyWith(fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: AppSpacing.s16),

                            // Option Chips if multiple choice
                            if (options.isNotEmpty) ...[
                              Text("Options from form:", style: theme.textTheme.labelSmall),
                              const SizedBox(height: AppSpacing.s8),
                              Wrap(
                                spacing: AppSpacing.s8,
                                runSpacing: AppSpacing.s8,
                                children: options.map((opt) {
                                  return ActionChip(
                                    label: Text(opt.toString()),
                                    onPressed: () {
                                      setState(() {
                                        controller.text = opt.toString();
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: AppSpacing.s16),
                            ],

                            // Proof Point Quick-fill Chips
                            Text("Quick Answer from Verified Facts:", style: theme.textTheme.labelSmall),
                            const SizedBox(height: AppSpacing.s8),
                            Wrap(
                              spacing: AppSpacing.s8,
                              runSpacing: AppSpacing.s8,
                              children: _proofPointChips.take(4).map((chipText) {
                                return ActionChip(
                                  label: Text(
                                    chipText.length > 36 ? "${chipText.substring(0, 36)}..." : chipText,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      controller.text = chipText;
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: AppSpacing.s16),

                            // Input Box
                            TextField(
                              controller: controller,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: "Type answer here...",
                                filled: true,
                                fillColor: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.control),
                                  borderSide: BorderSide(
                                    color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s12),

                            // Save to Answer Bank Checkbox
                            Row(
                              children: [
                                Checkbox(
                                  value: _saveToBank[id] ?? true,
                                  onChanged: (v) => setState(() => _saveToBank[id] = v ?? true),
                                ),
                                Text(
                                  "Remember in Answer Bank (never ask again)",
                                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s12),

                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.accentLight,
                                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadii.control),
                                  ),
                                ),
                                onPressed: () => _resolveItem(id),
                                child: const Text(
                                  "Save & Auto-Resume",
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
