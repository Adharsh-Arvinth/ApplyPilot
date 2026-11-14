import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_tokens.dart';

/// Tactile interactive card tile adapted from urmilshroff/dashboard_reborn (MIT License)
/// Provides satisfying haptic press states and clean elevated border shadows.
class RebornCardTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  const RebornCardTile({
    super.key,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.all(TemplateTokens.s14),
    this.margin = const EdgeInsets.only(bottom: TemplateTokens.s12),
    this.borderRadius = TemplateTokens.radiusLg,
  });

  @override
  State<RebornCardTile> createState() => _RebornCardTileState();
}

class _RebornCardTileState extends State<RebornCardTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? TemplateTokens.surface;
    final border = widget.borderColor ?? TemplateTokens.border;

    return AnimatedScale(
      scale: _isPressed ? 0.985 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _isPressed ? TemplateTokens.accent.withOpacity(0.5) : border,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isPressed ? 0.2 : 0.4),
              blurRadius: _isPressed ? 4 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            onTap: widget.onTap != null
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onTap!();
                  }
                : null,
            onHighlightChanged: (val) {
              setState(() => _isPressed = val);
            },
            borderRadius: BorderRadius.circular(widget.borderRadius),
            splashColor: TemplateTokens.accent.withOpacity(0.08),
            highlightColor: TemplateTokens.accent.withOpacity(0.04),
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
