import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

// ── Gradient Background ────────────────────────────────────────────────────
class GradientBackground extends StatelessWidget {
  final Widget child;
  const GradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
      child: child,
    );
  }
}

// ── Glass Card ─────────────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.gradient,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? AppTheme.radiusLG,
        gradient: gradient ??
            LinearGradient(
              colors: [
                // ĐÃ SỬA: Thay .withOpacity() bằng .withValues(alpha: ...)
                AppTheme.surfaceBg.withValues(alpha: 0.8),
                AppTheme.cardBg.withValues(alpha: 0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
        border: Border.all(
          // ĐÃ SỬA: Thay .withOpacity() bằng .withValues(alpha: ...)
          color: AppTheme.lightPurple.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: boxShadow ?? AppTheme.softShadow,
      ),
      child: child,
    );
  }
}

// ── Gradient Button ────────────────────────────────────────────────────────
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Gradient gradient;
  final IconData? icon;
  final bool isLoading;
  final double? width;

  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.gradient = AppTheme.primaryGradient,
    this.icon,
    this.isLoading = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: AppTheme.radiusMD,
          boxShadow: AppTheme.glowShadow(AppTheme.primaryPurple),
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Chip Badge ─────────────────────────────────────────────────────────────
class ChipBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ChipBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // ĐÃ SỬA: Thay .withOpacity() bằng .withValues(alpha: ...)
        color: color.withValues(alpha: 0.2),
        borderRadius: AppTheme.radiusSM,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Lever Toggle ───────────────────────────────────────────────────────────
class LeverToggle extends StatelessWidget {
  final int index;
  final bool isOn;
  final bool isEnabled;
  final VoidCallback? onTap;

  const LeverToggle({
    super.key,
    required this.index,
    required this.isOn,
    required this.isEnabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // ĐÃ SỬA: Xóa biến 'activeColor' vì bạn không sử dụng nó (lỗi severity 4)
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusSM,
          color: isEnabled
              ? (isOn
                  ? AppTheme.accentYellow.withValues(alpha: 0.2)
                  : AppTheme.surfaceBg)
              : AppTheme.cardBg,
          border: Border.all(
            color: isEnabled
                ? (isOn ? AppTheme.accentYellow : AppTheme.textMuted.withValues(alpha: 0.3))
                : AppTheme.textMuted.withValues(alpha: 0.1),
            width: isOn ? 1.5 : 1,
          ),
          boxShadow: isOn && isEnabled
              ? AppTheme.glowShadow(AppTheme.accentYellow, blur: 12)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isEnabled
                    ? (isOn ? AppTheme.accentYellow : AppTheme.textMuted)
                    : AppTheme.textMuted.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 16,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: isEnabled && isOn
                    ? AppTheme.warmGradient
                    : LinearGradient(
                        colors: isEnabled
                            ? [
                                AppTheme.textMuted.withValues(alpha: 0.5),
                                AppTheme.textMuted.withValues(alpha: 0.3)
                              ]
                            : [
                                AppTheme.textMuted.withValues(alpha: 0.15),
                                AppTheme.textMuted.withValues(alpha: 0.1)
                              ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOn ? 'BẬT' : 'TẮT',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: isEnabled
                    ? (isOn ? AppTheme.accentYellow : AppTheme.textMuted)
                    : AppTheme.textMuted.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}