import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../widgets/interactive_charts.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};
  String _timeRange = "7D"; // "7D", "30D", "All"

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getAnalytics();
      if (mounted) {
        setState(() {
          _data = res;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
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

    final emerald = AppColors.getSemanticColor("emerald", isDark);
    final blue = AppColors.getSemanticColor("blue", isDark);
    final violet = AppColors.getSemanticColor("violet", isDark);
    final teal = AppColors.getSemanticColor("teal", isDark);

    final totalTracked = _data["total_tracked"] ?? 0;
    final realApplied = _data["real_applied_count"] ?? 0;
    final dryRuns = _data["dry_run_count"] ?? 0;
    final interviewsCount = _data["interviews_count"] ?? 0;
    final conversionRate = _data["conversion_rate_percent"] ?? 0.0;

    final weeklyTrend = (_data["weekly_trend"] as List<dynamic>?) ?? [];
    final monthlyTrend = (_data["monthly_trend"] as List<dynamic>?) ?? [];
    final scoreDist = (_data["match_score_distribution"] as Map<String, dynamic>?) ?? {};
    final statusDist = (_data["status_distribution"] as Map<String, dynamic>?) ?? {};
    final funnel = (_data["funnel"] as List<dynamic>?) ?? [];
    final activityTrend = (_data["activity_line_trend"] as List<dynamic>?) ?? [];
    final resumeVersions = (_data["resume_performance"] as List<dynamic>?) ?? [];
    final topCompanies = (_data["top_companies"] as List<dynamic>?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Analytics & Funnel",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAnalytics),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: emerald))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Failed to load analytics: $_error", style: TextStyle(color: secondaryTextColor)),
                      const SizedBox(height: AppSpacing.s12),
                      ElevatedButton(onPressed: _loadAnalytics, child: const Text("Retry")),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadAnalytics,
                  color: emerald,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    children: [
                      // 1. Time Range Selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "METRICS OVERVIEW",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: borderColor.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(AppRadii.control),
                            ),
                            child: Row(
                              children: [
                                _buildRangeTab("7D", _timeRange == "7D", () => setState(() => _timeRange = "7D"), emerald),
                                _buildRangeTab("30D", _timeRange == "30D", () => setState(() => _timeRange = "30D"), emerald),
                                _buildRangeTab("All", _timeRange == "All", () => setState(() => _timeRange = "All"), emerald),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.s12),

                      // 2. High-Impact KPI Cards (Semantic Colors)
                      Row(
                        children: [
                          _buildKpiCard("Tracked Jobs", "$totalTracked", Icons.radar, blue, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                          const SizedBox(width: AppSpacing.s12),
                          _buildKpiCard("Real Submitted", "$realApplied", Icons.send_outlined, emerald, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      Row(
                        children: [
                          _buildKpiCard("Dry-Run Sims", "$dryRuns", Icons.science_outlined, violet, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                          const SizedBox(width: AppSpacing.s12),
                          _buildKpiCard("Interviews", "$interviewsCount ($conversionRate%)", Icons.event_available, teal, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.s20),

                      // 3. Interactive Chart 1: 7-Day & 4-Week Bar Chart
                      WeeklyMonthlyBarChart(
                        weeklyTrend: weeklyTrend,
                        monthlyTrend: monthlyTrend,
                      ),

                      const SizedBox(height: AppSpacing.s16),

                      // 4. Interactive Chart 2: Conversion Funnel Pipeline
                      if (funnel.isNotEmpty)
                        ApplicationFunnelChart(funnelData: funnel),

                      const SizedBox(height: AppSpacing.s16),

                      // 5. Interactive Chart 3: Application Status Distribution Donut
                      StatusDonutChart(
                        statusDistribution: statusDist,
                        totalCount: totalTracked,
                      ),

                      const SizedBox(height: AppSpacing.s16),

                      // 6. Interactive Chart 4: Fit Score Histogram
                      MatchScoreHistogram(
                        scoreDistribution: scoreDist,
                        totalCount: totalTracked,
                      ),

                      const SizedBox(height: AppSpacing.s16),

                      // 7. Interactive Chart 5: Weekly Job-Search Activity Line Chart
                      if (activityTrend.isNotEmpty)
                        WeeklyActivityLineChart(activityTrend: activityTrend),

                      const SizedBox(height: AppSpacing.s16),

                      // 8. Interactive Chart 6: Company-Wise Application Density
                      CompanyApplicationsChart(topCompanies: topCompanies),

                      const SizedBox(height: AppSpacing.s16),

                      // 9. Interactive Chart 7: Resume Version Comparison
                      if (resumeVersions.isNotEmpty)
                        ResumeComparisonChart(resumeVersions: resumeVersions),

                      const SizedBox(height: AppSpacing.s32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRangeTab(String label, bool active, VoidCallback onTap, Color activeColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.grey),
        ),
      ),
    );
  }

  Widget _buildKpiCard(
    String title,
    String value,
    IconData icon,
    Color iconColor,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
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
                Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: primaryTextColor)),
          ],
        ),
      ),
    );
  }
}
