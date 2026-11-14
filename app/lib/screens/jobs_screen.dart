import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiClient();
  Timer? _liveTimer;

  bool _initialLoading = true;
  String? _fetchError;
  List<dynamic> _queueJobs = [];
  List<dynamic> _maybeJobs = [];
  List<dynamic> _appliedJobs = [];
  List<dynamic> _blockedJobs = [];
  String _search = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchJobs(isInitial: true);

    // Real-time engine synchronization every 1.5 seconds
    _liveTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) _fetchJobs(isInitial: false);
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchJobs({bool isInitial = false}) async {
    if (isInitial && mounted) setState(() => _initialLoading = true);
    try {
      final all = await _api.getJobs();
      if (mounted) {
        setState(() {
          _queueJobs = all.where((j) => ["queued", "discovered", "scoring", "applying"].contains(j["status"])).toList();
          _maybeJobs = all.where((j) => j["status"] == "maybe").toList();
          _appliedJobs = all.where((j) => ["applied", "interview", "offer", "submitted"].contains(j["status"])).toList();
          _blockedJobs = all.where((j) => ["blocked", "skipped", "rejected", "failed"].contains(j["status"])).toList();
          _fetchError = null;
          _initialLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = "Could not synchronize with Windows host: $e";
          if (isInitial) _initialLoading = false;
        });
      }
    }
  }

  Future<void> _swipeMaybe(int jobId, bool accept) async {
    await _api.swipeMaybeJob(jobId, accept);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? "Job queued for autonomous applying!" : "Job dismissed."),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    _fetchJobs();
  }

  void _showProofDialog(String screenshotName, String company, String role) {
    final imageUrl = "${_api.baseUrl}/output/screenshots/$screenshotName";
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Application Proof • $company", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(role, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (c, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 300,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.appleCrimson)),
                    );
                  },
                  errorBuilder: (c, err, stack) => Container(
                    height: 240,
                    color: const Color(0xFF1C1C1E),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 48),
                        const SizedBox(height: 12),
                        Text("Proof record: $screenshotName", style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showJobDetail(Map<String, dynamic> job) {
    final applications = (job["applications"] as List<dynamic>?) ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141416) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
            border: Border.all(
              color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
              width: 0.5,
            ),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) {
              return ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(AppSpacing.s24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s20),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              job["company"] ?? "",
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22, letterSpacing: -0.4),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              job["title"] ?? "",
                              style: TextStyle(fontSize: 15, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (job["score"] ?? 0) >= 4.0
                              ? AppColors.appleCrimson.withOpacity(0.15)
                              : Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(AppRadii.badge),
                        ),
                        child: Text(
                          "${job["score"] ?? 0.0} / 5.0",
                          style: TextStyle(
                            fontFamily: 'SF Pro Text',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: (job["score"] ?? 0) >= 4.0 ? AppColors.appleCrimson : Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.s16),
                  Divider(height: 1, color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight),
                  const SizedBox(height: AppSpacing.s16),

                  // Metadata cards
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(Icons.location_on_outlined, job["location"] ?? "India", isDark),
                      _buildChip(Icons.apartment_outlined, job["source"] ?? "ATS", isDark),
                      _buildChip(Icons.currency_rupee_outlined, "Min ₹7 LPA", isDark),
                      _buildChip(Icons.bolt, (job["status"] ?? "").toString().toUpperCase(), isDark, highlight: true),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.s20),
                  Text("AI FIT EVALUATION", style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.0, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                      border: Border.all(
                        color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      job["score_reason"] ?? "Meets target candidate criteria based on verified credentials.",
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                  ),

                  // Concrete Proof of Application Section
                  if (applications.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s24),
                    Row(
                      children: [
                        const Icon(Icons.verified, color: AppColors.iosGreen, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "APPLICATION PROOF & SCREENSHOTS",
                          style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.0, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...applications.map((app) {
                      final hasProof = (app["confirmation_screenshot"] ?? "").toString().isNotEmpty;
                      final screenshotName = app["confirmation_screenshot"] ?? "";
                      final resumeFile = app["resume_file"] ?? "";
                      final submittedAt = app["submitted_at"] ?? "";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(AppRadii.card),
                          border: Border.all(
                            color: AppColors.iosGreen.withOpacity(0.4),
                            width: 1.0,
                          ),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.iosGreen.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        (app["status"] ?? "Applied").toString().toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.iosGreen,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  submittedAt.toString().replaceAll("T", " ").split(".").first,
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey : Colors.black54),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (resumeFile.isNotEmpty)
                              Row(
                                children: [
                                  const Icon(Icons.description_outlined, size: 16, color: AppColors.appleCrimson),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      "Tailored Resume: $resumeFile",
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            if (hasProof) ...[
                              InkWell(
                                onTap: () => _showProofDialog(screenshotName, job["company"] ?? "", job["title"] ?? ""),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  height: 140,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white24, width: 0.5),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          "${_api.baseUrl}/output/screenshots/$screenshotName",
                                          width: double.infinity,
                                          height: 140,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(
                                            color: Colors.black26,
                                            alignment: Alignment.center,
                                            child: const Icon(Icons.image, size: 36, color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.zoom_in, color: Colors.white, size: 16),
                                            SizedBox(width: 6),
                                            Text("Tap to View Full Confirmation Screenshot", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ],

                  const SizedBox(height: AppSpacing.s24),
                  if (job["status"] == "maybe") ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _swipeMaybe(job["id"], false);
                            },
                            child: const Text("Dismiss"),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.appleCrimson,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.control)),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _swipeMaybe(job["id"], true);
                            },
                            child: const Text("Queue to Apply"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildChip(IconData icon, String text, bool isDark, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.appleCrimson.withOpacity(0.15)
            : (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlight ? AppColors.appleCrimson.withOpacity(0.3) : (isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: highlight ? AppColors.appleCrimson : Colors.grey),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              color: highlight ? AppColors.appleCrimson : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobList(List<dynamic> list, {bool isMaybeTab = false, bool isAppliedTab = false}) {
    final filtered = list.where((j) {
      if (_search.isEmpty) return true;
      final query = _search.toLowerCase();
      final c = (j["company"] ?? "").toString().toLowerCase();
      final t = (j["title"] ?? "").toString().toLowerCase();
      return c.contains(query) || t.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text("No jobs in this category yet.", style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s12),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final j = filtered[i];
        final score = (j["score"] ?? 0.0) as num;
        final apps = (j["applications"] as List<dynamic>?) ?? [];
        final hasProof = apps.isNotEmpty && (apps.first["confirmation_screenshot"] ?? "").toString().isNotEmpty;

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.s10),
          child: InkWell(
            onTap: () => _showJobDetail(j),
            borderRadius: BorderRadius.circular(AppRadii.card),
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
                          j["company"] ?? "",
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: score >= 4.0 ? AppColors.appleCrimson.withOpacity(0.14) : Colors.amber.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(AppRadii.badge),
                        ),
                        child: Text(
                          "$score",
                          style: TextStyle(
                            fontFamily: 'SF Pro Text',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: score >= 4.0 ? AppColors.appleCrimson : Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    j["title"] ?? "",
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${j["location"] ?? "India"} • ${j["source"] ?? "ATS"}",
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                      ),
                      if (hasProof)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.iosGreen.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image, size: 11, color: AppColors.iosGreen),
                              SizedBox(width: 4),
                              Text("Proof Attached", style: TextStyle(fontSize: 10, color: AppColors.iosGreen, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      if (isMaybeTab) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, size: 24, color: AppColors.iosGreen),
                              onPressed: () => _swipeMaybe(j["id"], true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, size: 24, color: AppColors.iosRed),
                              onPressed: () => _swipeMaybe(j["id"], false),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Jobs & Tracker", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.appleCrimson,
          indicatorColor: AppColors.appleCrimson,
          indicatorWeight: 2.5,
          tabs: [
            Tab(text: "Queue (${_queueJobs.length})"),
            Tab(text: "Maybe (${_maybeJobs.length})"),
            Tab(text: "Applied (${_appliedJobs.length})"),
            Tab(text: "Blocked (${_blockedJobs.length})"),
          ],
        ),
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.appleCrimson))
          : Column(
              children: [
                if (_fetchError != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s8, AppSpacing.s16, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.iosRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      border: Border.all(color: AppColors.iosRed.withOpacity(0.3), width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off, size: 16, color: AppColors.iosRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_fetchError!, style: const TextStyle(fontSize: 12, color: AppColors.iosRed)),
                        ),
                        TextButton(
                          onPressed: () => _fetchJobs(isInitial: true),
                          child: const Text("Retry", style: TextStyle(fontSize: 12, color: AppColors.iosRed, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s12, AppSpacing.s16, AppSpacing.s8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "Search company or role...",
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _search = val),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildJobList(_queueJobs),
                      _buildJobList(_maybeJobs, isMaybeTab: true),
                      _buildJobList(_appliedJobs, isAppliedTab: true),
                      _buildJobList(_blockedJobs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
