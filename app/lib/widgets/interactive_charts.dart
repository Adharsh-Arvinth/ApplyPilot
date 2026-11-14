import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

// ---------------------------------------------------------------------------
// 1. Weekly & Monthly Applications Bar Chart
// ---------------------------------------------------------------------------
class WeeklyMonthlyBarChart extends StatefulWidget {
  final List<dynamic> weeklyTrend;
  final List<dynamic> monthlyTrend;

  const WeeklyMonthlyBarChart({
    super.key,
    required this.weeklyTrend,
    required this.monthlyTrend,
  });

  @override
  State<WeeklyMonthlyBarChart> createState() => _WeeklyMonthlyBarChartState();
}

class _WeeklyMonthlyBarChartState extends State<WeeklyMonthlyBarChart> {
  bool _isWeekly = true;
  int? _selectedIdx;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final emerald = AppColors.getSemanticColor("emerald", isDark);
    final blue = AppColors.getSemanticColor("blue", isDark);

    final dataList = _isWeekly ? widget.weeklyTrend : widget.monthlyTrend;
    final maxCount = dataList.map((e) => (e["count"] ?? 0) as int).fold(1, (a, b) => a > b ? a : b);

    final selectedItem = (_selectedIdx != null && _selectedIdx! < dataList.length) ? dataList[_selectedIdx!] : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
              Text(
                _isWeekly ? "7-DAY APPLICATION VELOCITY" : "4-WEEK APPLICATION VOLUME",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
              ),
              Container(
                decoration: BoxDecoration(
                  color: borderColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Row(
                  children: [
                    _buildToggleBtn("7D", _isWeekly, () => setState(() { _isWeekly = true; _selectedIdx = null; }), emerald),
                    _buildToggleBtn("4W", !_isWeekly, () => setState(() { _isWeekly = false; _selectedIdx = null; }), emerald),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          // Tooltip banner
          if (selectedItem != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(bottom: AppSpacing.s10),
              decoration: BoxDecoration(
                color: emerald.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Text(
                "${selectedItem['date'] ?? selectedItem['range'] ?? ''}: ${selectedItem['count']} applications submitted",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: emerald),
              ),
            ),
          const SizedBox(height: AppSpacing.s8),
          // Bars
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(dataList.length, (idx) {
                final item = dataList[idx];
                final count = (item["count"] ?? 0) as int;
                final label = _isWeekly ? (item["day"] ?? "") : (item["week"] ?? "");
                final isSelected = _selectedIdx == idx;
                final isPeak = count > 0 && count == maxCount;
                final barHeight = 85.0 * (count / maxCount).clamp(0.1, 1.0);

                return GestureDetector(
                  onTap: () => setState(() => _selectedIdx = isSelected ? null : idx),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        "$count",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? emerald : (count > 0 ? primaryTextColor : secondaryTextColor),
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _isWeekly ? 24 : 36,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? emerald
                              : (isPeak
                                  ? emerald.withOpacity(0.85)
                                  : (count > 0 ? blue.withOpacity(0.7) : borderColor.withOpacity(0.5))),
                          borderRadius: BorderRadius.circular(AppRadii.badge),
                          border: isSelected ? Border.all(color: primaryTextColor, width: 1.5) : null,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? primaryTextColor : secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool active, VoidCallback onTap, Color activeColor) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Application Funnel Chart
// ---------------------------------------------------------------------------
class ApplicationFunnelChart extends StatefulWidget {
  final List<dynamic> funnelData;

  const ApplicationFunnelChart({super.key, required this.funnelData});

  @override
  State<ApplicationFunnelChart> createState() => _ApplicationFunnelChartState();
}

class _ApplicationFunnelChartState extends State<ApplicationFunnelChart> {
  int? _selectedStage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
          Text(
            "CONVERSION FUNNEL PIPELINE",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s16),
          ...List.generate(widget.funnelData.length, (idx) {
            final stage = widget.funnelData[idx];
            final name = stage["stage"] ?? "";
            final count = stage["count"] ?? 0;
            final rate = (stage["rate"] as num?)?.toDouble() ?? 0.0;
            final colorName = stage["color"] ?? "blue";
            final color = AppColors.getSemanticColor(colorName, isDark);
            final isSelected = _selectedStage == idx;

            return GestureDetector(
              onTap: () => setState(() => _selectedStage = isSelected ? null : idx),
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.s10),
                padding: const EdgeInsets.all(AppSpacing.s8),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  border: isSelected ? Border.all(color: color.withOpacity(0.4)) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                            const SizedBox(width: 8),
                            Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryTextColor)),
                          ],
                        ),
                        Text(
                          "$count (${rate.toStringAsFixed(1)}%)",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isSelected ? color : secondaryTextColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: borderColor.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: (rate / 100.0).clamp(0.03, 1.0),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Application Status Distribution (Donut Chart)
// ---------------------------------------------------------------------------
class StatusDonutChart extends StatefulWidget {
  final Map<String, dynamic> statusDistribution;
  final int totalCount;

  const StatusDonutChart({
    super.key,
    required this.statusDistribution,
    required this.totalCount,
  });

  @override
  State<StatusDonutChart> createState() => _StatusDonutChartState();
}

class _StatusDonutChartState extends State<StatusDonutChart> {
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final categories = [
      {"key": "submitted", "label": "Submitted", "color": AppColors.getSemanticColor("emerald", isDark)},
      {"key": "interview", "label": "Interview", "color": AppColors.getSemanticColor("teal", isDark)},
      {"key": "approved", "label": "Approved", "color": AppColors.getSemanticColor("violet", isDark)},
      {"key": "evaluated", "label": "Evaluated", "color": AppColors.getSemanticColor("amber", isDark)},
      {"key": "discovered", "label": "Discovered", "color": AppColors.getSemanticColor("blue", isDark)},
      {"key": "rejected", "label": "Filtered", "color": AppColors.getSemanticColor("coral", isDark)},
    ];

    final total = math.max(widget.totalCount, 1);
    final selectedCount = _selectedKey != null ? (widget.statusDistribution[_selectedKey] ?? 0) : null;
    final selectedPct = selectedCount != null ? ((selectedCount / total) * 100).toStringAsFixed(1) : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
          Text(
            "APPLICATION STATUS DISTRIBUTION",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              // Custom Donut Canvas
              SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    distribution: widget.statusDistribution,
                    categories: categories,
                    total: total,
                    selectedKey: _selectedKey,
                    isDark: isDark,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _selectedKey != null ? "$selectedCount" : "${widget.totalCount}",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: primaryTextColor),
                        ),
                        Text(
                          _selectedKey != null ? "$selectedPct%" : "Total",
                          style: TextStyle(fontSize: 10, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              // Interactive Legend
              Expanded(
                child: Column(
                  children: categories.map((c) {
                    final key = c["key"] as String;
                    final label = c["label"] as String;
                    final color = c["color"] as Color;
                    final count = (widget.statusDistribution[key] ?? 0) as int;
                    final isSel = _selectedKey == key;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedKey = isSel ? null : key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: isSel ? 10 : 8,
                                  height: isSel ? 10 : 8,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                    color: isSel ? primaryTextColor : secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              "$count",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSel ? color : secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final Map<String, dynamic> distribution;
  final List<Map<String, dynamic>> categories;
  final int total;
  final String? selectedKey;
  final bool isDark;

  _DonutChartPainter({
    required this.distribution,
    required this.categories,
    required this.total,
    required this.selectedKey,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    double startAngle = -math.pi / 2;

    for (final c in categories) {
      final key = c["key"] as String;
      final color = c["color"] as Color;
      final count = (distribution[key] ?? 0) as int;
      if (count <= 0) continue;

      final sweepAngle = (count / total) * 2 * math.pi;
      final isSel = selectedKey == key;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 18 : 12
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 10),
        startAngle,
        sweepAngle - 0.04, // slight segment gap
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// 4. Match Score Distribution (Histogram)
// ---------------------------------------------------------------------------
class MatchScoreHistogram extends StatefulWidget {
  final Map<String, dynamic> scoreDistribution;
  final int totalCount;

  const MatchScoreHistogram({
    super.key,
    required this.scoreDistribution,
    required this.totalCount,
  });

  @override
  State<MatchScoreHistogram> createState() => _MatchScoreHistogramState();
}

class _MatchScoreHistogramState extends State<MatchScoreHistogram> {
  String? _selectedBracket;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final brackets = [
      {"key": "tier_4_5", "label": "4.0 - 5.0", "sub": "High Fit", "color": AppColors.getSemanticColor("emerald", isDark)},
      {"key": "tier_3_4", "label": "3.0 - 3.9", "sub": "Target Fit", "color": AppColors.getSemanticColor("blue", isDark)},
      {"key": "tier_2_3", "label": "2.0 - 2.9", "sub": "Borderline", "color": AppColors.getSemanticColor("amber", isDark)},
      {"key": "tier_1_2", "label": "< 2.0", "sub": "Filtered", "color": AppColors.getSemanticColor("coral", isDark)},
    ];

    final maxVal = brackets.map((b) => (widget.scoreDistribution[b["key"]] ?? 0) as int).fold(1, (a, b) => a > b ? a : b);
    final total = math.max(widget.totalCount, 1);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
          Text(
            "FIT SCORE HISTOGRAM (0 - 5.0 ★)",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: brackets.map((b) {
              final key = b["key"] as String;
              final label = b["label"] as String;
              final sub = b["sub"] as String;
              final color = b["color"] as Color;
              final count = (widget.scoreDistribution[key] ?? 0) as int;
              final isSel = _selectedBracket == key;
              final barHeight = 85.0 * (count / maxVal).clamp(0.08, 1.0);
              final pct = ((count / total) * 100).toStringAsFixed(0);

              return GestureDetector(
                onTap: () => setState(() => _selectedBracket = isSel ? null : key),
                child: Column(
                  children: [
                    Text(
                      "$count ($pct%)",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSel ? color : secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 48,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: isSel ? color : color.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(AppRadii.badge),
                        border: isSel ? Border.all(color: primaryTextColor, width: 1.5) : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    Text(sub, style: TextStyle(fontSize: 9, color: secondaryTextColor)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Weekly Activity Line Chart (Smooth Bezier with Area Gradient)
// ---------------------------------------------------------------------------
class WeeklyActivityLineChart extends StatefulWidget {
  final List<dynamic> activityTrend;

  const WeeklyActivityLineChart({super.key, required this.activityTrend});

  @override
  State<WeeklyActivityLineChart> createState() => _WeeklyActivityLineChartState();
}

class _WeeklyActivityLineChartState extends State<WeeklyActivityLineChart> {
  int? _touchIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final emerald = AppColors.getSemanticColor("emerald", isDark);

    final data = widget.activityTrend;
    final selectedPoint = (_touchIndex != null && _touchIndex! < data.length) ? data[_touchIndex!] : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
              Text(
                "WEEKLY JOB SEARCH ACTIVITY",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
              ),
              if (selectedPoint != null)
                Text(
                  "${selectedPoint['date']}: ${selectedPoint['total_activity']} actions",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: emerald),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: GestureDetector(
              onPanDown: (details) => _handleTouch(details.localPosition.dx),
              onPanUpdate: (details) => _handleTouch(details.localPosition.dx),
              child: CustomPaint(
                painter: _LineChartPainter(
                  data: data,
                  lineColor: emerald,
                  selectedIndex: _touchIndex,
                  isDark: isDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: data.map<Widget>((e) {
              return Text(
                e["day"] ?? "",
                style: TextStyle(fontSize: 10, color: secondaryTextColor),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _handleTouch(double dx) {
    if (widget.activityTrend.isEmpty) return;
    final w = MediaQuery.of(context).size.width - 72; // estimated width
    final segWidth = w / math.max(widget.activityTrend.length - 1, 1);
    final idx = (dx / segWidth).round().clamp(0, widget.activityTrend.length - 1);
    setState(() => _touchIndex = idx);
  }
}

class _LineChartPainter extends CustomPainter {
  final List<dynamic> data;
  final Color lineColor;
  final int? selectedIndex;
  final bool isDark;

  _LineChartPainter({
    required this.data,
    required this.lineColor,
    required this.selectedIndex,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.map((e) => (e["total_activity"] ?? 0) as int).fold(1, (a, b) => a > b ? a : b);
    final points = <Offset>[];
    final dx = size.width / math.max(data.length - 1, 1);

    for (int i = 0; i < data.length; i++) {
      final val = (data[i]["total_activity"] ?? 0) as int;
      final y = size.height - (val / maxVal * (size.height - 20)) - 10;
      points.add(Offset(i * dx, y));
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPoint1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final controlPoint2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, p1.dx, p1.dy);
    }

    // Area fill gradient
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withOpacity(0.35),
          lineColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Line stroke
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Dots
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isSel = selectedIndex == i;
      final dotPaint = Paint()..color = isSel ? Colors.white : lineColor;
      canvas.drawCircle(p, isSel ? 6 : 3.5, dotPaint);
      if (isSel) {
        final ringPaint = Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(p, 6, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// 6. Company Applications Horizontal Bar Chart
// ---------------------------------------------------------------------------
class CompanyApplicationsChart extends StatelessWidget {
  final List<dynamic> topCompanies;

  const CompanyApplicationsChart({super.key, required this.topCompanies});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final teal = AppColors.getSemanticColor("teal", isDark);

    final maxApps = topCompanies.map((c) => (c["applications"] ?? 0) as int).fold(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
          Text(
            "COMPANY APPLICATION DENSITY",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s16),
          if (topCompanies.isEmpty)
            Text("No applications logged yet", style: TextStyle(fontSize: 12, color: secondaryTextColor))
          else
            ...topCompanies.map((c) {
              final comp = c["company"] ?? "";
              final apps = (c["applications"] ?? 0) as int;
              final factor = (apps / maxApps).clamp(0.1, 1.0);

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(comp, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryTextColor)),
                        Text("$apps apps", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: borderColor.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: factor,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: teal,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
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
// 7. Resume Version Comparison Chart
// ---------------------------------------------------------------------------
class ResumeComparisonChart extends StatelessWidget {
  final List<dynamic> resumeVersions;

  const ResumeComparisonChart({super.key, required this.resumeVersions});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final violet = AppColors.getSemanticColor("violet", isDark);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
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
          Text(
            "RESUME PORTFOLIO & ATS CONVERSION",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor),
          ),
          const SizedBox(height: AppSpacing.s16),
          ...resumeVersions.map((rv) {
            final name = rv["version_name"] ?? "";
            final isMaster = (rv["is_master"] ?? false) as bool;
            final ats = (rv["ats_score"] as num?)?.toDouble() ?? 95.0;
            final apps = (rv["applications"] ?? 0) as int;
            final conv = (rv["conversion_rate"] as num?)?.toDouble() ?? 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.s12),
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: borderColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryTextColor)),
                            if (isMaster) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: violet.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text("MASTER", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: violet)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text("ATS $ats%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: violet)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text("$apps applications", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                      const SizedBox(width: 12),
                      Text("•  $conv% interview rate", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                    ],
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
