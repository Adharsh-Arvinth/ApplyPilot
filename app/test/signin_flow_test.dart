// The first-run flow: welcome pages → sign in → the "You're in" moment, against a fake server.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:applypilot/shell/connect_screen.dart';
import 'package:applypilot/shell/shell_config.dart';
import 'package:applypilot/shell/shell_theme.dart';

/// Set SHOTS=1 to also write screenshots (with real fonts) to build/signin_shots/ for a visual check.
final bool shots = Platform.environment['SHOTS'] == '1';

Future<void> loadRealFonts() async {
  final dir = Platform.environment['FLUTTER_ROOT'] ?? r'D:\flutter';
  final fonts = '$dir/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final w in ['regular', 'medium', 'bold']) {
    final f = File('$fonts/roboto-$w.ttf');
    if (f.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await roboto.load();
  final icons = File('$fonts/materialicons-regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto', scaffoldBackgroundColor: ShellPalette.neutral.bg),
      home: home,
    );

Future<void> shot(WidgetTester t, String name) async {
  if (!shots) return;
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../build/signin_shots/$name.png'));
}

void main() {
  setUpAll(() async { if (shots) await loadRealFonts(); });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShellConfig.httpClient = null;
  });

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('welcome → sign in → "You\'re in", then the app opens', (t) async {
    await phone(t);
    var requests = 0;
    ShellConfig.httpClient = MockClient((req) async {
      requests++;
      expect(req.url.path, '/api/v1/health/authenticated');
      expect(req.headers['Authorization'], 'Bearer good-key');
      return http.Response('{"ok":true}', 200);
    });
    ShellConfig? connected;
    await t.pumpWidget(app(ConnectScreen(
      initial: const ShellConfig(serverUrl: 'https://demo.sslip.io', token: '', ready: false),
      showIntro: true,
      onConnected: (c) => connected = c,
    )));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Get started'), findsOneWidget);
    await shot(t, '1_welcome');

    await t.tap(find.text('Get started'));
    for (var i = 0; i < 12; i++) { await t.pump(const Duration(milliseconds: 60)); } // the glow drifts forever: step frames instead of settling
    expect(find.text('You stay\nin control'), findsOneWidget);
    await t.tap(find.text('Continue'));
    for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 60)); }
    expect(find.text('Sign in'), findsWidgets);
    await shot(t, '2_signin');

    await t.enterText(find.byType(TextField).last, 'good-key');
    await t.pump(const Duration(milliseconds: 300));
    await shot(t, '3_signin_filled');
    await t.tap(find.text('Sign in').last);
    await t.pump(); // request goes out
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 700)); // mid-celebration
    expect(requests, 1);
    expect(find.text("You're in"), findsOneWidget);
    expect(find.text('Connected to demo.sslip.io'), findsOneWidget);
    await shot(t, '4_youre_in');
    await t.pump(const Duration(milliseconds: 1200));
    expect(connected?.token, 'good-key');
    expect(connected?.serverUrl, 'https://demo.sslip.io');
    expect((await SharedPreferences.getInstance()).getString('auth_token'), 'good-key');
  });

  testWidgets('a wrong key explains itself and stays on the screen', (t) async {
    await phone(t);
    ShellConfig.httpClient = MockClient((_) async => http.Response('{}', 403));
    var opened = false;
    await t.pumpWidget(app(ConnectScreen(
      initial: const ShellConfig(serverUrl: 'https://demo.sslip.io', token: '', ready: true),
      onConnected: (_) => opened = true,
    )));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Welcome back'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'bad-key');
    await t.pump();
    await t.tap(find.text('Sign in').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining("didn't work"), findsOneWidget);
    expect(find.text("You're in"), findsNothing);
    await shot(t, '5_wrong_key');
    await t.pump(const Duration(seconds: 2));
    expect(opened, isFalse);
  });

  testWidgets('a pasted sign-in link fills the server and key together', (t) async {
    await phone(t);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': 'https://my-box.sslip.io/app/?token=abc123'};
      return null;
    });
    await t.pumpWidget(app(ConnectScreen(
      initial: const ShellConfig(serverUrl: '', token: '', ready: false),
      onConnected: (_) {},
    )));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(find.text('Paste'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('my-box.sslip.io'), findsOneWidget);
    final key = t.widget<TextField>(find.byType(TextField).last);
    expect(key.controller!.text, 'abc123');
  });
}
