import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

// ─── Gradient Button ──────────────────────────────────────────────────────────

class GradientButton extends StatefulWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final Widget? badge;

  const GradientButton({
    super.key,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.badge,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        _ctrl.forward();
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        _ctrl.reverse();
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: widget.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: _pressed
                ? null
                : [
                    BoxShadow(
                      color: widget.colors.first.withAlpha(89),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              // Top gloss line
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withAlpha(77),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(38),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.label,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle!,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withAlpha(191),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withAlpha(153),
                      size: 16,
                    ),
                  ],
                ),
              ),
              if (widget.badge != null)
                Positioned(top: 12, right: 14, child: widget.badge!),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType type;

  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final (color, bg, icon) = switch (type) {
      StatusType.running => (
          AppColors.success,
          AppColors.success.withAlpha(38),
          Icons.play_circle_fill_rounded,
        ),
      StatusType.starting => (
          AppColors.warning,
          AppColors.warning.withAlpha(38),
          Icons.hourglass_top_rounded,
        ),
      StatusType.success => (
          AppColors.success,
          AppColors.success.withAlpha(38),
          Icons.check_circle_rounded,
        ),
      StatusType.error => (
          AppColors.error,
          AppColors.error.withAlpha(38),
          Icons.error_rounded,
        ),
      StatusType.stopped => (
          AppColors.textMuted,
          AppColors.surfaceElevated,
          Icons.stop_circle_rounded,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(102)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (type == StatusType.running)
            _PulsingDot(color: color)
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withAlpha((_anim.value * 255).round()),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

enum StatusType { running, starting, success, error, stopped }

// ─── Section Label ────────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─── Glowing Divider ──────────────────────────────────────────────────────────

class GlowDivider extends StatelessWidget {
  final Color color;
  const GlowDivider({super.key, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            color.withAlpha(128),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─── Code Card ────────────────────────────────────────────────────────────────

class CodeCard extends StatelessWidget {
  final String code;
  final String filename;
  final VoidCallback? onCopy;

  const CodeCard({
    super.key,
    required this.code,
    required this.filename,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                // Traffic-light dots
                Row(
                  children: [Colors.red, Colors.orange, Colors.green]
                      .map(
                        (c) => Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 6),
                          decoration:
                              BoxDecoration(color: c, shape: BoxShape.circle),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    filename,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (onCopy != null)
                  InkWell(
                    onTap: onCopy,
                    child: Row(
                      children: [
                        const Icon(Icons.copy_rounded,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Code body
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: const Color(0xFFE6EDF3),
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Progress Step Indicator ──────────────────────────────────────────────────

class ProgressSteps extends StatelessWidget {
  final int total;
  final int current;

  const ProgressSteps(
      {super.key, required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final done = i < current;
        final active = i == current - 1;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              // FIXED: AppColors.diagnosisGold is now defined in app_theme.dart
              color: done
                  ? AppColors.diagnosisGold
                  : active
                      ? AppColors.diagnosisGold.withAlpha(102)
                      : AppColors.border,
            ),
          ),
        );
      }),
    );
  }
}