import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/hallmark_tokens.dart';
import '../core/motion.dart';

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
      final itemsFuture = _api.getNeedsYou();
      final summaryFuture = _api.fetchNeedsYouSummary();
      final results = await Future.wait([itemsFuture, summaryFuture]);
      final items = results[0] as List<dynamic>;
      final summary = results[1] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _items = items;
          _summary = summary;
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
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Autonomous Status Badge
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.successEmerald.withOpacity(0.12),
                          border: Border.all(color: AppColors.successEmerald.withOpacity(0.3), width: 2),
                        ),
                        child: const Icon(Icons.shield_outlined, size: 48, color: AppColors.successEmerald),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      Text(
                        "Inbox Clear · Autonomous Operations Active",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primaryTextColor),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        "All active application workflows are resolving autonomously via verified candidate intelligence and Answer Bank memories.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.45, color: secondaryTextColor),
                      ),
                      const SizedBox(height: AppSpacing.s24),

                      // Metric Summary Row
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.s12),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(AppRadii.control),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.auto_awesome, size: 14, color: AppColors.successEmerald),
                                      const SizedBox(width: AppSpacing.s4),
                                      Text("Auto-resolved", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  Text(
                                    "${_summary['auto_processed_count'] ?? 0} answers",
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.s12),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(AppRadii.control),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.racingGreen),
                                      const SizedBox(width: AppSpacing.s4),
                                      Text("By candidate", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  Text(
                                    "${_summary['resolved_count'] ?? 0} confirmed",
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s24),

                      // Last Resolved Question Card
                      if (_summary["last_resolved"] != null) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "LAST RESOLVED QUESTION",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.s16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                            border: Border.all(color: brassColor.withOpacity(0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                                    decoration: BoxDecoration(
                                      color: accentGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(AppRadii.badge),
                                    ),
                                    child: Text(
                                      _summary["last_resolved"]["company"] ?? "Company",
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentGreen),
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(Icons.check_circle, size: 16, color: AppColors.successEmerald),
                                  const SizedBox(width: AppSpacing.s4),
                                  Text("Answer Stored", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s10),
                              Text(
                                _summary["last_resolved"]["question"] ?? "",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primaryTextColor),
                              ),
                              const SizedBox(height: AppSpacing.s6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(AppSpacing.s10),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                                  borderRadius: BorderRadius.circular(AppRadii.control),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Text(
                                  _summary["last_resolved"]["answer"] ?? "",
                                  style: TextStyle(fontSize: 12, color: primaryTextColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s24),
                      ],

                      // Recently Answered Questions List
                      if ((_summary["recently_answered"] as List<dynamic>?)?.isNotEmpty ?? false) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "RECENTLY LEARNED FROM YOU",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        ...(_summary["recently_answered"] as List<dynamic>).map((item) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: AppSpacing.s8),
                            padding: const EdgeInsets.all(AppSpacing.s12),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(AppRadii.control),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.psychology_outlined, size: 18, color: AppColors.accentDark),
                                const SizedBox(width: AppSpacing.s10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item["question"] ?? "",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryTextColor),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${item['company']} • ${item['answer']}",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  item["answered_at"] ?? "",
                                  style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
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

                    final coral = AppColors.getSemanticColor("coral", isDark);

                    return MotionFadeSlide(
                      index: idx,
                      child: Dismissible(
                        key: ValueKey("ny_$id"),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: coral.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(AppRadii.card),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Dismiss", style: TextStyle(color: coral, fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(width: 8),
                              Icon(Icons.delete_outline, color: coral),
                            ],
                          ),
                        ),
                        onDismissed: (_) => _dismissItem(id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.s16),
                          decoration: BoxDecoration(
                            color: isDark ? HallmarkConsole.panel : cardBg,
                            borderRadius: BorderRadius.circular(HallmarkConsole.radiusPanel),
                            border: Border.all(color: HallmarkConsole.amber.withOpacity(0.4), width: HallmarkConsole.ruleWidth),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          // Header: Company + Role Badge
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            decoration: BoxDecoration(
                              color: HallmarkConsole.amber.withOpacity(0.08),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(HallmarkConsole.radiusPanel)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.assignment_late_outlined, size: 18, color: HallmarkConsole.amber),
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
                                  decoration: HallmarkConsole.tagDecoration(tint: HallmarkConsole.amber),
                                  child: Text(
                                    (item["field_type"] ?? "text").toString().toLowerCase(),
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: HallmarkConsole.amber),
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
                                  "Question from employer form",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor),
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
                                    "Select option",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor),
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

                          // Action Buttons: Reject & Accept Options
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: borderColor)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showRejectDialog(item),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: coral,
                                    side: BorderSide(color: coral.withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  icon: Icon(Icons.close, size: 14, color: coral),
                                  label: const Text("Reject", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _dismissItem(id),
                                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                      child: Text("Skip", style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                                    ),
                                    const SizedBox(width: AppSpacing.s8),
                                    ElevatedButton.icon(
                                      onPressed: () => _resolveItem(id),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentGreen,
                                        foregroundColor: AppColors.pureWhite,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s8),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(Icons.check, size: 15),
                                      label: const Text("Accept & Continue", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )));
                  },
                ),
    );
  }
}
