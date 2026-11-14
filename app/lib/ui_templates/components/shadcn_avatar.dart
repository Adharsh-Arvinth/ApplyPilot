import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Company / Candidate Avatar adapted from nank1ro/flutter-shadcn-ui (MIT License)
class ShadcnAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final double size;
  final Color? backgroundColor;
  final Color? textColor;

  const ShadcnAvatar({
    super.key,
    this.imageUrl,
    required this.fallbackText,
    this.size = 36,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(fallbackText);
    final bg = backgroundColor ?? TemplateTokens.surfaceElevated;
    final fg = textColor ?? TemplateTokens.textPrimary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
        border: Border.all(color: TemplateTokens.border, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallback(initials, fg),
            )
          : _buildFallback(initials, fg),
    );
  }

  Widget _buildFallback(String initials, Color fg) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  String _getInitials(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return "AP";
    if (words.length == 1) {
      return words[0].substring(0, words[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}
