import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';

/// Where the phone app finds the ApplyPilot backend on your PC.
/// Uses the same preference keys as the previous native app, so an
/// upgraded install keeps its saved server and token.
class ShellConfig {
  static const _urlKey = 'server_url';
  static const _tokenKey = 'auth_token';
  static const _connectedKey = 'shell_connected_once';

  final String serverUrl;
  final String token;

  /// True once a connection has succeeded (or an older install already had settings).
  final bool ready;

  const ShellConfig({required this.serverUrl, required this.token, required this.ready});

  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    u = u.replaceAll(RegExp(r'/+$'), '');
    if (u.endsWith('/app')) u = u.substring(0, u.length - 4);
    return u;
  }

  /// The cockpit URL. The token is only used on this first request: the server
  /// turns it into an HttpOnly cookie and the page removes it from the address bar.
  Uri cockpitUri() => Uri.parse('$serverUrl/app/').replace(queryParameters: {'token': token});

  static Future<ShellConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_urlKey) ?? '';
    final savedToken = prefs.getString(_tokenKey) ?? '';
    final hasSaved = savedUrl.isNotEmpty && !savedUrl.contains('100.x.y.z') && savedToken.isNotEmpty;
    return ShellConfig(
      serverUrl: hasSaved ? normalizeUrl(savedUrl) : ApiClient.defaultTailscaleUrl,
      token: savedToken.isNotEmpty ? savedToken : ApiClient.defaultAuthToken,
      ready: hasSaved || (prefs.getBool(_connectedKey) ?? false),
    );
  }

  static Future<ShellConfig> save(String url, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final cfg = ShellConfig(serverUrl: normalizeUrl(url), token: token.trim(), ready: true);
    await prefs.setString(_urlKey, cfg.serverUrl);
    await prefs.setString(_tokenKey, cfg.token);
    await prefs.setBool(_connectedKey, true);
    return cfg;
  }

  /// Tests can stand in for the network here.
  static http.Client? httpClient;

  /// Returns null when the server accepted the token, otherwise a readable reason.
  static Future<String?> test(String url, String token) async {
    final base = normalizeUrl(url);
    if (base.isEmpty) return 'Enter your server address.';
    if (token.trim().isEmpty) return 'Enter your access key.';
    try {
      final client = httpClient ?? http.Client();
      final res = await client
          .get(Uri.parse('$base/api/v1/health/authenticated'), headers: {'Authorization': 'Bearer ${token.trim()}'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) return null;
      if (res.statusCode == 401 || res.statusCode == 403) return 'That access key didn\'t work. Check it and try again.';
      if (res.statusCode == 429) return 'Too many tries. Wait a few minutes, then try again.';
      return 'The server answered with HTTP ${res.statusCode}.';
    } catch (_) {
      return 'Couldn\'t reach $base. Check your internet connection and the server address.';
    }
  }
}
