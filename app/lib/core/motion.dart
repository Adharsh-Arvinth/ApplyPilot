import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized Motion & Animation System for ApplyPilot.
/// Provides standardized durations, easing curves, reduced-motion compliance,
/// subtle micro-interactions, and staggered entry transitions.
class AppMotion {
  // Standardized Durations
  static const Duration durationInstant = Duration.zero;
  static const Duration durationMicro = Duration(milliseconds: 150);
  static const Duration durationFast = Duration(milliseconds: 220);
  static const Duration durationMedium = Duration(milliseconds: 320);
  static const Duration durationPage = Duration(milliseconds: 380);
  static const Duration durationStaggerStep = Duration(milliseconds: 40);

  // Standardized Motion Curves
  static const Curve curveStandard = Curves.easeInOutCubic;
  static const Curve curveDecelerate = Curves.easeOutCubic;
  static const Curve curveAccelerate = Curves.easeInCubic;
  static const Curve curveEmphasized = Curves.fastOutSlowIn;
  static const Curve curveSpring = Curves.easeOutBack;

  /// Check whether the candidate OS has enabled "Remove animations" or reduced motion.
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  /// Get safe duration respecting user's accessibility preferences.
  static Duration safeDuration(BuildContext context, Duration defaultDuration) {
    return isReducedMotion(context) ? Duration.zero : defaultDuration;
  }
}

/// A subtle, high-performance pressable wrapper for cards, chips, and action buttons.
/// Scales down to 0.98 on press with subtle haptic feedback.
class InteractivePressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool enableHaptic;
  final BorderRadius? borderRadius;

  const InteractivePressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.975,
    this.enableHaptic = true,
    this.borderRadius,
  });

  @override
  State<InteractivePressable> createState() => _InteractivePressableState();
}

class _InteractivePressableState extends State<InteractivePressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.durationMicro,
      reverseDuration: AppMotion.durationMicro,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppMotion.curveDecelerate,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    _controller.reverse();
  }

  void _onTapCancel() {
    if (widget.onTap == null) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: widget.borderRadius,
        child: widget.child,
      );
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Staggered Fade + Slide entrance animation for lists and cards.
class MotionFadeSlide extends StatefulWidget {
  final Widget child;
  final int index;
  final Offset slideOffset;
  final Duration? duration;
  final Duration? delay;

  const MotionFadeSlide({
    super.key,
    required this.child,
    this.index = 0,
    this.slideOffset = const Offset(0.0, 0.08),
    this.duration,
    this.delay,
  });

  @override
  State<MotionFadeSlide> createState() => _MotionFadeSlideState();
}

class _MotionFadeSlideState extends State<MotionFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    final effectiveDuration = widget.duration ?? AppMotion.durationMedium;
    _controller = AnimationController(
      vsync: this,
      duration: effectiveDuration,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.curveDecelerate),
    );

    _slideAnimation = Tween<Offset>(
      begin: widget.slideOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: AppMotion.curveDecelerate),
    );

    final staggerDelay = widget.delay ??
        Duration(milliseconds: (widget.index * 35).clamp(0, 300));

    Future.delayed(staggerDelay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

/// Shimmer Skeleton loading block for placeholders.
class ShimmerSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.baseColor ??
        (isDark ? const Color(0xFF1F221F) : const Color(0xFFECEBE4));
    final highlight = widget.highlightColor ??
        (isDark ? const Color(0xFF2C302C) : const Color(0xFFFAF9F5));

    if (AppMotion.isReducedMotion(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (_shimmerController.value * 2.0), -0.3),
              end: Alignment(1.0 + (_shimmerController.value * 2.0), 0.3),
              colors: [base, highlight, base],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}

/// PageRoute with smooth fade & subtle scale transition.
class MotionPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  MotionPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: AppMotion.durationPage,
          reverseTransitionDuration: AppMotion.durationFast,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (AppMotion.isReducedMotion(context)) {
              return child;
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.curveDecelerate,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}
