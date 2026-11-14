import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/api_client.dart';
import '../core/motion.dart';

class ApplicationTrackerScreen extends StatefulWidget {
  const ApplicationTrackerScreen({super.key});

  @override
  State<ApplicationTrackerScreen> createState() => _ApplicationTrackerScreenState();
}

class _ApplicationTrackerScreenState extends State<ApplicationTrackerScreen> with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  bool _isKanban = false;
  String _searchQuery = "";
  String _selectedStage = "queue"; // queue, maybe, applied, skipped, blocked

  List<dynamic> _allJobs = [];
  Map<String, dynamic> _kanbanData = {};

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() => _loading = true);
    try {
      final jobsFuture = _api.getJobs();
      final kanbanFuture = _api.getKanbanJobs();
      final results = await Future.wait([jobsFuture, kanbanFuture]);
      if (mounted) {
        setState(() {
          _allJobs = results[0] as List<dynamic>;
          _kanbanData = results[1] as Map<String, dynamic>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetailModal(dynamic job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApplicationDetailSheet(job: job, onUpdated: _loadApplications),
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

    final queueCount = _allJobs.where((j) => ["queued", "approved"].contains(j["status"])).length;
    final maybeCount = _allJobs.where((j) => ["maybe", "evaluated", "discovered"].contains(j["status"])).length;
    final appliedCount = _allJobs.where((j) => ["applied", "submitted", "dry_run", "interview", "offer"].contains(j["status"])).length;
    final skippedCount = _allJobs.where((j) => ["skipped", "cooldown", "below_salary", "ineligible"].contains(j["status"])).length;
    final blockedCount = _allJobs.where((j) => ["blocked", "captcha", "auth_required", "failed"].contains(j["status"])).length;

    final filteredJobs = _allJobs.where((j) {
      final matchSearch = _searchQuery.isEmpty ||
          (j["company"] ?? "").toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (j["title"] ?? "").toString().toLowerCase().contains(_searchQuery.toLowerCase());
      
      final st = (j["status"] ?? "").toString().toLowerCase();
      bool matchTab = true;
      if (_selectedStage == "queue") {
        matchTab = st == "queued" || st == "approved";
      } else if (_selectedStage == "maybe") {
        matchTab = st == "maybe" || st == "evaluated" || st == "discovered";
      } else if (_selectedStage == "applied") {
        matchTab = st == "applied" || st == "submitted" || st == "dry_run" || st == "interview" || st == "offer";
      } else if (_selectedStage == "skipped") {
        matchTab = st == "skipped" || st == "cooldown" || st == "below_salary" || st == "ineligible";
      } else if (_selectedStage == "blocked") {
        matchTab = st == "blocked" || st == "captcha" || st == "auth_required" || st == "failed";
      }
      return matchSearch && matchTab;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Application Tracker",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primaryTextColor),
        ),
        actions: [
          IconButton(
            icon: Icon(_isKanban ? Icons.view_list_outlined : Icons.view_kanban_outlined),
            tooltip: _isKanban ? "Switch to List View" : "Switch to Kanban View",
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() => _isKanban = !_isKanban);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadApplications,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter & Search Controls
          Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s12),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: "Search applications by company or role...",
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
                if (!_isKanban) ...[
                  const SizedBox(height: AppSpacing.s8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill("Queue ($queueCount)", "queue", accentGreen),
                        const SizedBox(width: AppSpacing.s8),
                        _buildFilterPill("Maybe ($maybeCount)", "maybe", brassColor),
                        const SizedBox(width: AppSpacing.s8),
                        _buildFilterPill("Applied ($appliedCount)", "applied", AppColors.successEmerald),
                        const SizedBox(width: AppSpacing.s8),
                        _buildFilterPill("Skipped ($skippedCount)", "skipped", AppColors.warningLight),
                        const SizedBox(width: AppSpacing.s8),
                        _buildFilterPill("Blocked ($blockedCount)", "blocked", AppColors.errorCoral),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Content Area
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: accentGreen))
                : _isKanban
                    ? _buildKanbanView(cardBg, borderColor, primaryTextColor, secondaryTextColor, accentGreen)
                    : _buildListView(filteredJobs, cardBg, borderColor, primaryTextColor, secondaryTextColor, accentGreen, brassColor),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String value, Color accent) {
    final selected = _selectedStage == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedStage = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: selected ? accent : AppColors.hairlineBorder),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.pureWhite : AppColors.mutedGray),
        ),
      ),
    );
  }

  Widget _buildListView(
    List<dynamic> jobs,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentGreen,
    Color brassColor,
  ) {
    if (jobs.isEmpty) {
      return Center(
        child: Text("No applications found in this view.", style: TextStyle(color: secondaryTextColor)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: jobs.length,
      itemBuilder: (context, idx) {
        final job = jobs[idx];
        final apps = (job["applications"] as List<dynamic>?) ?? [];
        final latestApp = apps.isNotEmpty ? apps.last : null;
        final status = (job["status"] ?? "discovered").toString();
        final score = (job["score"] as num? ?? 0.0).toDouble();
        final eligStatus = job["eligibility_status"] ?? "eligible";
        final blockedCat = job["blocked_category"] ?? "";
        final skipReason = job["skip_reason"] ?? job["eligibility_reason"] ?? "";
        final matchingSkills = (job["matching_skills"] as List<dynamic>?) ?? [];
        final missingSkills = (job["missing_skills"] as List<dynamic>?) ?? [];

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final emerald = AppColors.getSemanticColor("emerald", isDark);
        final amber = AppColors.getSemanticColor("amber", isDark);
        final coral = AppColors.getSemanticColor("coral", isDark);
        final dotColor = score >= 4.0 ? emerald : (score >= 3.0 ? amber : coral);

        return MotionFadeSlide(
          index: idx,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: Material(
              color: cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                side: BorderSide(color: borderColor),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.card),
                onTap: () => _openDetailModal(job),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              job["company"] ?? "",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: secondaryTextColor),
                            ),
                          ),
                          if (score > 0) ...[
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
                            const SizedBox(width: AppSpacing.s8),
                          ],
                          _buildStatusPill(
                            status,
                            accentGreen,
                            brassColor,
                            latestApp: latestApp is Map<String, dynamic> ? latestApp : null,
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Text(
                      job["title"] ?? "",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primaryTextColor),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, size: 12, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(job["location"] ?? "India", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                        const SizedBox(width: 12),
                        Icon(Icons.work_outline, size: 12, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(job["experience_required"] ?? "0-1 yrs", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                        const SizedBox(width: 12),
                        Icon(Icons.history, size: 12, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(
                          latestApp != null
                              ? (latestApp['status'] == 'dry_run'
                                  ? "Simulated ${latestApp['submitted_at'].toString().split('T')[0]}"
                                  : "Applied ${latestApp['submitted_at'].toString().split('T')[0]}")
                              : "Tracked",
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                      ],
                    ),
                    // Stage A & Blocked Reason Badges
                    if (blockedCat.toString().isNotEmpty || eligStatus == "ineligible") ...[
                      const SizedBox(height: AppSpacing.s8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10, vertical: AppSpacing.s6),
                        decoration: BoxDecoration(
                          color: AppColors.errorCoral.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(AppRadii.control),
                          border: Border.all(color: AppColors.errorCoral.withOpacity(0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.block, size: 14, color: AppColors.errorCoral),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                skipReason.toString().isNotEmpty ? skipReason : "Ineligible for auto-apply: Experience requirements exceed early-career profile.",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.errorCoral),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Skills Preview Chips
                    if (matchingSkills.isNotEmpty || missingSkills.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          ...matchingSkills.take(3).map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.successEmerald.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppRadii.badge),
                            ),
                            child: Text("✓ $s", style: const TextStyle(fontSize: 10, color: AppColors.successEmerald, fontWeight: FontWeight.w600)),
                          )),
                          ...missingSkills.take(2).map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: secondaryTextColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(AppRadii.badge),
                            ),
                            child: Text("• $s", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                          )),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ));
      },
    );
  }

  Widget _buildKanbanView(
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentGreen,
  ) {
    final stages = [
      {"key": "approved", "label": "Approved (Queue)"},
      {"key": "submitted", "label": "Submitted"},
      {"key": "interview", "label": "Interview"},
      {"key": "offer", "label": "Offer Received"},
      {"key": "rejected", "label": "Closed / Rejected"},
    ];

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: stages.map((st) {
        final list = (_kanbanData[st["key"]] as List<dynamic>?) ?? [];
        return Container(
          width: 260,
          margin: const EdgeInsets.only(right: AppSpacing.s16),
          decoration: BoxDecoration(
            color: cardBg.withOpacity(0.5),
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column Header
              Container(
                padding: const EdgeInsets.all(AppSpacing.s12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(st["label"]!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(AppRadii.badge)),
                      child: Text("${list.length}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text("Empty", style: TextStyle(fontSize: 12, color: secondaryTextColor)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.s8),
                        itemCount: list.length,
                        itemBuilder: (ctx, i) {
                          final job = list[i];
                          return GestureDetector(
                            onTap: () => _openDetailModal(job),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppSpacing.s8),
                              padding: const EdgeInsets.all(AppSpacing.s12),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(AppRadii.control),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(job["company"] ?? "", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                                  const SizedBox(height: 2),
                                  Text(job["title"] ?? "", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(job["location"] ?? "", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                                      Text("${job['score']} ★", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentGreen)),
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
      }).toList(),
    );
  }

  Widget _buildStatusPill(String status, Color accentGreen, Color brassColor, {Map<String, dynamic>? latestApp}) {
    Color col = accentGreen;
    String displayStatus = status;

    final appStatus = latestApp?["status"]?.toString().toLowerCase();
    if (appStatus == "dry_run" || status == "dry_run") {
      displayStatus = "DRY RUN";
      col = const Color(0xFF0284C7); // Sky/Cyan 600 - safe simulation indicator
    } else if (appStatus == "submitted" || status == "submitted") {
      displayStatus = "SUBMITTED";
      col = AppColors.successEmerald;
    } else if (status == "interview" || status == "offer") {
      col = brassColor;
    } else if (status == "rejected" || status == "blocked") {
      col = AppColors.errorLight;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        color: col.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: col.withOpacity(0.3)),
      ),
      child: Text(
        displayStatus.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: col),
      ),
    );
  }
}

class _ApplicationDetailSheet extends StatefulWidget {
  final dynamic job;
  final VoidCallback onUpdated;

  const _ApplicationDetailSheet({required this.job, required this.onUpdated});

  @override
  State<_ApplicationDetailSheet> createState() => _ApplicationDetailSheetState();
}

class _ApplicationDetailSheetState extends State<_ApplicationDetailSheet> {
  final ApiClient _api = ApiClient();
  late String _status;
  late TextEditingController _notesController;
  late TextEditingController _recruiterController;
  DateTime? _followUpDate;

  final List<String> _allStatuses = [
    "discovered", "evaluated", "approved", "preparing", "awaiting_review", "submitted", "interview", "offer", "rejected", "withdrawn"
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.job["status"] ?? "discovered";
    _notesController = TextEditingController(text: widget.job["notes"] ?? "");
    _recruiterController = TextEditingController(text: widget.job["recruiter_info"] ?? "");
    if (widget.job["follow_up_date"] != null) {
      try {
        _followUpDate = DateTime.parse(widget.job["follow_up_date"]);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _recruiterController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    HapticFeedback.mediumImpact();
    try {
      await _api.updateJobStatus(widget.job["id"], {
        "status": _status,
        "notes": _notesController.text.trim(),
        "recruiter_info": _recruiterController.text.trim(),
        "follow_up_date": _followUpDate?.toIso8601String(),
      });
      widget.onUpdated();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Application updated successfully.")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to update: $e")));
    }
  }

  void _openFullScreenshot(BuildContext context, String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (c, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                },
                errorBuilder: (c, e, s) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s24),
                    child: Text(
                      "Cannot load proof image over network: $e\nEnsure Windows host is online over Tailscale.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final primaryTextColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accentGreen = isDark ? AppColors.accentDark : AppColors.racingGreen;
    final borderColor = isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight;
    final apps = (widget.job["applications"] as List<dynamic>?) ?? [];
    final latestApp = apps.isNotEmpty ? apps.last : null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
              Text("Application Dossier", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: primaryTextColor)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          Text("${widget.job['company']} • ${widget.job['title']}", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: secondaryTextColor)),
          const SizedBox(height: AppSpacing.s16),
          Expanded(
            child: ListView(
              children: [
                // Assist-Only Banner if applicable
                if (widget.job["is_assist_only"] == true ||
                    widget.job["source"] == "naukri" ||
                    widget.job["source"] == "linkedin") ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.s16),
                    padding: const EdgeInsets.all(AppSpacing.s12),
                    decoration: BoxDecoration(
                      color: AppColors.getSemanticColor("amber", isDark).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(color: AppColors.getSemanticColor("amber", isDark).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 16, color: AppColors.getSemanticColor("amber", isDark)),
                            const SizedBox(width: 6),
                            Text(
                              "Assist-Only Flow (${widget.job['source']?.toString().toUpperCase() ?? 'PORTAL'})",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.getSemanticColor("amber", isDark)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "This application requires human submission on the portal to comply with platform access terms.",
                          style: TextStyle(fontSize: 11, height: 1.35, color: secondaryTextColor),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final u = widget.job["url"] ?? "";
                            if (u.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: u));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Application URL copied to clipboard!")));
                            }
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text("Copy Job URL", style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                  ),
                ],
                if (widget.job["quality_readiness_score"] != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.s16),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Application Readiness Score", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                        Row(
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: accentGreen)),
                            const SizedBox(width: 6),
                            Text(
                              "${((widget.job['quality_readiness_score'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)} / 5.0",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: primaryTextColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                // 1. Lifecycle Status Selector
                Text("LIFECYCLE STATUS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _allStatuses.contains(_status) ? _status : "discovered",
                  items: _allStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _status = val);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),

                // 2. Recruiter Contact Details
                Text("RECRUITER INFORMATION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(
                  controller: _recruiterController,
                  decoration: InputDecoration(
                    hintText: "e.g. Sarah Miller <sarah@company.com>",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),

                // 3. Notes & Context
                Text("NOTES & STRATEGY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Add recruiter feedback, interview rounds, salary discussions...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),

                // 4. Follow-up Date Picker
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("FOLLOW-UP DATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                        const SizedBox(height: 4),
                        Text(
                          _followUpDate != null ? DateFormat('MMM dd, yyyy').format(_followUpDate!) : "No reminder scheduled",
                          style: TextStyle(fontSize: 13, color: primaryTextColor),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _followUpDate ?? DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 180)),
                        );
                        if (picked != null) setState(() => _followUpDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: const Text("Select Date"),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),

                // 5. Submission Evidence & Proof
                Text("SUBMISSION EVIDENCE & AUTOMATION AUDIT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final formShot = (latestApp?["form_screenshot_url"] ?? latestApp?["form_screenshot"] ?? "").toString().trim();
                    final confirmShot = (latestApp?["confirmation_screenshot_url"] ?? latestApp?["confirmation_screenshot"] ?? "").toString().trim();
                    final screenshotRaw = confirmShot.isNotEmpty ? confirmShot : formShot;
                    String? screenshotUrl;
                    String? screenshotFilename;
                    if (screenshotRaw.isNotEmpty) {
                      screenshotFilename = screenshotRaw.replaceAll(r'\', '/').split('/').last;
                      if (screenshotFilename.isNotEmpty && screenshotFilename.endsWith(".png")) {
                        screenshotUrl = "${_api.baseUrl}/output/screenshots/$screenshotFilename";
                      }
                    }

                    final resumeRaw = (latestApp?["resume_file_url"] ?? latestApp?["resume_file"] ?? "").toString().trim();
                    String? resumeUrl;
                    String? resumeFilename;
                    if (resumeRaw.isNotEmpty && resumeRaw != "manual_tracking_submission" && resumeRaw != "test.pdf") {
                      resumeFilename = resumeRaw.replaceAll(r'\', '/').split('/').last;
                      resumeUrl = "${_api.baseUrl}/output/resumes/$resumeFilename";
                    }

                    final appStatus = (latestApp?["status"] ?? widget.job["status"] ?? "").toString().toLowerCase();
                    final isDryRun = appStatus == "dry_run";
                    final isSubmitted = appStatus == "submitted";

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // A. Mode & Safety Explanation Pill
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.s12),
                          decoration: BoxDecoration(
                            color: isDryRun
                                ? const Color(0xFF0284C7).withOpacity(0.08)
                                : (isSubmitted ? AppColors.successEmerald.withOpacity(0.08) : (isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight)),
                            borderRadius: BorderRadius.circular(AppRadii.control),
                            border: Border.all(
                              color: isDryRun
                                  ? const Color(0xFF0284C7).withOpacity(0.25)
                                  : (isSubmitted ? AppColors.successEmerald.withOpacity(0.25) : borderColor),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isDryRun ? Icons.science_outlined : (isSubmitted ? Icons.verified : Icons.help_outline),
                                    size: 16,
                                    color: isDryRun ? const Color(0xFF0284C7) : (isSubmitted ? AppColors.successEmerald : secondaryTextColor),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isDryRun
                                        ? "Simulated Dry-Run (Safety Gate Active)"
                                        : (isSubmitted ? "Live Application Submitted" : "Tracking Record"),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isDryRun ? const Color(0xFF0284C7) : (isSubmitted ? AppColors.successEmerald : primaryTextColor),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isDryRun
                                    ? "Form filled automatically by Playwright on ATS (Greenhouse/Lever). All fields validated. Final submit was safely halted because GO_LIVE_ENABLED is set to False."
                                    : (isSubmitted
                                        ? "Application was submitted live to the ATS with complete candidate profile and tailored resume."
                                        : "This role is tracked in your pipeline. Automated form execution pending."),
                                style: TextStyle(fontSize: 11, height: 1.35, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        ),

                        // B. Screenshot Preview Card
                        if (screenshotUrl != null) ...[
                          const SizedBox(height: AppSpacing.s12),
                          Text("ATS FORM SCREENSHOT PROOF", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                              borderRadius: BorderRadius.circular(AppRadii.control),
                              border: Border.all(color: borderColor),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _openFullScreenshot(context, screenshotUrl!, "${widget.job['company']} Form Fill Proof"),
                                  child: Stack(
                                    children: [
                                      Image.network(
                                        screenshotUrl,
                                        height: 180,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                        loadingBuilder: (ctx, child, progress) {
                                          if (progress == null) return child;
                                          return Container(
                                            height: 180,
                                            color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                          );
                                        },
                                        errorBuilder: (ctx, err, stack) => Container(
                                          height: 100,
                                          padding: const EdgeInsets.all(AppSpacing.s12),
                                          alignment: Alignment.center,
                                          child: Text(
                                            "Screenshot saved on host: $screenshotFilename\n(Ensure Windows backend is reachable over Tailscale)",
                                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 8,
                                        right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.7),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.fullscreen, size: 14, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text("Tap to Zoom", style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(AppSpacing.s8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.photo_camera_outlined, size: 14, color: AppColors.mutedGray),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          screenshotFilename ?? "",
                                          style: TextStyle(fontSize: 10, color: secondaryTextColor),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _openFullScreenshot(context, screenshotUrl!, "${widget.job['company']} Form Fill Proof"),
                                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                        child: const Text("Inspect Full Proof", style: TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // C. Tailored Resume File
                        if (resumeUrl != null && resumeFilename != null) ...[
                          const SizedBox(height: AppSpacing.s12),
                          Text("GENERATED TAILORED RESUME", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.s12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceSubtleDark : AppColors.surfaceSubtleLight,
                              borderRadius: BorderRadius.circular(AppRadii.control),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.picture_as_pdf_outlined, size: 20, color: AppColors.errorCoral),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        resumeFilename,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text("Tailored by Gemini for ATS compliance", style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 16),
                                  tooltip: "Copy Resume Link",
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: resumeUrl!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Resume PDF URL copied to clipboard!")),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentGreen,
                foregroundColor: AppColors.pureWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              ),
              child: const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
