import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Adapted from nank1ro/flutter-shadcn-ui (MIT License)
/// A structured card container with header, content, and footer slots.
class ShadcnCard extends StatelessWidget {
  final Widget? title;
  final Widget? description;
  final Widget? leading;
  final Widget? trailing;
  final Widget? child;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final VoidCallback? onTap;

  const ShadcnCard({
    super.key,
    this.title,
    this.description,
    this.leading,
    this.trailing,
    this.child,
    this.footer,
    this.padding = const EdgeInsets.all(TemplateTokens.s16),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? TemplateTokens.surface;
    final border = borderColor ?? TemplateTokens.border;
    final radius = BorderRadius.circular(borderRadius ?? TemplateTokens.radiusLg);

    Widget cardContent = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: border, width: 1.0),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row if title, leading, or trailing exists
            if (title != null || leading != null || trailing != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: TemplateTokens.s12),
                  ],
                  if (title != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DefaultTextStyle(
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: TemplateTokens.textPrimary,
                              letterSpacing: -0.2,
                            ),
                            child: title!,
                          ),
                          if (description != null) ...[
                            const SizedBox(height: TemplateTokens.s4),
                            DefaultTextStyle(
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: TemplateTokens.textSecondary,
                                height: 1.35,
                              ),
                              child: description!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (trailing != null) ...[
                    const SizedBox(width: TemplateTokens.s12),
                    trailing!,
                  ],
                ],
              ),
              if (child != null) const SizedBox(height: TemplateTokens.s12),
            ],
            // Main Content Body
            if (child != null) child!,
            // Footer Section
            if (footer != null) ...[
              const SizedBox(height: TemplateTokens.s12),
              Container(
                padding: const EdgeInsets.only(top: TemplateTokens.s12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: TemplateTokens.border, width: 0.8)),
                ),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: TemplateTokens.accent.withOpacity(0.08),
          highlightColor: TemplateTokens.accent.withOpacity(0.04),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}
