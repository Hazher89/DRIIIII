import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/survey/survey_living_motion.dart';

/// Levende, animert bakgrunn for respondent-visning av undersøkelser.
class SurveyLivingBackground extends StatefulWidget {
  const SurveyLivingBackground({
    super.key,
    required this.motion,
    required this.background,
    required this.primary,
    required this.accent,
    this.child,
  });

  final SurveyLivingMotion motion;
  final Color background;
  final Color primary;
  final Color accent;
  final Widget? child;

  @override
  State<SurveyLivingBackground> createState() => _SurveyLivingBackgroundState();
}

class _SurveyLivingBackgroundState extends State<SurveyLivingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _SurveyLivingPainter(
            t: _controller.value,
            motion: widget.motion,
            background: widget.background,
            primary: widget.primary,
            accent: widget.accent,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SurveyLivingPainter extends CustomPainter {
  _SurveyLivingPainter({
    required this.t,
    required this.motion,
    required this.background,
    required this.primary,
    required this.accent,
  });

  final double t;
  final SurveyLivingMotion motion;
  final Color background;
  final Color primary;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    switch (motion) {
      case SurveyLivingMotion.aurora:
        _aurora(canvas, size);
      case SurveyLivingMotion.orbs:
        _orbs(canvas, size);
      case SurveyLivingMotion.waves:
        _waves(canvas, size);
      case SurveyLivingMotion.drift:
        _drift(canvas, size);
      case SurveyLivingMotion.nordic:
        _nordic(canvas, size);
      case SurveyLivingMotion.pulse:
        _pulse(canvas, size);
    }
  }

  void _aurora(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      final phase = t * math.pi * 2 + i * 1.2;
      final path = Path();
      for (var x = 0.0; x <= size.width; x += 6) {
        final y = size.height * (0.25 + i * 0.12) +
            math.sin((x / size.width) * math.pi * 3 + phase) * size.height * 0.08;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [
              primary.withValues(alpha: 0.0),
              i.isEven ? primary.withValues(alpha: 0.14) : accent.withValues(alpha: 0.12),
              primary.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
  }

  void _orbs(Canvas canvas, Size size) {
    for (var i = 0; i < 7; i++) {
      final angle = t * math.pi * 2 + i * 0.9;
      final cx = size.width * (0.2 + (i % 3) * 0.28) + math.cos(angle) * size.width * 0.06;
      final cy = size.height * (0.15 + (i % 4) * 0.18) + math.sin(angle * 1.3) * size.height * 0.05;
      final r = size.width * (0.12 + (i % 3) * 0.04);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              (i.isEven ? primary : accent).withValues(alpha: 0.22),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }
  }

  void _waves(Canvas canvas, Size size) {
    for (var layer = 0; layer < 3; layer++) {
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += 4) {
        final y = size.height * 0.72 +
            math.sin((x / size.width) * math.pi * 4 + t * math.pi * 2 + layer) * size.height * 0.04;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = (layer.isEven ? primary : accent).withValues(alpha: 0.08 + layer * 0.03),
      );
    }
  }

  void _drift(Canvas canvas, Size size) {
    for (var i = 0; i < 24; i++) {
      final seed = i * 0.137;
      final x = ((t * 0.35 + seed) % 1) * size.width;
      final y = (math.sin(seed * 12 + t * math.pi * 2) * 0.5 + 0.5) * size.height;
      canvas.drawCircle(
        Offset(x, y),
        2 + (i % 3),
        Paint()..color = (i.isEven ? primary : accent).withValues(alpha: 0.15 + (i % 5) * 0.04),
      );
    }
  }

  void _nordic(Canvas canvas, Size size) {
    final band = Path();
    for (var x = 0.0; x <= size.width; x += 5) {
      final y = size.height * 0.18 +
          math.sin((x / size.width) * math.pi * 2 + t * math.pi * 2) * size.height * 0.06;
      if (x == 0) {
        band.moveTo(x, y);
      } else {
        band.lineTo(x, y);
      }
    }
    canvas.drawPath(
      band,
      Paint()
        ..color = primary.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      band,
      Paint()
        ..color = accent.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.06
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  void _pulse(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.35);
    for (var i = 0; i < 4; i++) {
      final phase = (t + i * 0.22) % 1;
      final r = size.width * (0.08 + phase * 0.55);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = primary.withValues(alpha: (1 - phase) * 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SurveyLivingPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.motion != motion ||
        oldDelegate.background != background ||
        oldDelegate.primary != primary ||
        oldDelegate.accent != accent;
  }
}
