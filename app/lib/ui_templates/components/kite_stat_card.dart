import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Adapted from ColorlibHQ/kite-flutter-admin-dashboard (MIT License)
/// A high-impact metric tile with trend badge, delta indicators, and secondary context.
class KiteStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final String? delta;
  final bool isPositiveDelta;
  final IconData? icon;
  final Color? iconColor;
  final double? progressFraction;
  final VoidCallback? onTap;

  const KiteStatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.delta,
    this.isPositiveDelta = true,
    this.icon,
    this.iconColor,
    this.progressFraction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? TemplateTokens.accent;

    return Container(
      decoration: BoxDecoration(
        color: TemplateTokens.surface,
        borderRadius: BorderRadius.circular(TemplateTokens.radiusLg),
        border: Border.all(color: TemplateTokens.border, width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(TemplateTokens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TemplateTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(TemplateTokens.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (icon != null) ...[
                          Container(
                            padding: const EdgeInsets.all(TemplateTokens.s6),
                            decoration: BoxDecoration(
                              color: effectiveIconColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(TemplateTokens.radiusSm),
                            ),
                            child: Icon(icon, size: 14, color: effectiveIconColor),
                          ),
                          const SizedBox(width: TemplateTokens.s8),
                        ],
                        Text(
                          title.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: TemplateTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (delta != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: TemplateTokens.s6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPositiveDelta
                              ? TemplateTokens.accentSubtle
                              : TemplateTokens.errorSubtle,
                          borderRadius: BorderRadius.circular(TemplateTokens.radiusPill),
                          border: Border.all(
                            color: (isPositiveDelta ? TemplateTokens.accent : TemplateTokens.error).withOpacity(0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositiveDelta ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 9,
                              color: isPositiveDelta ? TemplateTokens.accent : TemplateTokens.error,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              delta!,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isPositiveDelta ? TemplateTokens.accent : TemplateTokens.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: TemplateTokens.s12),
                // Big Metric Value
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: TemplateTokens.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: TemplateTokens.s4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TemplateTokens.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
                // Optional Progress Bar
                if (progressFraction != null) ...[
                  const SizedBox(height: TemplateTokens.s10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(TemplateTokens.radiusPill),
                    child: LinearProgressIndicator(
                      value: progressFraction!.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: TemplateTokens.surfaceElevated,
                      valueColor: AlwaysStoppedAnimation<Color>(effectiveIconColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
