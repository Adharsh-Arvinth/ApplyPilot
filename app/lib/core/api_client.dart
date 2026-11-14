import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  // Defaults: Tailscale PC address or auto web origin
  String _baseUrl = "http://100.97.30.113:8000";
  String _token = "mApIGVEyORqpXbJzPhrhLPk9pRaS_vPOFyxH07nuPV4";

  String get baseUrl => _baseUrl;
  String get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    String defaultUrl = "http://100.97.30.113:8000";
    if (kIsWeb && Uri.base.origin.startsWith("http")) {
      defaultUrl = Uri.base.origin;
    }
    _baseUrl = prefs.getString("server_url") ?? defaultUrl;
    _token = prefs.getString("auth_token") ?? "mApIGVEyORqpXbJzPhrhLPk9pRaS_vPOFyxH07nuPV4";
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
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/profile"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception("Failed to load profile: ${res.statusCode}");
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

  // 3. Answer Bank
  Future<List<dynamic>> getAnswerBank({String? search, String? category}) async {
    var uri = Uri.parse("$_baseUrl/api/v1/answer-bank");
    final params = <String, String>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (category != null && category.isNotEmpty) params['category'] = category;
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

  // 4. Jobs & Applications
  Future<List<dynamic>> getJobs({String? status, String? search}) async {
    var uri = Uri.parse("$_baseUrl/api/v1/jobs");
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<void> swipeMaybeJob(int jobId, bool accept) async {
    await http.post(
      Uri.parse("$_baseUrl/api/v1/jobs/$jobId/swipe"),
      headers: _headers(),
      body: jsonEncode({"action": accept ? "queue" : "dismiss"}),
    );
  }

  // 5. Needs You Inbox
  Future<List<dynamic>> getNeedsYou() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/needs-you"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }

  Future<void> resolveNeedsYou(int id, String answer, {bool saveToBank = true}) async {
    final res = await http.post(
      Uri.parse("$_baseUrl/api/v1/needs-you/$id/resolve"),
      headers: _headers(),
      body: jsonEncode({
        "answer": answer,
        "save_to_answer_bank": saveToBank,
        "mode": "always_use"
      }),
    );
    if (res.statusCode != 200) {
      throw Exception("Failed to resolve question: ${res.statusCode}");
    }
  }

  // 6. Stats & Logs
  Future<Map<String, dynamic>> getStats() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/stats"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {
      "daily_applied": 0,
      "daily_cap": 100,
      "needs_you_count": 0,
      "maybe_count": 0,
      "blocked_count": 0,
      "interview_count": 0,
      "queue_count": 0,
    };
  }

  Future<List<dynamic>> getRunLogs() async {
    final res = await http.get(Uri.parse("$_baseUrl/api/v1/logs"), headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return [];
  }
}
