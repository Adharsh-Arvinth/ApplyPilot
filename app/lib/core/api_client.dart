import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Global reactive notifiers for system-wide synchronizations
final ValueNotifier<int> needsYouCountNotifier = ValueNotifier<int>(0);
final ValueNotifier<Map<String, dynamic>> automationStatusNotifier = ValueNotifier<Map<String, dynamic>>({});

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  static const String defaultTailscaleUrl = "";  // entered on the connect screen
  static const String defaultAuthToken = "";

  String _baseUrl = defaultTailscaleUrl;
  String _token = defaultAuthToken;

  String get baseUrl => _baseUrl;
  String get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    String defaultUrl = defaultTailscaleUrl;
    if (kIsWeb && Uri.base.origin.startsWith("http")) {
      defaultUrl = Uri.base.origin;
    }
    final savedUrl = prefs.getString("server_url") ?? "";
    _baseUrl = (savedUrl.isEmpty || savedUrl.contains("100.x.y.z")) ? defaultUrl : savedUrl;

    final savedToken = prefs.getString("auth_token") ?? "";
    _token = savedToken.isEmpty ? defaultAuthToken : savedToken;
  }

  Future<void> saveConnectionSettings(String url, String token) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    _token = token.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("server_url", _baseUrl);
    await prefs.setString("auth_token", _token);
  }

  Map<String, String> _headers() {
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $_token",
    };
  }

  // 1. Health
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/api/v1/health"),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {"status": "offline", "error": "HTTP ${res.statusCode}"};
    } catch (e) {
      return {"status": "offline", "error": e.toString()};
    }
  }

  // 2. Profile
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/profile"), headers: _headers()).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse("$_baseUrl/api/v1/profile"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to update profile: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> uploadResume(List<int> bytes, String filename) async {
    final request = http.MultipartRequest("POST", Uri.parse("$_baseUrl/api/v1/profile/resume"));
    request.headers.addAll({
      "Authorization": "Bearer $_token",
    });
    request.files.add(http.MultipartFile.fromBytes("file", bytes, filename: filename));
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception("Resume upload failed: ${response.statusCode} - ${response.body}");
  }

  Future<Map<String, dynamic>> togglePause() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/profile/toggle-pause"), headers: _headers());
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> toggleGoLive() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/profile/toggle-go-live"), headers: _headers());
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> getLockedFacts() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/profile/facts"), headers: _headers()).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> rotateToken() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/profile/rotate-token"), headers: _headers());
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final newToken = data["new_token"];
      if (newToken != null) {
        await saveConnectionSettings(_baseUrl, newToken);
      }
      return data;
    }
    throw Exception("Token rotation failed: ${res.statusCode}");
  }

  // 3. Answer Bank
  Future<List<dynamic>> getAnswerBank({String? search, String? category, bool? isVerified}) async {
    var uri = Uri.parse("$_baseUrl/api/v1/answer-bank");
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (category != null && category.isNotEmpty) params['category'] = category;
    if (isVerified != null) params['is_verified'] = isVerified.toString();
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to fetch answers: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> createAnswer(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/answer-bank"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 201 || res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to save answer: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> updateAnswer(int id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse("$_baseUrl/api/v1/answer-bank/$id"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to update answer: ${res.statusCode}");
  }

  Future<void> deleteAnswer(int id) async {
    final res = await http.delete(Uri.parse("$_baseUrl/api/v1/answer-bank/$id"), headers: _headers());
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception("Failed to delete answer: ${res.statusCode}");
    }
  }

  // 4. Jobs, Discovery & Kanban
  Future<List<dynamic>> getJobs({String? status, String? search, String? workMode, double? minScore}) async {
    var uri = Uri.parse("$_baseUrl/api/v1/jobs");
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (workMode != null && workMode.isNotEmpty) params['work_mode'] = workMode;
    if (minScore != null) params['min_score'] = minScore.toString();
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<Map<String, dynamic>> getKanbanJobs() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/jobs/kanban"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {};
  }

  Future<Map<String, dynamic>> updateJobStatus(int jobId, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse("$_baseUrl/api/v1/jobs/$jobId/status"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to update status: ${res.statusCode}");
  }

  Future<void> swipeJob(int jobId, String action) async {
    await http.post(
      Uri.parse("$_baseUrl/api/v1/jobs/$jobId/swipe"),
      headers: _headers(),
      body: jsonEncode({"action": action}),
    );
  }

  Future<void> approveJob(int jobId) async {
    await updateJobStatus(jobId, {"status": "queued"});
  }

  Future<void> skipJob(int jobId, {String reason = "Skipped by candidate"}) async {
    await updateJobStatus(jobId, {"status": "skipped", "skip_reason": reason});
  }

  Future<Map<String, dynamic>> triggerDiscovery() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/jobs/discover"), headers: _headers());
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> triggerEvaluation() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/jobs/evaluate"), headers: _headers());
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> applyToJob(int jobId) async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/jobs/$jobId/apply"), headers: _headers());
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> applyNext() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/jobs/apply-next"), headers: _headers());
    return jsonDecode(res.body);
  }

  // 5. Resume Intelligence
  Future<List<dynamic>> getResumes() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/resumes"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<Map<String, dynamic>> tailorResumeSimulation(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/resumes/tailor"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to tailor resume: ${res.statusCode}");
  }

  Future<void> setMasterResume(int id) async {
    await http.post(Uri.parse("$_baseUrl/api/v1/resumes/$id/set-master"), headers: _headers());
  }

  Future<void> deleteResume(int id) async {
    await http.delete(Uri.parse("$_baseUrl/api/v1/resumes/$id"), headers: _headers());
  }

  // 6. Analytics
  Future<Map<String, dynamic>> getAnalytics() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/analytics"), headers: _headers()).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return {};
  }

  // 7. Needs You Inbox
  Future<List<dynamic>> getNeedsYou() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/needs-you"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<void> resolveNeedsYou(int id, String answer, {bool saveToBank = true, String mode = "always_use"}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/needs-you/$id/resolve"),
      headers: _headers(),
      body: jsonEncode({
        "answer": answer,
        "save_to_answer_bank": saveToBank,
        "mode": mode
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Failed to resolve question: ${res.statusCode}");
    }
    if (needsYouCountNotifier.value > 0) {
      needsYouCountNotifier.value--;
    }
  }

  Future<void> dismissNeedsYou(int id) async {
    await http.post(Uri.parse("$_baseUrl/api/v1/needs-you/$id/dismiss"), headers: _headers());
    if (needsYouCountNotifier.value > 0) {
      needsYouCountNotifier.value--;
    }
  }

  Future<Map<String, dynamic>> rejectNeedsYou(int id, {bool blockCompany = false, String reason = "Rejected by candidate"}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/needs-you/$id/reject"),
      headers: _headers(),
      body: jsonEncode({"block_company": blockCompany, "reason": reason}),
    );
    if (needsYouCountNotifier.value > 0) {
      needsYouCountNotifier.value--;
    }
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {"status": "error"};
  }

  // 7b. Gemini Auto-Answer Review & Settings
  Future<List<dynamic>> getGeminiAnswers() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/needs-you/gemini-answers"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<void> approveGeminiAnswer(int id) async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/needs-you/gemini-answers/$id/approve"), headers: _headers());
    if (res.statusCode != 200) {
      throw Exception("Failed to approve Gemini answer: ${res.statusCode}");
    }
  }

  Future<void> editGeminiAnswer(int id, String newAnswer) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/needs-you/gemini-answers/$id/edit"),
      headers: _headers(),
      body: jsonEncode({"answer": newAnswer}),
    );
    if (res.statusCode != 200) {
      throw Exception("Failed to edit Gemini answer: ${res.statusCode}");
    }
  }

  Future<void> rejectGeminiAnswer(int id) async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/needs-you/gemini-answers/$id/reject"), headers: _headers());
    if (res.statusCode != 200) {
      throw Exception("Failed to reject Gemini answer: ${res.statusCode}");
    }
  }

  Future<Map<String, dynamic>> getGeminiSettings() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/profile/gemini-settings"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {};
  }

  Future<Map<String, dynamic>> updateGeminiSettings(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/profile/gemini-settings"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {};
  }

  // 8. Stats & Logs
  Future<Map<String, dynamic>> getStats() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/stats"), headers: _headers()).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final nyCount = (data["needs_you_count"] ?? 0) as int;
        needsYouCountNotifier.value = nyCount;
        automationStatusNotifier.value = data;
        return data;
      }
    } catch (_) {}
    return {
      "daily_applied": 0,
      "daily_cap": 100,
      "needs_you_count": 0,
      "maybe_count": 0,
      "skipped_count": 0,
      "blocked_count": 0,
      "interview_count": 0,
      "queue_count": 0,
      "total_tracked": 0,
      "automation_state": "idle"
    };
  }

  Future<Map<String, dynamic>> getAutomationStatus() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/automation/status"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {"state": "unknown", "can_resume": false};
  }

  Future<Map<String, dynamic>> pauseAutomation({String reason = "paused_by_user", String details = "Paused by user"}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/automation/pause?reason=$reason&details=${Uri.encodeComponent(details)}"),
      headers: _headers()
    );
    await getStats();
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> resumeAutomation({bool force = false}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/automation/resume?force=$force"),
      headers: _headers()
    );
    await getStats();
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception(jsonDecode(res.body)["detail"] ?? "Failed to resume automation.");
  }

  Future<List<dynamic>> getRunLogs() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/logs"), headers: _headers()).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> triggerBackup() async {
    final res = await http.post(Uri.parse("$_baseUrl/api/v1/backup"), headers: _headers());
    return jsonDecode(res.body);
  }

  Future<void> saveWidgetPreferences(Map<String, dynamic> prefsMap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("widget_preferences", jsonEncode(prefsMap));
    try {
      await updateProfile({"widget_preferences": prefsMap});
    } catch (_) {}
  }

  Future<Map<String, dynamic>> loadWidgetPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final localStr = prefs.getString("widget_preferences");
    if (localStr != null) {
      try {
        return jsonDecode(localStr) as Map<String, dynamic>;
      } catch (_) {}
    }
    return {};
  }

  // 10. Gemini AI Intelligence
  Future<Map<String, dynamic>> getAiStatus() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/ai/status"), headers: _headers());
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {"service": "Gemini AI", "is_connected": false, "error": "HTTP ${res.statusCode}"};
    } catch (e) {
      return {"service": "Gemini AI", "is_connected": false, "error": e.toString()};
    }
  }

  Future<Map<String, dynamic>> chatWithAdvisor(String message, {List<Map<String, String>> history = const []}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/ai/chat"),
      headers: _headers(),
      body: jsonEncode({
        "message": message,
        "history": history,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("AI Chat failed: ${res.statusCode} - ${res.body}");
  }

  Future<Map<String, dynamic>> getJobIntelligence({int? jobId, String? title, String? company, String? description}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/ai/job-intelligence"),
      headers: _headers(),
      body: jsonEncode({
        if (jobId != null) "job_id": jobId,
        if (title != null) "title": title,
        if (company != null) "company": company,
        if (description != null) "description": description,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Job intelligence failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> calculateMatch({
    int? jobId,
    String? title,
    String? company,
    String? location,
    String? workMode,
    String? experienceRequired,
    String? salaryRaw,
  }) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/ai/match-analysis"),
      headers: _headers(),
      body: jsonEncode({
        if (jobId != null) "job_id": jobId,
        if (title != null) "title": title,
        if (company != null) "company": company,
        if (location != null) "location": location,
        if (workMode != null) "work_mode": workMode,
        if (experienceRequired != null) "experience_required": experienceRequired,
        if (salaryRaw != null) "salary_raw": salaryRaw,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Match analysis failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> tailorResume({int? jobId, String? title, String? company, String? location, int? masterResumeId}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/ai/tailor-resume"),
      headers: _headers(),
      body: jsonEncode({
        if (jobId != null) "job_id": jobId,
        if (title != null) "title": title,
        if (company != null) "company": company,
        if (location != null) "location": location,
        if (masterResumeId != null) "master_resume_id": masterResumeId,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Resume tailoring failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> suggestAnswer(String questionText, {String fieldType = "text", int? jobId}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/ai/answer-suggest"),
      headers: _headers(),
      body: jsonEncode({
        "question_text": questionText,
        "field_type": fieldType,
        if (jobId != null) "job_id": jobId,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Answer suggestion failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> generateInterviewPrep({int? jobId, String? title, String? company, String? location}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/ai/interview-prep"),
      headers: _headers(),
      body: jsonEncode({
        if (jobId != null) "job_id": jobId,
        if (title != null) "title": title,
        if (company != null) "company": company,
        if (location != null) "location": location,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Interview prep generation failed: ${res.statusCode}");
  }

  // 11. Firebase Cloud Platform
  Future<Map<String, dynamic>> getFirebaseStatus() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/firebase/status"), headers: _headers());
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {"initialized": false, "error": "HTTP ${res.statusCode}"};
    } catch (e) {
      return {"initialized": false, "error": e.toString()};
    }
  }

  Future<Map<String, dynamic>> syncToCloud({bool syncJobs = true, bool syncProfile = true}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/firebase/sync"),
      headers: _headers(),
      body: jsonEncode({
        "sync_jobs": syncJobs,
        "sync_profile": syncProfile,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Firebase sync failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> sendTestNotification(String title, String body, {String? topic}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/firebase/test-notification"),
      headers: _headers(),
      body: jsonEncode({
        "title": title,
        "body": body,
        if (topic != null) "topic": topic,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Test notification failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> getCloudConfig() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/firebase/config"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {};
  }

  // 12. Candidate Intelligence Records
  Future<List<dynamic>> fetchCandidateRecords({String? category, String? verificationStatus}) async {
    String url = "$_baseUrl/api/v1/profile/records";
    final queryParams = <String>[];
    if (category != null && category.isNotEmpty) {
      queryParams.add("category=${Uri.encodeComponent(category)}");
    }
    if (verificationStatus != null && verificationStatus.isNotEmpty) {
      queryParams.add("verification_status=${Uri.encodeComponent(verificationStatus)}");
    }
    if (queryParams.isNotEmpty) {
      url += "?${queryParams.join('&')}";
    }
    final res = await http.get(Uri.parse(url), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<Map<String, dynamic>> createCandidateRecord(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/profile/records"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to create candidate record: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> updateCandidateRecord(int id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse("$_baseUrl/api/v1/profile/records/$id"),
      headers: _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to update candidate record: ${res.statusCode}");
  }

  Future<bool> deleteCandidateRecord(int id) async {
    final res = await http.delete(
      Uri.parse("$_baseUrl/api/v1/profile/records/$id"),
      headers: _headers(),
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> seedCandidateRecords() async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/profile/records/seed"),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {};
  }

  // 13. Needs You Summary & Bookmarking
  Future<Map<String, dynamic>> fetchNeedsYouSummary() async {
    try {
      final res = await http.get(Uri.parse("$_baseUrl/api/v1/needs-you/summary"), headers: _headers());
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> toggleSaveJob(int jobId) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/jobs/$jobId/toggle-save"),
      headers: _headers(),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to bookmark job: ${res.statusCode}");
  }
}
