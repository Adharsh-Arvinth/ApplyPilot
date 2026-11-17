import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/design_tokens.dart';

/// Navigation item definition for KiteAppShell
class ShellNavItem {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badgeCount;

  const ShellNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeCount = 0,
  });
}

/// Adapted from ColorlibHQ/kite-flutter-admin-dashboard (MIT License)
/// An adaptive, responsive shell providing sidebar on desktop/tablet and bottom navigation on mobile.
class KiteAppShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<ShellNavItem> items;
  final Widget body;
  final String title;
  final List<Widget>? actions;
  final bool isOnline;
  final VoidCallback? onOpenAiAdvisor;
  final bool showAppBar;

  const KiteAppShell({
    super.key,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.items,
    required this.body,
    this.title = "Command Center",
    this.actions,
    this.isOnline = true,
    this.onOpenAiAdvisor,
    this.showAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = TemplateTokens.isDesktop(context);

    if (isDesktop) {
      return Scaffold(
        backgroundColor: TemplateTokens.background,
        body: SafeArea(
          child: Row(
            children: [
              // Desktop Sidebar Navigation
              _buildDesktopSidebar(context),
              // Main Content Area with Top Header
              Expanded(
                child: Column(
                  children: [
                    if (showAppBar) _buildDesktopTopBar(context),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile & Compact Tablet Layout
    return Scaffold(
      backgroundColor: TemplateTokens.background,
      appBar: showAppBar
          ? AppBar(
              titleSpacing: TemplateTokens.s12,
              backgroundColor: TemplateTokens.background,
              elevation: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: TemplateTokens.s8, vertical: TemplateTokens.s4),
                    decoration: BoxDecoration(
                      color: TemplateTokens.accentSubtle,
                      borderRadius: BorderRadius.circular(TemplateTokens.radiusSm),
                      border: Border.all(color: TemplateTokens.accent.withOpacity(0.3), width: 0.8),
                    ),
                    child: const Text(
                      "APPLYPILOT",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: TemplateTokens.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: TemplateTokens.s8),
                  Flexible(
                    child: Text(
                      title ?? "Command Center",
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: TemplateTokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              actions: actions,
            )
          : null,
      body: body,
      bottomNavigationBar: _buildMobileBottomBar(context),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: TemplateTokens.surface,
        border: Border(right: BorderSide(color: TemplateTokens.border, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo & Branding Header
          Padding(
            padding: const EdgeInsets.all(TemplateTokens.s20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(TemplateTokens.s8),
                  decoration: BoxDecoration(
                    color: TemplateTokens.accentSubtle,
                    borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                    border: Border.all(color: TemplateTokens.accent.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.rocket_launch, size: 18, color: TemplateTokens.accent),
                ),
                const SizedBox(width: TemplateTokens.s10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ApplyPilot",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: TemplateTokens.textPrimary,
                      ),
                    ),
                    Text(
                      "Career Command",
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: TemplateTokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: TemplateTokens.border),
          const SizedBox(height: TemplateTokens.s12),

          // Navigation Links
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: TemplateTokens.s12),
              itemCount: items.length,
              itemBuilder: (ctx, idx) {
                final item = items[idx];
                final isSelected = currentIndex == idx;

                return Padding(
                  padding: const EdgeInsets.only(bottom: TemplateTokens.s4),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onNavigationChanged(idx);
                      },
                      borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: TemplateTokens.s12,
                          vertical: TemplateTokens.s10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? TemplateTokens.accentSubtle : Colors.transparent,
                          borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                          border: isSelected
                              ? Border.all(color: TemplateTokens.accent.withOpacity(0.35), width: 0.8)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              size: 18,
                              color: isSelected ? TemplateTokens.accent : TemplateTokens.textSecondary,
                            ),
                            const SizedBox(width: TemplateTokens.s10),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? TemplateTokens.accent : TemplateTokens.textSecondary,
                                ),
                              ),
                            ),
                            if (item.badgeCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: TemplateTokens.error,
                                  borderRadius: BorderRadius.circular(TemplateTokens.radiusPill),
                                ),
                                child: Text(
                                  item.badgeCount > 99 ? "99+" : "${item.badgeCount}",
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Tailscale Connectivity Pill & AI trigger
          Padding(
            padding: const EdgeInsets.all(TemplateTokens.s16),
            child: Column(
              children: [
                if (onOpenAiAdvisor != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: TemplateTokens.s8),
                    child: InkWell(
                      onTap: onOpenAiAdvisor,
                      borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                      child: Container(
                        padding: const EdgeInsets.all(TemplateTokens.s10),
                        decoration: BoxDecoration(
                          color: TemplateTokens.aiViolet.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                          border: Border.all(color: TemplateTokens.aiViolet.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome, size: 14, color: TemplateTokens.aiViolet),
                            SizedBox(width: 6),
                            Text(
                              "Gemini Career Advisor",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: TemplateTokens.aiViolet,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: TemplateTokens.s10, vertical: TemplateTokens.s8),
                  decoration: BoxDecoration(
                    color: TemplateTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(TemplateTokens.radiusMd),
                    border: Border.all(color: TemplateTokens.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? TemplateTokens.accent : TemplateTokens.error,
                        ),
                      ),
                      const SizedBox(width: TemplateTokens.s8),
                      Expanded(
                        child: Text(
                          isOnline ? "Tailscale Connected" : "Host Offline",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: TemplateTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTopBar(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: TemplateTokens.s20),
      decoration: const BoxDecoration(
        color: TemplateTokens.surface,
        border: Border(bottom: BorderSide(color: TemplateTokens.border, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: TemplateTokens.textPrimary,
            ),
          ),
          Row(
            children: actions ?? [],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF161816) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF262926) : const Color(0xFFE3E3DE);
    final activeColor = isDark ? const Color(0xFF7FD1A8) : const Color(0xFF2F6F4F);
    final inactiveColor = isDark ? const Color(0xFF8A908A) : const Color(0xFF6E736E);

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (idx) {
              final item = items[idx];
              final isSelected = currentIndex == idx;

              return InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onNavigationChanged(idx);
                },
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              isSelected ? item.activeIcon : item.icon,
                              size: 20,
                              color: isSelected ? activeColor : inactiveColor,
                            ),
                            if (item.badgeCount > 0)
                              Positioned(
                                top: -3,
                                right: -7,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE5736B),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    item.badgeCount > 9 ? "9+" : "${item.badgeCount}",
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? activeColor : inactiveColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Small accent indicator dot
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? activeColor : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
