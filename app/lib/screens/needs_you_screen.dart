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
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, bool> _saveToBank = {};
  final Map<int, String> _modes = {};

  @override
  void initState() {
    super.initState();
    _loadNeedsYou();
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
      final items = await _api.getNeedsYou();
      if (mounted) {
        setState(() {
          _items = items;
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

  Future<void> _resolveItem(int id) async {
    HapticFeedback.mediumImpact();
    final answerText = _controllers[id]?.text.trim() ?? "";
    if (answerText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide an answer before submitting.")));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question dismissed.")));
      _loadNeedsYou();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
          "Needs You Inbox",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNeedsYou,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.s20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentGreen.withOpacity(0.08),
                          ),
                          child: Icon(Icons.done_all, size: 48, color: accentGreen),
                        ),
                        const SizedBox(height: AppSpacing.s20),
                        Text(
                          "All Caught Up",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryTextColor),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          "The auto-apply engine has all the candidate intelligence it needs. Any new custom form questions will arrive here for your 1-tap review.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, height: 1.4, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  itemCount: _items.length,
                  itemBuilder: (context, idx) {
                    final item = _items[idx];
                    final id = item["id"] as int;
                    final controller = _controllers[id];
                    final options = (item["options"] as List<dynamic>?) ?? [];

                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        border: Border.all(color: brassColor.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Company + Role Badge
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            decoration: BoxDecoration(
                              color: brassColor.withOpacity(0.08),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.assignment_late_outlined, size: 18, color: brassColor),
                                const SizedBox(width: AppSpacing.s8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item["company"] ?? "Unknown Company",
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primaryTextColor),
                                      ),
                                      Text(
                                        item["role"] ?? "Target Position",
                                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(AppRadii.badge),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    (item["field_type"] ?? "text").toString().toUpperCase(),
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "QUESTION FROM ATS FORM",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: secondaryTextColor),
                                ),
                                const SizedBox(height: AppSpacing.s6),
                                Text(
                                  item["question_text"] ?? "",
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor),
                                ),
                                const SizedBox(height: AppSpacing.s16),

                                // If dropdown options exist, display quick chips
                                if (options.isNotEmpty) ...[
                                  Text(
                                    "SELECT OPTION",
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: secondaryTextColor),
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  Wrap(
                                    spacing: AppSpacing.s8,
                                    runSpacing: AppSpacing.s6,
                                    children: options.map<Widget>((opt) {
                                      final optStr = opt.toString();
                                      final isSelected = controller?.text == optStr;
                                      return ChoiceChip(
                                        label: Text(optStr, style: TextStyle(fontSize: 12, color: isSelected ? AppColors.pureWhite : primaryTextColor)),
                                        selected: isSelected,
                                        selectedColor: accentGreen,
                                        backgroundColor: cardBg,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                        onSelected: (val) {
                                          if (val) {
                                            setState(() => controller?.text = optStr);
                                          }
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: AppSpacing.s12),
                                ],

                                Text(
                                  "YOUR ANSWER",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: secondaryTextColor),
                                ),
                                const SizedBox(height: AppSpacing.s6),
                                TextField(
                                  controller: controller,
                                  maxLines: (item["field_type"] == "textarea") ? 4 : 1,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppRadii.control),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppRadii.control),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppRadii.control),
                                      borderSide: BorderSide(color: accentGreen, width: 1.5),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.s12),

                                // Answer Bank Memory Options
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _saveToBank[id] ?? true,
                                      activeColor: accentGreen,
                                      onChanged: (val) => setState(() => _saveToBank[id] = val ?? true),
                                    ),
                                    Expanded(
                                      child: Text(
                                        "Save to Answer Bank (never ask again)",
                                        style: TextStyle(fontSize: 12, color: primaryTextColor),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Action Buttons
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: borderColor)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _dismissItem(id),
                                  child: Text("Dismiss", style: TextStyle(color: secondaryTextColor)),
                                ),
                                const SizedBox(width: AppSpacing.s8),
                                ElevatedButton.icon(
                                  onPressed: () => _resolveItem(id),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentGreen,
                                    foregroundColor: AppColors.pureWhite,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s10),
                                  ),
                                  icon: const Icon(Icons.send, size: 16),
                                  label: const Text("Submit & Auto-Resume", style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
