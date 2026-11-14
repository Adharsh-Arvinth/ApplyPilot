import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

class WidgetConfig {
  static const String goal = "goal";
  static const String interview = "interview";
  static const String match = "match";
  static const String attention = "attention";
  static const String streak = "streak";
  static const String health = "health";
  static const String funnel = "funnel";
  static const String quickActions = "quick_actions";

  static const List<String> defaultOrder = [
    goal,
    attention,
    interview,
    match,
    streak,
    health,
    funnel,
    quickActions,
  ];

  static const Map<String, String> titles = {
    goal: "Application Goal",
    interview: "Interview Countdown",
    match: "Top Job Match",
    attention: "Needs Attention",
    streak: "Career Streak",
    health: "Backend Engine",
    funnel: "Application Funnel",
    quickActions: "Quick Actions",
  };

  static const Map<String, IconData> icons = {
    goal: Icons.flag_outlined,
    interview: Icons.event_available_outlined,
    match: Icons.auto_awesome_outlined,
    attention: Icons.notification_important_outlined,
    streak: Icons.local_fire_department_outlined,
    health: Icons.dns_outlined,
    funnel: Icons.filter_alt_outlined,
    quickActions: Icons.bolt_outlined,
  };
}

class DashboardPreferences {
  List<String> order;
  Set<String> visible;
  Set<String> pinned;
  bool isCompact;

  DashboardPreferences({
    required this.order,
    required this.visible,
    required this.pinned,
    this.isCompact = false,
  });

  factory DashboardPreferences.defaults() {
    return DashboardPreferences(
      order: List.from(WidgetConfig.defaultOrder),
      visible: Set.from(WidgetConfig.defaultOrder),
      pinned: {WidgetConfig.goal, WidgetConfig.attention},
      isCompact: false,
    );
  }

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    final rawOrder = (json["order"] as List<dynamic>?)?.map((e) => e.toString()).toList();
    final rawVisible = (json["visible"] as List<dynamic>?)?.map((e) => e.toString()).toSet();
    final rawPinned = (json["pinned"] as List<dynamic>?)?.map((e) => e.toString()).toSet();
    final compact = (json["is_compact"] as bool?) ?? false;

    final order = rawOrder ?? List.from(WidgetConfig.defaultOrder);
    for (final def in WidgetConfig.defaultOrder) {
      if (!order.contains(def)) order.add(def);
    }

    return DashboardPreferences(
      order: order,
      visible: rawVisible ?? Set.from(WidgetConfig.defaultOrder),
      pinned: rawPinned ?? {WidgetConfig.goal},
      isCompact: compact,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "order": order,
      "visible": visible.toList(),
      "pinned": pinned.toList(),
      "is_compact": isCompact,
    };
  }
}

// ---------------------------------------------------------------------------
// 1. Application Goal Widget
// ---------------------------------------------------------------------------
class ApplicationGoalWidget extends StatefulWidget {
  final Map<String, dynamic> goalData;
  final Map<String, dynamic>? statsData;
  final bool isCompact;
  final VoidCallback onAdjustTarget;

  const ApplicationGoalWidget({
    super.key,
    required this.goalData,
    this.statsData,
    this.isCompact = false,
    required this.onAdjustTarget,
  });

  @override
  State<ApplicationGoalWidget> createState() => _ApplicationGoalWidgetState();
}

class _ApplicationGoalWidgetState extends State<ApplicationGoalWidget> {
  bool _showWeekly = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final emerald = AppColors.getSemanticColor("emerald", isDark);

    final realApplied = widget.statsData?["real_applied_today"] ?? widget.statsData?["daily_applied"] ?? widget.goalData["daily_applied"] ?? 0;
    final dryRunCount = widget.statsData?["dry_run_today"] ?? 0;
    final dailyCap = widget.statsData?["daily_cap"] ?? 100;

    final dailyTarget = widget.goalData["daily_target"] ?? 50;
    final dailyApplied = widget.goalData["daily_applied"] ?? realApplied;
    final dailyRemaining = widget.goalData["daily_remaining"] ?? math.max(0, (dailyTarget as int) - (dailyApplied as int));
    final dailyPercent = (widget.goalData["daily_percent"] as num?)?.toDouble() ??
        (dailyTarget > 0 ? ((dailyApplied / dailyTarget) * 100.0) : 0.0);

