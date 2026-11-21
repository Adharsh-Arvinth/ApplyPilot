import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// Background entry point: Android runs this about every 15 minutes, even when the app is closed.
@pragma('vm:entry-point')
void notifierDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await Notifier.checkNow();
    } catch (_) {}
    return true; // never ask Android to retry aggressively; the next window comes anyway
  });
}

/// Calm, grouped phone notifications from the ApplyPilot server.
/// The phone asks the server what's new (no Firebase, nothing paid); the server groups and words it.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _sinceKey = 'notify_since';
  static const _task = 'applypilot.whats-new';
  static const _accent = Color(0xFF34B394);

  /// Where a tapped notification should take the app (cockpit route, e.g. "proof").
  static void Function(String route)? onOpen;
  static String? pendingRoute;

  static const _channels = [
    AndroidNotificationChannel('replies', 'Employer replies',
        description: 'Interview invitations, confirmations and decisions', importance: Importance.high),
    AndroidNotificationChannel('updates', 'Your search',
        description: 'New top matches, questions for you and applications sent', importance: Importance.defaultImportance),
    AndroidNotificationChannel('quiet', 'Quiet hours',
        description: 'Delivered silently during your quiet hours', importance: Importance.low, playSound: false, enableVibration: false),
  ];

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_applypilot')),
      onDidReceiveNotificationResponse: (r) {
        final route = r.payload;
        if (route == null || route.isEmpty) return;
        if (onOpen != null) {
          onOpen!(route);
        } else {
          pendingRoute = route;
        }
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in _channels) {
      await android?.createNotificationChannel(c);
    }
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) pendingRoute = launch!.notificationResponse?.payload;
    } catch (_) {}
    _ready = true;
  }

  /// Start the background checks (safe to call on every launch).
  static Future<void> start() async {
    try {
      await Workmanager().initialize(notifierDispatcher);
      await Workmanager().registerPeriodicTask(
        'applypilot-whats-new', _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {}
  }

  static Future<bool> permitted() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Ask the server what's new since the last check and show it. Returns how many were shown.
  static Future<int> checkNow({bool test = false}) async {
    WidgetsFlutterBinding.ensureInitialized();
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final url = prefs.getString('server_url') ?? '', token = prefs.getString('auth_token') ?? '';
    if (url.isEmpty || token.isEmpty) return 0;
    if (test) {
      await _show(0x7ff00001, 'Notifications are on', "You'll hear about employer replies and strong new matches here.", 'updates', 'home');
      return 1;
    }
    final since = prefs.getString(_sinceKey);
    final uri = Uri.parse('$url/api/v1/notifications').replace(queryParameters: since == null ? null : {'since': since});
    final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return 0;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['now'] is String) await prefs.setString(_sinceKey, data['now'] as String);
    final items = ((data['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final quiet = data['quiet'] == true;
    for (final it in items) {
      final channel = quiet ? 'quiet' : (it['kind'] == 'replies' ? 'replies' : 'updates');
      await _show((it['id'] as String).hashCode & 0x7fffffff, it['title'] as String, it['body'] as String, channel, (it['route'] as String?) ?? 'home');
    }
    return items.length;
  }

  static Future<void> _show(int id, String title, String body, String channel, String route) async {
    final c = _channels.firstWhere((x) => x.id == channel);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: route,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          c.id, c.name,
          channelDescription: c.description,
          importance: c.importance,
          priority: c.importance == Importance.high ? Priority.high : Priority.defaultPriority,
          color: _accent,
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
          category: channel == 'replies' ? AndroidNotificationCategory.email : AndroidNotificationCategory.status,
          groupKey: 'org.applypilot.news',
          autoCancel: true,
          playSound: channel != 'quiet',
          enableVibration: channel != 'quiet',
        ),
      ),
    );
  }
}
