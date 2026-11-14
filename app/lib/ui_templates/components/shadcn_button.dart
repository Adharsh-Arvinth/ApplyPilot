import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_tokens.dart';

enum ShadcnButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  destructive,
}

enum ShadcnButtonSize {
  sm,
  md,
  lg,
  icon,
}

/// Adapted from nank1ro/flutter-shadcn-ui (MIT License)
/// Tactile, micro-animated button with variants and loading state.
class ShadcnButton extends StatelessWidget {
  final Widget? child;
  final VoidCallback? onPressed;
  final ShadcnButtonVariant variant;
  final ShadcnButtonSize size;
  final Widget? leading;
  final Widget? trailing;
  final bool isLoading;
  final bool fullWidth;

  const ShadcnButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.variant = ShadcnButtonVariant.primary,
    this.size = ShadcnButtonSize.md,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.fullWidth = false,
  });

  const ShadcnButton.outline({
    super.key,
    required this.child,
    required this.onPressed,
    this.size = ShadcnButtonSize.md,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.fullWidth = false,
  }) : variant = ShadcnButtonVariant.outline;

  const ShadcnButton.secondary({
    super.key,
    required this.child,
    required this.onPressed,
    this.size = ShadcnButtonSize.md,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.fullWidth = false,
  }) : variant = ShadcnButtonVariant.secondary;

  const ShadcnButton.ghost({
    super.key,
    required this.child,
    required this.onPressed,
    this.size = ShadcnButtonSize.md,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.fullWidth = false,
  }) : variant = ShadcnButtonVariant.ghost;

  const ShadcnButton.destructive({
    super.key,
    required this.child,
    required this.onPressed,
    this.size = ShadcnButtonSize.md,
    this.leading,
    this.trailing,
    this.isLoading = false,
    this.fullWidth = false,
  }) : variant = ShadcnButtonVariant.destructive;

  const ShadcnButton.icon({
    super.key,
    required Widget icon,
    required this.onPressed,
    this.variant = ShadcnButtonVariant.ghost,
    this.isLoading = false,
  })  : child = icon,
        size = ShadcnButtonSize.icon,
        leading = null,
        trailing = null,
        fullWidth = false;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color fg;

    switch (variant) {
      case ShadcnButtonVariant.primary:
        bg = TemplateTokens.accent;
        border = TemplateTokens.accent;
        fg = TemplateTokens.background;
        break;
      case ShadcnButtonVariant.destructive:
        bg = TemplateTokens.error;
        border = TemplateTokens.error;
        fg = TemplateTokens.textPrimary;
        break;
      case ShadcnButtonVariant.outline:
        bg = Colors.transparent;
        border = TemplateTokens.border;
        fg = TemplateTokens.textPrimary;
        break;
      case ShadcnButtonVariant.ghost:
        bg = Colors.transparent;
        border = Colors.transparent;
        fg = TemplateTokens.textSecondary;
        break;
      case ShadcnButtonVariant.secondary:
      default:
        bg = TemplateTokens.surfaceElevated;
        border = TemplateTokens.border;
        fg = TemplateTokens.textPrimary;
        break;
    }

    EdgeInsets padding;
    double fontSize;
    double iconSize;
    double minHeight;

    switch (size) {
      case ShadcnButtonSize.sm:
        padding = const EdgeInsets.symmetric(horizontal: TemplateTokens.s10, vertical: TemplateTokens.s6);
        fontSize = 12.0;
        iconSize = 14.0;
        minHeight = 32.0;
        break;
      case ShadcnButtonSize.lg:
        padding = const EdgeInsets.symmetric(horizontal: TemplateTokens.s20, vertical: TemplateTokens.s14);
        fontSize = 15.0;
        iconSize = 18.0;
        minHeight = 48.0;
        break;
      case ShadcnButtonSize.icon:
        padding = const EdgeInsets.all(TemplateTokens.s8);
        fontSize = 13.0;
        iconSize = 18.0;
        minHeight = 36.0;
        break;
      case ShadcnButtonSize.md:
      default:
        padding = const EdgeInsets.symmetric(horizontal: TemplateTokens.s14, vertical: TemplateTokens.s8);
        fontSize = 13.0;
        iconSize = 16.0;
        minHeight = 38.0;
        break;
    }

    final isClickable = onPressed != null && !isLoading;

    Widget buttonContent = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: isClickable ? bg : bg.withOpacity(0.4),
          borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
          border: Border.all(color: border, width: 1.0),
        ),
        child: isLoading
            ? SizedBox(
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            : Row(
                mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    IconTheme(
                      data: IconThemeData(size: iconSize, color: fg),
                      child: leading!,
                    ),
                    const SizedBox(width: TemplateTokens.s6),
                  ],
                  if (child != null)
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: isClickable ? fg : fg.withOpacity(0.4),
                      ),
                      child: child!,
                    ),
                  if (trailing != null) ...[
                    const SizedBox(width: TemplateTokens.s6),
                    IconTheme(
                      data: IconThemeData(size: iconSize, color: fg),
                      child: trailing!,
                    ),
                  ],
                ],
              ),
      ),
    );

    return InkWell(
      onTap: isClickable
          ? () {
              HapticFeedback.lightImpact();
              onPressed?.call();
            }
          : null,
      borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
      child: fullWidth ? SizedBox(width: double.infinity, child: buttonContent) : buttonContent,
    );
  }
}
