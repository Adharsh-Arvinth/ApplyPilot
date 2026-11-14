import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

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
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final brassColor = isDark ? AppColors.brassDark : AppColors.mutedBrass;

    final totalTracked = _data["total_tracked"] ?? 0;
    final totalApplied = _data["total_applied"] ?? 0;
    final interviewsCount = _data["interviews_count"] ?? 0;
    final conversionRate = _data["conversion_rate_percent"] ?? 0.0;
    final avgResponseDays = _data["avg_response_days"] ?? 0.0;

    final weeklyTrend = (_data["weekly_trend"] as List<dynamic>?) ?? [];
    final monthlyTrend = (_data["monthly_trend"] as List<dynamic>?) ?? [];
    final scoreDist = (_data["match_score_distribution"] as Map<String, dynamic>?) ?? {};
    final sources = (_data["source_breakdown"] as Map<String, dynamic>?) ?? {};
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
          ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
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
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  children: [
                    // 1. KPI Cards Grid
                    Row(
                      children: [
                        _buildKpiCard("Tracked Jobs", "$totalTracked", Icons.radar, accentGreen, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                        const SizedBox(width: AppSpacing.s12),
                        _buildKpiCard("Applications", "$totalApplied", Icons.send_outlined, accentGreen, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        _buildKpiCard("Interviews", "$interviewsCount", Icons.event_available, brassColor, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                        const SizedBox(width: AppSpacing.s12),
                        _buildKpiCard("Conversion", "$conversionRate%", Icons.trending_up, AppColors.successLight, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.s20),

                    // 2. Weekly Application Trend
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("7-DAY APPLICATION VELOCITY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                          const SizedBox(height: AppSpacing.s16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: weeklyTrend.map<Widget>((item) {
                              final count = (item["count"] ?? 0) as int;
                              final maxCount = weeklyTrend.map((e) => (e["count"] ?? 0) as int).fold(1, (a, b) => a > b ? a : b);
                              final height = 75 * (count / maxCount).clamp(0.12, 1.0);
                              return Column(
                                children: [
                                  Text("$count", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: count > 0 ? accentGreen : secondaryTextColor)),
                                  const SizedBox(height: AppSpacing.s4),
                                  Container(
                                    width: 20,
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: count > 0 ? accentGreen : borderColor,
                                      borderRadius: BorderRadius.circular(AppRadii.badge),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s6),
                                  Text(item["day"] ?? "", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                                ],
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.s16),

                    // 3. Match Score Distribution Breakdown
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("FIT SCORE DISTRIBUTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                          const SizedBox(height: AppSpacing.s16),
                          _buildDistributionBar("High Fit (4.0 - 5.0 ★)", scoreDist["tier_4_5"] ?? 0, totalTracked, accentGreen, primaryTextColor, secondaryTextColor),
                          const SizedBox(height: AppSpacing.s8),
                          _buildDistributionBar("Target Fit (3.0 - 3.9 ★)", scoreDist["tier_3_4"] ?? 0, totalTracked, brassColor, primaryTextColor, secondaryTextColor),
                          const SizedBox(height: AppSpacing.s8),
                          _buildDistributionBar("Borderline (2.0 - 2.9 ★)", scoreDist["tier_2_3"] ?? 0, totalTracked, AppColors.warningLight, primaryTextColor, secondaryTextColor),
                          const SizedBox(height: AppSpacing.s8),
                          _buildDistributionBar("Filtered (< 2.0 ★)", scoreDist["tier_1_2"] ?? 0, totalTracked, AppColors.errorLight, primaryTextColor, secondaryTextColor),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.s16),

                    // 4. Source-Wise Performance & Top Companies
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sources
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("ATS PLATFORMS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                                const SizedBox(height: AppSpacing.s12),
                                ...sources.entries.map((e) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: AppSpacing.s6),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(e.key.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor)),
                                        Text("${e.value}", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        // Top Companies
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.s16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("TOP COMPANIES", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                                const SizedBox(height: AppSpacing.s12),
                                if (topCompanies.isEmpty)
                                  Text("No applications yet", style: TextStyle(fontSize: 11, color: secondaryTextColor))
                                else
                                  ...topCompanies.map((c) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text(c["company"] ?? "", overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor))),
                                          Text("${c['applications']} apps", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.s24),
                  ],
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                Icon(icon, size: 16, color: iconColor),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: primaryTextColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionBar(
    String label,
    int count,
    int total,
    Color barColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final pct = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: primaryTextColor)),
            Text("$count jobs (${(pct * 100).round()}%)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: secondaryTextColor)),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: barColor.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}
