import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/motion.dart';
import 'ai_assistant_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final ApiClient _api = ApiClient();

  bool _loading = true;
  bool _discovering = false;
  String _searchQuery = "";
  String _selectedWorkMode = "all"; // all, remote, hybrid, onsite
  double _minScoreThreshold = 0.0;
  List<dynamic> _jobs = [];
  final Set<int> _expandedJobIds = {};

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    try {
      final workMode = _selectedWorkMode == "all" ? null : _selectedWorkMode;
      final jobs = await _api.getJobs(
        search: _searchQuery.isEmpty ? null : _searchQuery,
        workMode: workMode,
        minScore: _minScoreThreshold > 0.0 ? _minScoreThreshold : null,
      );
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _triggerDiscoveryRun() async {
    HapticFeedback.heavyImpact();
    setState(() => _discovering = true);
    try {
      final resDisc = await _api.triggerDiscovery();
      final resEval = await _api.triggerEvaluation();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Discovery complete: ${resDisc['new_jobs_discovered']} new postings, ${resEval['jobs_scored']} scored.",
          ),
        ),
      );
      await _loadJobs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Discovery failed: $e")));
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _approveJob(int jobId) async {
    HapticFeedback.lightImpact();
    try {
      await _api.swipeJob(jobId, "approve");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Job approved & added to application queue.")));
      _loadJobs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _excludeCompany(int jobId, String company) async {
    HapticFeedback.mediumImpact();
    try {
      await _api.swipeJob(jobId, "exclude");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Added '$company' to Excluded Companies list.")),
      );
      _loadJobs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showTailoringModal(dynamic job) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TailoringSheet(job: job),
    );
  }

  void _showAiJobIntelligenceModal(dynamic job) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiJobIntelligenceSheet(job: job),
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
          "Discover Jobs",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(
            icon: _discovering
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar_outlined),
            tooltip: "Scan ATS Boards",
            onPressed: _discovering ? null : _triggerDiscoveryRun,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s12),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) {
                    _searchQuery = val;
                    _loadJobs();
                  },
                  decoration: InputDecoration(
                    hintText: "Search company, title, or skills...",
                    hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                    prefixIcon: Icon(Icons.search, size: 20, color: secondaryTextColor),
                    filled: true,
                    fillColor: cardBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: AppSpacing.s12),
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
                const SizedBox(height: AppSpacing.s8),
                // Work Mode Filter Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip("All Modes", "all", accentGreen),
                      const SizedBox(width: AppSpacing.s8),
                      _buildFilterChip("Remote", "remote", accentGreen),
                      const SizedBox(width: AppSpacing.s8),
                      _buildFilterChip("Hybrid", "hybrid", accentGreen),
                      const SizedBox(width: AppSpacing.s8),
                      _buildFilterChip("Onsite", "onsite", accentGreen),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Jobs List
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
                : _jobs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_outlined, size: 48, color: secondaryTextColor),
                            const SizedBox(height: AppSpacing.s12),
                            Text("No jobs match your filter criteria.", style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                            const SizedBox(height: AppSpacing.s4),
                            Text("Try adjusting filters or scan live ATS boards.", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                            const SizedBox(height: AppSpacing.s16),
                            ElevatedButton.icon(
                              onPressed: _triggerDiscoveryRun,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentGreen,
                                foregroundColor: AppColors.pureWhite,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                              ),
                              icon: const Icon(Icons.radar, size: 16),
                              label: const Text("Scan Live Boards"),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadJobs,
                        color: accentGreen,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
                          itemCount: _jobs.length,
                          itemBuilder: (context, idx) {
                            final job = _jobs[idx];
                            final jobId = job["id"] as int;
                            final isExpanded = _expandedJobIds.contains(jobId);
                            final score = (job["score"] as num?)?.toDouble() ?? 0.0;
                            final fit = job["fit_breakdown"] as Map<String, dynamic>? ?? {};

                            final emerald = AppColors.getSemanticColor("emerald", isDark);
                            final amber = AppColors.getSemanticColor("amber", isDark);
                            final coral = AppColors.getSemanticColor("coral", isDark);
                            final dotColor = score >= 4.0 ? emerald : (score >= 3.0 ? amber : coral);

                            return MotionFadeSlide(
                              index: idx,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.s12),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(AppRadii.card),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(AppSpacing.s16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header: Company + Semantic Match Score Dot
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                job["company"] ?? "",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.5,
                                                  color: secondaryTextColor,
                                                ),
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: dotColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "${score.toStringAsFixed(1)} / 5.0",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: primaryTextColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.s4),
                                        // Job Title
                                        Text(
                                          job["title"] ?? "",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.s8),
                                        // Tags: Location, Mode, Salary, Experience
                                        Wrap(
                                          spacing: AppSpacing.s8,
                                          runSpacing: AppSpacing.s4,
                                          children: [
                                            if (job["is_assist_only"] == true || job["source"] == "naukri" || job["source"] == "linkedin")
                                              _buildInfoChip(Icons.shield_outlined, "ASSIST ONLY", brassColor),
                                            _buildInfoChip(Icons.place_outlined, job["location"] ?? "India", secondaryTextColor),
                                            _buildInfoChip(Icons.work_outline, (job["work_mode"] ?? "remote").toString().toUpperCase(), secondaryTextColor),
                                            if (job["salary_raw"] != null && job["salary_raw"].toString().isNotEmpty)
                                              _buildInfoChip(Icons.payments_outlined, job["salary_raw"], accentGreen)
                                            else
                                              _buildInfoChip(Icons.payments_outlined, "Salary Unspecified", secondaryTextColor),
                                            _buildInfoChip(Icons.timeline_outlined, job["experience_required"] ?? "0-1 years", secondaryTextColor),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.s12),
                                        // Score Rationale snippet
                                        if (job["score_reason"] != null && job["score_reason"].toString().isNotEmpty)
                                          Text(
                                            job["score_reason"],
                                            style: TextStyle(fontSize: 12, height: 1.35, color: secondaryTextColor),
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Expandable Explainable Fit Factors
                                  if (isExpanded)
                                    Container(
                                      padding: const EdgeInsets.all(AppSpacing.s16),
                                      decoration: BoxDecoration(
                                        color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                                        border: Border(top: BorderSide(color: borderColor)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "EXPLAINABLE FIT BREAKDOWN",
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.0,
                                              color: secondaryTextColor,
                                            ),
                                          ),
                                          const SizedBox(height: AppSpacing.s8),
                                          _buildFactorRow("Skills & Stack", job["skills_score"] ?? 0, fit["skills"], primaryTextColor, secondaryTextColor),
                                          _buildFactorRow("Experience Window", job["experience_score"] ?? 0, fit["experience"], primaryTextColor, secondaryTextColor),
                                          _buildFactorRow("Location & Mode", job["location_score"] ?? 0, fit["location"], primaryTextColor, secondaryTextColor),
                                          _buildFactorRow("Education & Proof", job["education_score"] ?? 0, fit["education"], primaryTextColor, secondaryTextColor),
                                          _buildFactorRow("Compensation Range", job["compensation_score"] ?? 0, fit["compensation"], primaryTextColor, secondaryTextColor),
                                        ],
                                      ),
                                    ),

                                  // Action Bar
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
                                    decoration: BoxDecoration(
                                      border: Border(top: BorderSide(color: borderColor)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              if (isExpanded) {
                                                _expandedJobIds.remove(jobId);
                                              } else {
                                                _expandedJobIds.add(jobId);
                                              }
                                            });
                                          },
                                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                          icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: secondaryTextColor),
                                          label: Text(isExpanded ? "Hide Breakdown" : "Explain Match", style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                                        ),
                                        Row(
                                          children: [
                                            // Gemini Job Intelligence & Interview Prep
                                            IconButton(
                                              icon: const Icon(Icons.auto_awesome, size: 18, color: ApplyPilotColors.aiViolet),
                                              tooltip: "Gemini Intelligence & Interview Prep",
                                              onPressed: () => _showAiJobIntelligenceModal(job),
                                            ),
                                            // Tailor Simulator
                                            IconButton(
                                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                              tooltip: "Preview Tailored Resume",
                                              onPressed: () => _showTailoringModal(job),
                                            ),
                                            // Exclude Company
                                            IconButton(
                                              icon: const Icon(Icons.block_outlined, size: 18),
                                              tooltip: "Exclude Company",
                                              onPressed: () => _excludeCompany(jobId, job["company"] ?? ""),
                                            ),
                                            const SizedBox(width: AppSpacing.s4),
                                            if (job["is_assist_only"] == true || job["source"] == "naukri" || job["source"] == "linkedin")
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  final u = job["url"] ?? "";
                                                  if (u.isNotEmpty) {
                                                    Clipboard.setData(ClipboardData(text: u));
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assist-only job URL copied to clipboard!")));
                                                  }
                                                },
                                                icon: const Icon(Icons.open_in_new, size: 12),
                                                label: const Text("Assist", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: brassColor,
                                                  foregroundColor: AppColors.pureWhite,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s8),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              )
                                            else
                                              ElevatedButton(
                                                onPressed: () => _approveJob(jobId),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: accentGreen,
                                                  foregroundColor: AppColors.pureWhite,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                child: const Text("Approve", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ));
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Color accent) {
    final selected = _selectedWorkMode == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedWorkMode = value);
        _loadJobs();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? accent : AppColors.hairlineBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.pureWhite : AppColors.mutedGray,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  Widget _buildFactorRow(String name, dynamic scoreNum, dynamic reason, Color textPrimary, Color textSecondary) {
    final score = (scoreNum as num?)?.toDouble() ?? 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textPrimary)),
          ),
          Text("${score.toInt()}%  ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: score >= 80 ? AppColors.successLight : AppColors.warningLight)),
          Expanded(
            child: Text(
              reason?.toString() ?? "Standard ATS factor",
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TailoringSheet extends StatefulWidget {
  final dynamic job;
  const _TailoringSheet({required this.job});

  @override
  State<_TailoringSheet> createState() => _TailoringSheetState();
}

class _TailoringSheetState extends State<_TailoringSheet> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  Map<String, dynamic> _result = {};

  @override
  void initState() {
    super.initState();
    _tailor();
  }

  Future<void> _tailor() async {
    try {
      final res = await _api.tailorResumeSimulation({
        "company": widget.job["company"],
        "role": widget.job["title"],
        "job_id": widget.job["id"],
      });
      if (mounted) {
        setState(() {
          _result = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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
      padding: const EdgeInsets.all(AppSpacing.s24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Resume Intelligence & Tailoring", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: primaryTextColor)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text("${widget.job['company']} • ${widget.job['title']}", style: TextStyle(fontSize: 13, color: secondaryTextColor)),
          const SizedBox(height: AppSpacing.s16),
          if (_loading)
            Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.s24), child: CircularProgressIndicator(color: accentGreen)))
          else ...[
            Row(
              children: [
                _buildMetricCard("ATS Compatibility", "${_result['ats_score']}%", AppColors.successLight, cardBg),
                const SizedBox(width: AppSpacing.s12),
                _buildMetricCard("Keyword Match", "${_result['keyword_coverage_percent']}%", accentGreen, cardBg),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Text("MATCHED VERIFIED SKILLS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
            const SizedBox(height: AppSpacing.s6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ((_result["matched_keywords"] as List<dynamic>?) ?? []).map<Widget>((kw) {
                return Chip(
                  label: Text(kw, style: const TextStyle(fontSize: 11)),
                  backgroundColor: accentGreen.withOpacity(0.12),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text("TAILORING DECISIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
            const SizedBox(height: AppSpacing.s6),
            ...((_result["changes_applied"] as List<dynamic>?) ?? []).map((ch) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: AppColors.successLight),
                    const SizedBox(width: 6),
                    Expanded(child: Text(ch, style: TextStyle(fontSize: 12, color: primaryTextColor))),
                  ],
                ),
              );
            }),
            const SizedBox(height: AppSpacing.s16),
            Text("Output: ${_result['filename']}", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: secondaryTextColor)),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _AiJobIntelligenceSheet extends StatefulWidget {
  final dynamic job;
  const _AiJobIntelligenceSheet({required this.job});

  @override
  State<_AiJobIntelligenceSheet> createState() => _AiJobIntelligenceSheetState();
}

class _AiJobIntelligenceSheetState extends State<_AiJobIntelligenceSheet> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  Map<String, dynamic> _intelligence = {};
  Map<String, dynamic> _prep = {};

  @override
  void initState() {
    super.initState();
    _fetchAiData();
  }

  Future<void> _fetchAiData() async {
    try {
      final intelFuture = _api.getJobIntelligence(
        jobId: widget.job["id"] is int ? widget.job["id"] : null,
        title: widget.job["title"],
        company: widget.job["company"],
        description: widget.job["score_reason"] ?? "",
      );
      final prepFuture = _api.generateInterviewPrep(
        jobId: widget.job["id"] is int ? widget.job["id"] : null,
        title: widget.job["title"],
        company: widget.job["company"],
        location: widget.job["location"],
      );

      final results = await Future.wait([intelFuture, prepFuture]);
      if (mounted) {
        setState(() {
          _intelligence = results[0];
          _prep = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final violet = ApplyPilotColors.aiViolet;

    final requiredSkills = (_intelligence["required_skills"] as List<dynamic>?) ?? [];
    final preferredSkills = (_intelligence["preferred_skills"] as List<dynamic>?) ?? [];
    final techQs = (_prep["technical_questions"] as List<dynamic>?) ?? [];
    final behavQs = (_prep["behavioral_questions"] as List<dynamic>?) ?? [];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: violet.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome, color: violet, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Gemini Job Intelligence", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: primaryTextColor)),
                      Text("Powered by Gemini 2.5 Flash", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                    ],
                  ),
                ],
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text("${widget.job['company']} • ${widget.job['title']}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor)),
          const Divider(height: 24),
          if (_loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: violet),
                    const SizedBox(height: 16),
                    Text("Gemini is extracting deep skill requirements...", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: secondaryTextColor)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  // Role Summary
                  if (_intelligence["summary"] != null) ...[
                    Text("EXECUTIVE ROLE SUMMARY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                    const SizedBox(height: 4),
                    Text(_intelligence["summary"], style: TextStyle(fontSize: 13, height: 1.4, color: primaryTextColor)),
                    const SizedBox(height: AppSpacing.s16),
                  ],

                  // Skills Breakdown
                  Text("REQUIRED CORE SKILLS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: requiredSkills.map((sk) {
                      return Chip(
                        label: Text(sk.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        backgroundColor: accentGreen.withOpacity(0.12),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  if (preferredSkills.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text("PREFERRED / BONUS SKILLS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: preferredSkills.map((sk) {
                        return Chip(
                          label: Text(sk.toString(), style: const TextStyle(fontSize: 11)),
                          backgroundColor: violet.withOpacity(0.12),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.s16),

                  // Legitimacy & Safety Check
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s12),
                    decoration: BoxDecoration(
                      color: (_intelligence["is_suspicious"] == true ? ApplyPilotColors.errorCoral : ApplyPilotColors.successEmerald).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(
                        color: (_intelligence["is_suspicious"] == true ? ApplyPilotColors.errorCoral : ApplyPilotColors.successEmerald).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _intelligence["is_suspicious"] == true ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                          size: 18,
                          color: _intelligence["is_suspicious"] == true ? ApplyPilotColors.errorCoral : ApplyPilotColors.successEmerald,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _intelligence["is_suspicious"] == true
                                ? "Warning: Listing flagged with suspicious patterns"
                                : "Verified Authentic Opportunity • Zero Scam Indicators",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _intelligence["is_suspicious"] == true ? ApplyPilotColors.errorCoral : ApplyPilotColors.successEmerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.s20),

                  // Interview Intelligence Section
                  Text("PREDICTED TECHNICAL INTERVIEW QUESTIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                  const SizedBox(height: 8),
                  ...techQs.map((q) {
                    final qMap = q as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      decoration: BoxDecoration(
                        color: isDark ? ApplyPilotColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        border: Border.all(color: isDark ? ApplyPilotColors.darkBorder : ApplyPilotColors.lightBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.help_outline, size: 16, color: violet),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(qMap["question"] ?? "", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor)),
                              ),
                            ],
                          ),
                          if (qMap["model_answer"] != null) ...[
                            const SizedBox(height: 6),
                            Text("Model Answer Focus: ${qMap['model_answer']}", style: TextStyle(fontSize: 11, height: 1.35, color: secondaryTextColor)),
                          ],
                        ],
                      ),
                    );
                  }),

                  if (behavQs.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text("BEHAVIORAL & CULTURE FIT QUESTIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: secondaryTextColor)),
                    const SizedBox(height: 8),
                    ...behavQs.map((q) {
                      final qMap = q as Map<String, dynamic>;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        decoration: BoxDecoration(
                          color: isDark ? ApplyPilotColors.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          border: Border.all(color: isDark ? ApplyPilotColors.darkBorder : ApplyPilotColors.lightBorder),
                        ),
                        child: Text(qMap["question"] ?? "", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor)),
                      );
                    }),
                  ],

                  const SizedBox(height: AppSpacing.s16),

                  // Launch Coach Button
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantScreen()));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: violet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text("Practice Mock Interview with Gemini"),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
