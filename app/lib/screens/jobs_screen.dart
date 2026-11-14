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

  bool _loading = true;
  List<dynamic> _queueJobs = [];
  List<dynamic> _maybeJobs = [];
  List<dynamic> _appliedJobs = [];
  List<dynamic> _blockedJobs = [];
  String _search = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchJobs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchJobs() async {
    setState(() => _loading = true);
    try {
      final all = await _api.getJobs();
      if (mounted) {
        setState(() {
          _queueJobs = all.where((j) => ["queued", "discovered", "scoring", "applying"].contains(j["status"])).toList();
          _maybeJobs = all.where((j) => j["status"] == "maybe").toList();
          _appliedJobs = all.where((j) => ["applied", "interview", "offer"].contains(j["status"])).toList();
          _blockedJobs = all.where((j) => ["blocked", "skipped", "rejected"].contains(j["status"])).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _swipeMaybe(int jobId, bool accept) async {
    await _api.swipeMaybeJob(jobId, accept);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(accept ? "Job queued for applying!" : "Job dismissed.")),
    );
    _fetchJobs();
  }

  void _showJobDetail(Map<String, dynamic> job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        return DraggableScrollableSheet(
          initialChildSize: 0.75,
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
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.borderHairlineDark : AppColors.borderHairlineLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(job["company"] ?? "", style: theme.textTheme.titleLarge),
                          const SizedBox(height: AppSpacing.s4),
                          Text(job["title"] ?? "", style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: AppSpacing.s6),
                      decoration: BoxDecoration(
                        color: (job["score"] ?? 0) >= 4.0
                            ? AppColors.accentLight.withOpacity(0.12)
                            : AppColors.warningLight.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(AppRadii.badge),
                      ),
                      child: Text(
                        "${job["score"] ?? 0.0} / 5.0",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: (job["score"] ?? 0) >= 4.0 ? AppColors.accentLight : AppColors.warningLight,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.s16),
                Text("Evaluation Reasoning:", style: theme.textTheme.labelSmall),
                const SizedBox(height: AppSpacing.s4),
                Text(job["score_reason"] ?? "Meets target criteria.", style: theme.textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.s16),
                Text("Location: ${job["location"] ?? "India"}", style: theme.textTheme.bodyMedium),
                Text("Portal / ATS: ${job["source"] ?? "Greenhouse"}", style: theme.textTheme.bodyMedium),
                Text("Status: ${(job["status"] ?? "").toString().toUpperCase()}", style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.s24),
                if (job["status"] == "maybe") ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
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
                          style: FilledButton.styleFrom(backgroundColor: AppColors.accentLight),
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
        );
      },
    );
  }

  Widget _buildJobList(List<dynamic> list, {bool isMaybeTab = false}) {
    final filtered = list.where((j) {
      if (_search.isEmpty) return true;
      final query = _search.toLowerCase();
      final c = (j["company"] ?? "").toString().toLowerCase();
      final t = (j["title"] ?? "").toString().toLowerCase();
      return c.contains(query) || t.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text("No jobs in this view.", style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final j = filtered[i];
        final score = (j["score"] ?? 0.0) as num;

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.s12),
          child: ListTile(
            onTap: () => _showJobDetail(j),
            title: Text(j["company"] ?? "", style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(j["title"] ?? "", style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  "${j["location"] ?? "India"} • ${j["source"] ?? ""}",
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: score >= 4.0 ? AppColors.accentLight.withOpacity(0.1) : AppColors.warningLight.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppRadii.badge),
                  ),
                  child: Text(
                    "$score",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: score >= 4.0 ? AppColors.accentLight : AppColors.warningLight,
                    ),
                  ),
                ),
                if (isMaybeTab) ...[
                  const SizedBox(width: AppSpacing.s8),
                  IconButton(
                    icon: const Icon(Icons.check, size: 20, color: AppColors.accentLight),
                    onPressed: () => _swipeMaybe(j["id"], true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.blockedLight),
                    onPressed: () => _swipeMaybe(j["id"], false),
                  ),
                ],
              ],
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
        title: const Text("Jobs & Tracker", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accentLight,
          indicatorColor: AppColors.accentLight,
          tabs: [
            Tab(text: "Queue (${_queueJobs.length})"),
            Tab(text: "Maybe (${_maybeJobs.length})"),
            Tab(text: "Applied (${_appliedJobs.length})"),
            Tab(text: "Blocked (${_blockedJobs.length})"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
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
                      _buildJobList(_appliedJobs),
                      _buildJobList(_blockedJobs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
