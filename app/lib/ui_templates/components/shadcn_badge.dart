import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Adapted from nank1ro/flutter-shadcn-ui (MIT License)
/// Variants for the Shadcn-style Pill Badge
enum ShadcnBadgeVariant {
  primary,
  secondary,
  outline,
  destructive,
  success,
  brass,
  info,
}

class ShadcnBadge extends StatelessWidget {
  final Widget label;
  final Widget? icon;
  final ShadcnBadgeVariant variant;
  final VoidCallback? onTap;

  const ShadcnBadge({
    super.key,
    required this.label,
    this.icon,
    this.variant = ShadcnBadgeVariant.primary,
    this.onTap,
  });

  const ShadcnBadge.success({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  }) : variant = ShadcnBadgeVariant.success;

  const ShadcnBadge.destructive({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  }) : variant = ShadcnBadgeVariant.destructive;

  const ShadcnBadge.outline({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  }) : variant = ShadcnBadgeVariant.outline;

  const ShadcnBadge.brass({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  }) : variant = ShadcnBadgeVariant.brass;

  const ShadcnBadge.info({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  }) : variant = ShadcnBadgeVariant.info;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color fg;

    switch (variant) {
      case ShadcnBadgeVariant.success:
        bg = TemplateTokens.accentSubtle;
        border = TemplateTokens.accent.withOpacity(0.35);
        fg = TemplateTokens.accent;
        break;
      case ShadcnBadgeVariant.destructive:
        bg = TemplateTokens.errorSubtle;
        border = TemplateTokens.error.withOpacity(0.35);
        fg = TemplateTokens.error;
        break;
      case ShadcnBadgeVariant.outline:
        bg = Colors.transparent;
        border = TemplateTokens.border;
        fg = TemplateTokens.textSecondary;
        break;
      case ShadcnBadgeVariant.brass:
        bg = TemplateTokens.brassSubtle;
        border = TemplateTokens.brass.withOpacity(0.35);
        fg = TemplateTokens.brass;
        break;
      case ShadcnBadgeVariant.info:
        bg = TemplateTokens.infoSubtle;
        border = TemplateTokens.info.withOpacity(0.35);
        fg = TemplateTokens.info;
        break;
      case ShadcnBadgeVariant.secondary:
        bg = TemplateTokens.surfaceElevated;
        border = TemplateTokens.border;
        fg = TemplateTokens.textSecondary;
        break;
      case ShadcnBadgeVariant.primary:
      default:
        bg = TemplateTokens.surfaceElevated;
        border = TemplateTokens.border;
        fg = TemplateTokens.textPrimary;
        break;
    }

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: TemplateTokens.s8, vertical: TemplateTokens.s4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TemplateTokens.radiusPill),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            IconTheme(
              data: IconThemeData(size: 11, color: fg),
              child: icon!,
            ),
            const SizedBox(width: TemplateTokens.s4),
          ],
          DefaultTextStyle(
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: fg,
            ),
            child: label,
          ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: pill,
      );
    }

    return pill;
  }
}
