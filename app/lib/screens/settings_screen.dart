import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiClient();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  String _pingResult = "";

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = _api.baseUrl;
    _tokenCtrl.text = _api.token;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _pingResult = "Pinging server...");
    await _api.saveConnectionSettings(_urlCtrl.text, _tokenCtrl.text);
    final health = await _api.checkHealth();
    setState(() {
      if (health["status"] == "online") {
        _pingResult = "Connected! Server online (${health["database"]}). Uptime: ${health["uptime_seconds"]}s";
      } else {
        _pingResult = "Failed: ${health["error"] ?? "Cannot reach server"}";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings & Connection", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s20),
        children: [
          Text("PC Server Connection (Tailscale VPN)", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          Text(
            "Enter your always-on Windows PC's Tailscale IPv4 address or MagicDNS hostname.",
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.s12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Column(
                children: [
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: "Server Base URL",
                      hintText: "http://100.x.y.z:8000",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  TextField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: "Bearer Auth Token",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.wifi_tethering, size: 16),
                        label: const Text("Test Ping"),
                        onPressed: _testConnection,
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.accentLight),
                        onPressed: () async {
                          await _api.saveConnectionSettings(_urlCtrl.text, _tokenCtrl.text);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Connection settings saved.")),
                          );
                        },
                        child: const Text("Save"),
                      ),
                    ],
                  ),
                  if (_pingResult.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s12),
                    Text(
                      _pingResult,
                      style: TextStyle(
                        fontSize: 12,
                        color: _pingResult.startsWith("Connected") ? AppColors.accentLight : AppColors.blockedLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.s24),

          Text("System & Reliability", style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text("Nightly Database Backup"),
                  subtitle: const Text("Scheduled daily at 03:00 IST to backups/ folder"),
                  trailing: const Icon(Icons.backup_outlined, size: 20),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text("Safety Circuit Breaker"),
                  subtitle: const Text("Pauses queue automatically on 3 consecutive CAPTCHA spikes"),
                  trailing: const Icon(Icons.check_circle_outline, size: 20, color: AppColors.accentLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
