import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  Map<String, dynamic>? _aiStatus;
  final List<Map<String, dynamic>> _messages = [
    {
      "role": "assistant",
      "content": "### Welcome to ApplyPilot Career Advisor\n\nI'm powered by **Gemini 2.5 Flash** with direct access to your verified candidate profile (VIT Vellore MTech, 2 published patents, Agentic retrieval benchmark, and AWS Solutions Architect certification).\n\nHow can I help accelerate your career today?",
      "suggested_actions": [
        "Review top matches",
        "Technical interview prep",
        "ATS Resume optimization"
      ]
    }
  ];

  final List<String> _quickPrompts = [
    "Review my top matched jobs today",
    "Prepare me for a Machine Learning interview",
    "How should I highlight my patents for Data Science?",
    "Analyze my application funnel and next steps",
    "What questions will Swiggy or Razorpay ask me?",
  ];

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final status = await _api.getAiStatus();
      if (mounted) {
        setState(() {
          _aiStatus = status;
        });
      }
    } catch (_) {}
  }

  Future<void> _sendMessage([String? textToSend]) async {
    final text = (textToSend ?? _messageController.text).trim();
    if (text.isEmpty || _isLoading) return;

    _messageController.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add({
        "role": "user",
        "content": text,
      });
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      // Build history for API
      final history = _messages
          .where((m) => m["role"] == "user" || m["role"] == "assistant")
          .map((m) => {
                "role": m["role"] as String,
                "content": m["content"] as String,
              })
          .toList();

      final res = await _api.chatWithAdvisor(text, history: history);
      if (mounted) {
        setState(() {
          _messages.add({
            "role": "assistant",
            "content": res["response"] ?? "No response generated.",
            "suggested_actions": res["suggested_actions"] ?? [],
          });
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            "role": "assistant",
            "content": "⚠️ **Communication Notice**: Unable to contact Gemini service: $e\n\nPlease ensure backend is running.",
          });
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? ApplyPilotColors.darkPrimary : ApplyPilotColors.lightPrimary;
    final surface = isDark ? ApplyPilotColors.darkSurface : ApplyPilotColors.lightSurface;
    final textPrimary = isDark ? ApplyPilotColors.darkTextPrimary : ApplyPilotColors.lightTextPrimary;
    final textSecondary = isDark ? ApplyPilotColors.darkTextSecondary : ApplyPilotColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ApplyPilotColors.aiViolet.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: ApplyPilotColors.aiViolet, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Career Advisor", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  _aiStatus != null && _aiStatus!["is_connected"] == true
                      ? "Gemini 2.5 Flash • Connected"
                      : "Gemini AI • Ready",
                  style: TextStyle(
                    fontSize: 11,
                    color: _aiStatus != null && _aiStatus!["is_connected"] == true
                        ? ApplyPilotColors.successEmerald
                        : textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: "Check Model Diagnostics",
            onPressed: () {
              _fetchStatus();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_aiStatus != null
                      ? "Gemini AI: ${_aiStatus!['primary_model']} (${_aiStatus!['latency_ms']} ms)"
                      : "Checking Gemini connectivity..."),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Quick Suggestion Pills Carousel
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final prompt = _quickPrompts[index];
                  return ActionChip(
                    label: Text(
                      prompt,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? ApplyPilotColors.lightIvory : ApplyPilotColors.britishRacingGreen,
                      ),
                    ),
                    backgroundColor: isDark
                        ? ApplyPilotColors.darkCard
                        : ApplyPilotColors.brassAccent.withOpacity(0.12),
                    side: BorderSide(
                      color: isDark
                          ? ApplyPilotColors.darkBorder
                          : ApplyPilotColors.brassAccent.withOpacity(0.3),
                    ),
                    onPressed: () => _sendMessage(prompt),
                  );
                },
              ),
            ),
            const Divider(height: 1),

            // Chat Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg["role"] == "user";
                  final content = msg["content"] as String;
                  final actions = (msg["suggested_actions"] as List<dynamic>?) ?? [];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isUser) ...[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: ApplyPilotColors.aiViolet.withOpacity(0.2),
                            child: const Icon(Icons.psychology, size: 18, color: ApplyPilotColors.aiViolet),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Column(
                            crossAxisAlignment:
                                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? primary
                                      : (isDark ? ApplyPilotColors.darkCard : Colors.white),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                                    bottomRight: Radius.circular(isUser ? 4 : 16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: isUser
                                        ? Colors.transparent
                                        : (isDark
                                            ? ApplyPilotColors.darkBorder
                                            : ApplyPilotColors.lightBorder),
                                  ),
                                ),
                                child: SelectableText(
                                  content,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: isUser
                                        ? Colors.white
                                        : (isDark ? Colors.white : textPrimary),
                                  ),
                                ),
                              ),
                              if (!isUser && actions.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: actions.map((act) {
                                    return InkWell(
                                      onTap: () => _sendMessage("Tell me more about: $act"),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: ApplyPilotColors.aiViolet.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: ApplyPilotColors.aiViolet.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.arrow_forward, size: 12, color: ApplyPilotColors.aiViolet),
                                            const SizedBox(width: 4),
                                            Text(
                                              act.toString(),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: ApplyPilotColors.aiViolet,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isUser) ...[
                          const SizedBox(width: 10),
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: primary.withOpacity(0.2),
                            child: Icon(Icons.person, size: 18, color: primary),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            if (_isLoading) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ApplyPilotColors.aiViolet),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Gemini is analyzing career context...",
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? ApplyPilotColors.darkBorder : ApplyPilotColors.lightBorder,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: "Ask Gemini anything about your job search...",
                        hintStyle: TextStyle(fontSize: 13, color: textSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: isDark ? ApplyPilotColors.darkCard : const Color(0xFFF3F3F0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (val) => _sendMessage(val),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                      onPressed: _isLoading ? null : () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
