import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Alert variant types adapted from nank1ro/flutter-shadcn-ui
enum AlertVariant {
  info,
  success,
  warning,
  destructive,
}

/// Shadcn Alert Banner adapted from nank1ro/flutter-shadcn-ui (MIT License)
/// Provides structured status announcements, system warnings, and offline alerts.
class ShadcnAlert extends StatelessWidget {
  final AlertVariant variant;
  final IconData? icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;

  const ShadcnAlert({
    super.key,
    this.variant = AlertVariant.info,
    this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color borderColor;
    Color bgColor;
    Color iconColor;

    switch (variant) {
      case AlertVariant.success:
        borderColor = TemplateTokens.success.withOpacity(0.35);
        bgColor = TemplateTokens.success.withOpacity(0.08);
        iconColor = TemplateTokens.success;
        break;
      case AlertVariant.warning:
        borderColor = TemplateTokens.brass.withOpacity(0.35);
        bgColor = TemplateTokens.brass.withOpacity(0.08);
        iconColor = TemplateTokens.brass;
        break;
      case AlertVariant.destructive:
        borderColor = TemplateTokens.error.withOpacity(0.4);
        bgColor = TemplateTokens.error.withOpacity(0.10);
        iconColor = TemplateTokens.error;
        break;
      case AlertVariant.info:
      default:
        borderColor = TemplateTokens.border;
        bgColor = TemplateTokens.surface;
        iconColor = TemplateTokens.accent;
        break;
    }

    final IconData effectiveIcon = icon ?? _defaultIconForVariant(variant);

    Widget content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TemplateTokens.s14,
        vertical: TemplateTokens.s12,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(effectiveIcon, size: 16, color: iconColor),
          ),
          const SizedBox(width: TemplateTokens.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: variant == AlertVariant.destructive
                        ? TemplateTokens.error
                        : TemplateTokens.textPrimary,
                  ),
                ),
                if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: TemplateTokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: TemplateTokens.s8),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
          child: content,
        ),
      );
    }

    return content;
  }

  IconData _defaultIconForVariant(AlertVariant v) {
    switch (v) {
      case AlertVariant.success:
        return Icons.check_circle_outline;
      case AlertVariant.warning:
        return Icons.warning_amber_rounded;
      case AlertVariant.destructive:
        return Icons.error_outline;
      case AlertVariant.info:
      default:
        return Icons.info_outline;
    }
  }
}
