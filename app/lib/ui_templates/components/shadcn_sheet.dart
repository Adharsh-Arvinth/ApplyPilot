import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Adapted from nank1ro/flutter-shadcn-ui & dashboard_reborn (MIT License)
/// Tactile bottom sheet modal with drag handle and spring motion.
class ShadcnSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    double maxHeightFraction = 0.9,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * maxHeightFraction,
          ),
          decoration: const BoxDecoration(
            color: TemplateTokens.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(TemplateTokens.radiusXl)),
            border: Border(top: BorderSide(color: TemplateTokens.border, width: 1.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: TemplateTokens.s12, bottom: TemplateTokens.s8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TemplateTokens.borderHover,
                    borderRadius: BorderRadius.circular(TemplateTokens.radiusPill),
                  ),
                ),
              ),
              Flexible(child: builder(ctx)),
            ],
          ),
        );
      },
    );
  }
}