    final weeklyTarget = widget.goalData["weekly_target"] ?? 250;
    final weeklyApplied = widget.goalData["weekly_applied"] ?? dailyApplied;
    final weeklyRemaining = widget.goalData["weekly_remaining"] ?? math.max(0, (weeklyTarget as int) - (weeklyApplied as int));
    final weeklyPercent = (widget.goalData["weekly_percent"] as num?)?.toDouble() ?? 0.0;

    final target = _showWeekly ? weeklyTarget : dailyTarget;
    final applied = _showWeekly ? weeklyApplied : dailyApplied;
    final remaining = _showWeekly ? weeklyRemaining : dailyRemaining;
    final percent = _showWeekly ? weeklyPercent : dailyPercent;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.flag_outlined, size: 16, color: emerald),
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    _showWeekly ? "WEEKLY GOAL" : "DAILY GOAL",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(() => _showWeekly = !_showWeekly),
                borderRadius: BorderRadius.circular(AppRadii.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6, vertical: 2),
                  child: Text(
                    _showWeekly ? "Switch to Daily" : "Switch to Weekly",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: emerald),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: (percent / 100.0).clamp(0.0, 1.0),
                      strokeWidth: 6,
                      backgroundColor: borderColor,
                      color: emerald,
                    ),
                    Text(
                      "${percent.toInt()}%",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primaryTextColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "$applied",
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: primaryTextColor),
                        ),
                        Text(
                          " / $target target",
                          style: TextStyle(fontSize: 13, color: secondaryTextColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      remaining > 0 ? "$remaining more needed to reach goal" : "Target achieved! Outstanding pace.",
                      style: TextStyle(fontSize: 11, color: remaining > 0 ? secondaryTextColor : emerald, fontWeight: remaining > 0 ? FontWeight.normal : FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          // Distinct Real vs Dry-run telemetry bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: 7),
            decoration: BoxDecoration(
              color: borderColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: emerald)),
                    const SizedBox(width: 6),
                    Text(
                      "Real Submitted: $realApplied / $dailyCap",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor),
                    ),
                  ],
                ),
                Container(width: 1, height: 12, color: borderColor),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.getSemanticColor("blue", isDark))),
                    const SizedBox(width: 6),
                    Text(
                      "Dry-Run: $dryRunCount",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Interview Countdown Widget
// ---------------------------------------------------------------------------
class InterviewCountdownWidget extends StatelessWidget {
  final Map<String, dynamic>? interviewData;
  final bool isCompact;
  final VoidCallback onOpenPrep;

  const InterviewCountdownWidget({
    super.key,
    required this.interviewData,
    this.isCompact = false,
    required this.onOpenPrep,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final teal = AppColors.getSemanticColor("teal", isDark);

    if (interviewData == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.event_available_outlined, size: 20, color: teal),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text("No upcoming interviews scheduled yet.", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
            ),
          ],
        ),
      );
    }

    final company = interviewData!["company"] ?? "Target Company";
    final title = interviewData!["title"] ?? "Role";
    final scheduledStr = interviewData!["scheduled_at"] ?? "";
    DateTime? dt;
    try {
      dt = DateTime.parse(scheduledStr);
    } catch (_) {}

    String countdown = "Scheduled Soon";
    if (dt != null) {
      final diff = dt.difference(DateTime.now());
      if (diff.inDays > 0) {
        countdown = "In ${diff.inDays} days";
      } else if (diff.inHours > 0) {
        countdown = "In ${diff.inHours} hours";
      } else {
        countdown = "Today";
      }
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_outlined, size: 16, color: teal),
                  const SizedBox(width: AppSpacing.s6),
                  Text("UPCOMING INTERVIEW", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Text(
                  countdown,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: teal),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            company,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primaryTextColor),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenPrep,
              icon: Icon(Icons.psychology_outlined, size: 15, color: teal),
              label: Text("Prepare Key Proof Points", style: TextStyle(fontSize: 12, color: teal, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: teal.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Job Match Widget
// ---------------------------------------------------------------------------
class JobMatchWidget extends StatelessWidget {
  final List<dynamic> matches;
  final bool isCompact;
  final Function(int jobId) onReviewMatch;
  final Function(int jobId) onQuickApply;

  const JobMatchWidget({
    super.key,
    required this.matches,
    this.isCompact = false,
    required this.onReviewMatch,
    required this.onQuickApply,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final blue = AppColors.getSemanticColor("blue", isDark);

    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_outlined, size: 20, color: blue),
            const SizedBox(width: AppSpacing.s12),
            Expanded(child: Text("Run discovery to surface highest-fit roles.", style: TextStyle(fontSize: 12, color: secondaryTextColor))),
          ],
        ),
      );
    }

    final topMatch = matches.first as Map<String, dynamic>;
    final jobId = (topMatch["id"] ?? 0) as int;
    final company = topMatch["company"] ?? "Company";
    final title = topMatch["title"] ?? "Role";
    final matchPct = topMatch["match_percent"] ?? 90;
    final factors = (topMatch["factors"] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, size: 16, color: blue),
                  const SizedBox(width: AppSpacing.s6),
                  Text("HIGHEST FIT MATCH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Text(
                  "$matchPct% Fit",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: blue),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(company, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: primaryTextColor)),
          Text(title, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: factors.map((f) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: borderColor.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(f, style: TextStyle(fontSize: 10, color: secondaryTextColor, fontWeight: FontWeight.w500)),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onReviewMatch(jobId),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  ),
                  child: Text("Review Fit", style: TextStyle(fontSize: 11, color: primaryTextColor)),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => onQuickApply(jobId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  ),
                  child: const Text("Tailor & Queue", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Needs Attention Widget
// ---------------------------------------------------------------------------
class NeedsAttentionWidget extends StatelessWidget {
  final Map<String, dynamic> attentionData;
  final bool isCompact;
  final VoidCallback onResolveInbox;
  final VoidCallback onReviewApprovals;

  const NeedsAttentionWidget({
    super.key,
    required this.attentionData,
    this.isCompact = false,
    required this.onResolveInbox,
    required this.onReviewApprovals,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final amber = AppColors.getSemanticColor("amber", isDark);
    final coral = AppColors.getSemanticColor("coral", isDark);

    final pendingApprovals = (attentionData["pending_approvals"] ?? 0) as int;
    final needsYouCount = (attentionData["needs_you_count"] ?? 0) as int;
    final failedTasks = (attentionData["failed_tasks"] ?? 0) as int;
    final missingFields = (attentionData["missing_profile_fields"] as List<dynamic>?) ?? [];
    final isTripped = (attentionData["circuit_breaker_tripped"] ?? false) as bool;

    final hasCritical = needsYouCount > 0 || isTripped || failedTasks > 0;
    final themeColor = hasCritical ? coral : amber;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: hasCritical ? coral.withOpacity(0.5) : borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.notification_important_outlined, size: 16, color: themeColor),
                  const SizedBox(width: AppSpacing.s6),
                  Text("NEEDS ATTENTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                ],
              ),
              if (needsYouCount > 0 || pendingApprovals > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: themeColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Text(
                    "${needsYouCount + pendingApprovals} items",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: themeColor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          if (needsYouCount > 0) ...[
            InkWell(
              onTap: onResolveInbox,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 16, color: coral),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(child: Text("$needsYouCount form question requires human answer", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor))),
                    Icon(Icons.chevron_right, size: 16, color: secondaryTextColor),
                  ],
                ),
              ),
            ),
          ],
          if (pendingApprovals > 0) ...[
            InkWell(
              onTap: onReviewApprovals,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 16, color: amber),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(child: Text("$pendingApprovals evaluated jobs awaiting swipe approval", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor))),
                    Icon(Icons.chevron_right, size: 16, color: secondaryTextColor),
                  ],
                ),
              ),
            ),
          ],
          if (failedTasks > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: coral),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(child: Text("$failedTasks automated task failed (review execution log)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor))),
                  Icon(Icons.chevron_right, size: 16, color: secondaryTextColor),
                ],
              ),
            ),
          ],
          if (needsYouCount == 0 && pendingApprovals == 0 && missingFields.isEmpty && failedTasks == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: AppColors.getSemanticColor("emerald", isDark)),
                  const SizedBox(width: AppSpacing.s8),
                  Text("All queues clear. Engine operating normally.", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Career Streak Widget
// ---------------------------------------------------------------------------
class CareerStreakWidget extends StatelessWidget {
  final Map<String, dynamic> streakData;
  final bool isCompact;

  const CareerStreakWidget({
    super.key,
    required this.streakData,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final amber = AppColors.getSemanticColor("amber", isDark);

    final streakDays = streakData["current_streak_days"] ?? 3;
    final milestone = streakData["milestone"] ?? "Consistency Hunter";
    final weeklyDays = (streakData["weekly_days"] as List<dynamic>?) ?? [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department_outlined, size: 16, color: amber),
                  const SizedBox(width: AppSpacing.s6),
                  Text("CAREER SEARCH STREAK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                ],
              ),
              Text(
                "$streakDays Days Active",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: amber),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            milestone,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weeklyDays.map<Widget>((d) {
              final day = d["day"] ?? "";
              final active = (d["active"] ?? false) as bool;
              final isToday = (d["is_today"] ?? false) as bool;

              return Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? amber : borderColor.withOpacity(0.3),
                      border: isToday ? Border.all(color: primaryTextColor, width: 2) : null,
                    ),
                    alignment: Alignment.center,
                    child: active
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text(day, style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                  ),
                  const SizedBox(height: 4),
                  Text(day, style: TextStyle(fontSize: 10, fontWeight: isToday ? FontWeight.bold : FontWeight.normal, color: isToday ? primaryTextColor : secondaryTextColor)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Backend Health Widget
// ---------------------------------------------------------------------------
class BackendHealthWidget extends StatelessWidget {
  final Map<String, dynamic> healthData;
  final bool isCompact;
  final VoidCallback onPingTest;

  const BackendHealthWidget({
    super.key,
    required this.healthData,
    this.isCompact = false,
    required this.onPingTest,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final emerald = AppColors.getSemanticColor("emerald", isDark);
    final coral = AppColors.getSemanticColor("coral", isDark);

    final status = healthData["status"] ?? "online";
    final isOnline = status == "online";
    final isPaused = (healthData["queue_paused"] ?? false) as bool;
    final isGoLive = (healthData["go_live"] ?? false) as bool;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_outlined, size: 16, color: isOnline ? emerald : coral),
                  const SizedBox(width: AppSpacing.s6),
                  Text("BACKEND ENGINE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                ],
              ),
              InkWell(
                onTap: onPingTest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 12, color: secondaryTextColor),
                      const SizedBox(width: 4),
                      Text("Ping", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? emerald : coral,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? "Windows PC Active" : "Backend Offline",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryTextColor),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isGoLive ? coral : emerald).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Text(
                  isGoLive ? "LIVE AUTO-SUBMIT" : "DRY-RUN SAFE",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isGoLive ? coral : emerald),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isPaused ? "Queue is PAUSED by emergency control switch" : "Automated processing queue is running",
            style: TextStyle(fontSize: 11, color: isPaused ? coral : secondaryTextColor),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Application Funnel Widget
// ---------------------------------------------------------------------------
class ApplicationFunnelWidget extends StatelessWidget {
  final List<dynamic> funnelData;
  final bool isCompact;

  const ApplicationFunnelWidget({
    super.key,
    required this.funnelData,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final violet = AppColors.getSemanticColor("violet", isDark);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined, size: 16, color: violet),
              const SizedBox(width: AppSpacing.s6),
              Text("APPLICATION FUNNEL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          ...funnelData.map((stage) {
            final name = stage["stage"] ?? "";
            final count = stage["count"] ?? 0;
            final rate = (stage["rate"] as num?)?.toDouble() ?? 0.0;
            final colorName = stage["color"] ?? "blue";
            final color = AppColors.getSemanticColor(colorName, isDark);

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      Text("$count (${rate.toStringAsFixed(1)}%)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.badge),
                    child: LinearProgressIndicator(
                      value: (rate / 100.0).clamp(0.02, 1.0),
                      minHeight: 6,
                      backgroundColor: borderColor.withOpacity(0.3),
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Quick Actions Widget
// ---------------------------------------------------------------------------
class QuickActionsWidget extends StatelessWidget {
  final bool isCompact;
  final VoidCallback onFindJobs;
  final VoidCallback onTailorResume;
  final VoidCallback onReviewQueue;
  final VoidCallback onUpdateAnswerBank;
  final VoidCallback onToggleAutomation;
  final bool isPaused;

  const QuickActionsWidget({
    super.key,
    this.isCompact = false,
    required this.onFindJobs,
    required this.onTailorResume,
    required this.onReviewQueue,
    required this.onUpdateAnswerBank,
    required this.onToggleAutomation,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_outlined, size: 16, color: AppColors.getSemanticColor("amber", isDark)),
              const SizedBox(width: AppSpacing.s6),
              Text("QUICK ACTIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionButton(context, "Find Jobs", Icons.search, AppColors.getSemanticColor("blue", isDark), onFindJobs),
              _buildActionButton(context, "Tailor Resume", Icons.edit_document, AppColors.getSemanticColor("violet", isDark), onTailorResume),
              _buildActionButton(context, "Review Queue", Icons.list_alt, AppColors.getSemanticColor("amber", isDark), onReviewQueue),
              _buildActionButton(context, "Answer Bank", Icons.source_outlined, AppColors.getSemanticColor("teal", isDark), onUpdateAnswerBank),
              _buildActionButton(
                context,
                isPaused ? "Resume Auto" : "Pause Auto",
                isPaused ? Icons.play_arrow : Icons.pause,
                isPaused ? AppColors.getSemanticColor("emerald", isDark) : AppColors.getSemanticColor("coral", isDark),
                onToggleAutomation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget Customization Bottom Sheet
// ---------------------------------------------------------------------------
class WidgetCustomizerSheet extends StatefulWidget {
  final DashboardPreferences currentPrefs;
  final Function(DashboardPreferences newPrefs) onSave;

  const WidgetCustomizerSheet({
    super.key,
    required this.currentPrefs,
    required this.onSave,
  });

  @override
  State<WidgetCustomizerSheet> createState() => _WidgetCustomizerSheetState();
}

class _WidgetCustomizerSheetState extends State<WidgetCustomizerSheet> {
  late List<String> _order;
  late Set<String> _visible;
  late Set<String> _pinned;
  late bool _isCompact;

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.currentPrefs.order);
    _visible = Set.from(widget.currentPrefs.visible);
    _pinned = Set.from(widget.currentPrefs.pinned);
    _isCompact = widget.currentPrefs.isCompact;
  }

  void _reset() {
    setState(() {
      final def = DashboardPreferences.defaults();
      _order = def.order;
      _visible = def.visible;
      _pinned = def.pinned;
      _isCompact = def.isCompact;
    });
  }

  void _save() {
    final updated = DashboardPreferences(
      order: _order,
      visible: _visible,
      pinned: _pinned,
      isCompact: _isCompact,
    );
    widget.onSave(updated);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final emerald = AppColors.getSemanticColor("emerald", isDark);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Customize Dashboard",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryTextColor),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _reset,
                    child: Text("Reset", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                  ),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emerald,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: const Text("Save"),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            "Reorder widgets by dragging, toggle visibility, or pin critical metrics to the top.",
            style: TextStyle(fontSize: 12, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s12),
          SwitchListTile(
            title: Text("Compact Layout Density", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
            subtitle: Text("Reduce widget padding for higher density view", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
            value: _isCompact,
            activeColor: emerald,
            onChanged: (v) => setState(() => _isCompact = v),
          ),
          const Divider(),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _order.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _order.removeAt(oldIndex);
                  _order.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final key = _order[index];
                final title = WidgetConfig.titles[key] ?? key;
                final icon = WidgetConfig.icons[key] ?? Icons.widgets;
                final isVis = _visible.contains(key);
                final isPin = _pinned.contains(key);

                return ListTile(
                  key: ValueKey(key),
                  leading: Icon(icon, color: isVis ? primaryTextColor : secondaryTextColor),
                  title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isVis ? primaryTextColor : secondaryTextColor)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isPin ? Icons.push_pin : Icons.push_pin_outlined, size: 18, color: isPin ? emerald : secondaryTextColor),
                        onPressed: () {
                          setState(() {
                            if (isPin) {
                              _pinned.remove(key);
                            } else {
                              _pinned.add(key);
                            }
                          });
                        },
                      ),
                      Switch(
                        value: isVis,
                        activeColor: emerald,
                        onChanged: (v) {
                          setState(() {
                            if (v) {
                              _visible.add(key);
                            } else {
                              _visible.remove(key);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.drag_handle, size: 20),
                    ],
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
