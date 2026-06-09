import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'driftpro_living_scenes.dart';

/// Tegner én shufflet DriftPro-scene om gangen inne i D-merket.
class DriftProLivingMarkPainter extends CustomPainter {
  DriftProLivingMarkPainter({
    required this.scene,
    required this.sceneT,
    required this.sceneOpacity,
    required this.isDark,
  });

  final DriftProLivingScene scene;
  final double sceneT;
  final double sceneOpacity;
  final bool isDark;

  static const Color _green = DriftProTheme.primaryGreen;
  static const Color _greenLight = DriftProTheme.primaryGreenLight;
  static const Color _blue = DriftProTheme.accentBlue;

  Offset _p(double x, double y, Size size) => Offset(x * size.width, y * size.height);

  Path dOutline(Size size) {
    return Path()
      ..moveTo(_p(0.20, 0.07, size).dx, _p(0.20, 0.07, size).dy)
      ..lineTo(_p(0.13, 0.14, size).dx, _p(0.13, 0.14, size).dy)
      ..lineTo(_p(0.20, 0.21, size).dx, _p(0.20, 0.21, size).dy)
      ..lineTo(_p(0.20, 0.79, size).dx, _p(0.20, 0.79, size).dy)
      ..lineTo(_p(0.13, 0.86, size).dx, _p(0.13, 0.86, size).dy)
      ..lineTo(_p(0.20, 0.93, size).dx, _p(0.20, 0.93, size).dy)
      ..cubicTo(
        _p(0.62, 0.98, size).dx, _p(0.62, 0.98, size).dy,
        _p(0.93, 0.78, size).dx, _p(0.93, 0.78, size).dy,
        _p(0.93, 0.50, size).dx, _p(0.93, 0.50, size).dy,
      )
      ..cubicTo(
        _p(0.93, 0.22, size).dx, _p(0.93, 0.22, size).dy,
        _p(0.62, 0.02, size).dx, _p(0.62, 0.02, size).dy,
        _p(0.20, 0.07, size).dx, _p(0.20, 0.07, size).dy,
      )
      ..close();
  }

  static const double _sceneScale = 0.68;
  static const double _sceneCenterX = 0.54;
  static const double _sceneCenterY = 0.42;

  void _withSceneScale(Canvas canvas, Size size, VoidCallback draw) {
    final cx = size.width * _sceneCenterX;
    final cy = size.height * _sceneCenterY;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(_sceneScale);
    canvas.translate(-cx, -cy);
    draw();
    canvas.restore();
  }

  void _drawCaption(Canvas canvas, Size size, String text, double alpha) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: (isDark ? Colors.white : _green).withValues(alpha: alpha),
          fontSize: size.width * 0.095,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.58);

    final pos = Offset(
      (size.width - tp.width) / 2,
      size.height * 0.66,
    );
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(pos.dx - 3, pos.dy - 1, tp.width + 6, tp.height + 2),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      bg,
      Paint()..color = (isDark ? Colors.black : Colors.white).withValues(alpha: alpha * 0.55),
    );
    tp.paint(canvas, pos);
  }

  void _drawNode(Canvas canvas, Offset c, String label, double r, Color color, double alpha) {
    canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: alpha));
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: Colors.white, fontSize: r * 1.15, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  Offset _alongPolyline(List<Offset> pts, double t) {
    if (pts.length < 2) return pts.first;
    final segs = <double>[];
    var total = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final len = (pts[i + 1] - pts[i]).distance;
      segs.add(len);
      total += len;
    }
    var dist = (t % 1) * total;
    for (var i = 0; i < segs.length; i++) {
      if (dist <= segs[i]) {
        final f = segs[i] == 0 ? 0.0 : dist / segs[i];
        return Offset.lerp(pts[i], pts[i + 1], f)!;
      }
      dist -= segs[i];
    }
    return pts.last;
  }

  void _drawVan(Canvas canvas, double s, Color color) {
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.52),
      Radius.circular(s * 0.14),
    );
    canvas.drawRRect(body, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s * 0.08, -s * 0.06), width: s * 0.42, height: s * 0.24),
        Radius.circular(s * 0.05),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    for (final dx in [-s * 0.3, s * 0.3]) {
      canvas.drawCircle(Offset(dx, s * 0.32), s * 0.12, Paint()..color = const Color(0xFF37474F));
      canvas.drawCircle(Offset(dx, s * 0.32), s * 0.05, Paint()..color = Colors.white70);
    }
  }

  void _drawPackage(Canvas canvas, Offset c, double s, Color color) {
    final r = Rect.fromCenter(center: c, width: s, height: s * 0.82);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(s * 0.1)),
      Paint()..color = color,
    );
    canvas.drawLine(
      Offset(r.left, r.top + r.height * 0.32),
      Offset(r.right, r.top + r.height * 0.32),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = s * 0.09,
    );
    canvas.drawLine(
      Offset(r.center.dx, r.top),
      Offset(r.center.dx, r.bottom),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = s * 0.06,
    );
  }

  void _drawFile(Canvas canvas, Offset c, double s, Color color) {
    final path = Path()
      ..moveTo(c.dx - s * 0.42, c.dy - s * 0.5)
      ..lineTo(c.dx + s * 0.08, c.dy - s * 0.5)
      ..lineTo(c.dx + s * 0.42, c.dy - s * 0.12)
      ..lineTo(c.dx + s * 0.42, c.dy + s * 0.5)
      ..lineTo(c.dx - s * 0.42, c.dy + s * 0.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(c.dx - s * 0.2, c.dy - s * 0.05),
      Offset(c.dx + s * 0.2, c.dy - s * 0.05),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..strokeWidth = s * 0.08,
    );
  }

  void _drawPerson(Canvas canvas, Offset c, double s, Color color) {
    canvas.drawCircle(c + Offset(0, -s * 0.34), s * 0.24, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c + Offset(0, s * 0.14), width: s * 0.58, height: s * 0.52),
        Radius.circular(s * 0.16),
      ),
      Paint()..color = color,
    );
  }

  void _drawCheck(Canvas canvas, Offset c, double s, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(c + Offset(-s * 0.35, 0), c + Offset(-s * 0.05, s * 0.3), paint);
    canvas.drawLine(c + Offset(-s * 0.05, s * 0.3), c + Offset(s * 0.42, -s * 0.32), paint);
  }

  void _drawRouteDelivery(Canvas canvas, Size size, double alpha) {
    final stops = [
      _p(0.66, 0.30, size),
      _p(0.80, 0.44, size),
      _p(0.74, 0.58, size),
      _p(0.62, 0.68, size),
      _p(0.66, 0.30, size),
    ];
    final paint = Paint()
      ..color = _blue.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.038
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < stops.length - 1; i++) {
      canvas.drawLine(stops[i], stops[i + 1], paint);
    }

    const labels = ['A', 'B', 'C', 'D'];
    for (var i = 0; i < 4; i++) {
      _drawNode(canvas, stops[i], labels[i], size.width * 0.038, _blue, alpha);
    }

    final vanPos = _alongPolyline(stops, sceneT);
    final next = _alongPolyline(stops, sceneT + 0.02);
    final angle = math.atan2(next.dy - vanPos.dy, next.dx - vanPos.dx);
    canvas.save();
    canvas.translate(vanPos.dx, vanPos.dy);
    canvas.rotate(angle);
    _drawVan(canvas, size.width * 0.2, _green.withValues(alpha: alpha));
    canvas.restore();
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawPcFiles(Canvas canvas, Size size, double alpha) {
    final center = _p(0.54, 0.46, size);
    final w = size.width * 0.34;
    final h = size.width * 0.22;
    final screen = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center + Offset(0, -h * 0.15), width: w, height: h),
      Radius.circular(size.width * 0.025),
    );
    canvas.drawRRect(screen, Paint()..color = _blue.withValues(alpha: alpha * 0.7));
    canvas.drawRRect(
      screen,
      Paint()
        ..color = _blue.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.028,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center + Offset(0, h * 0.42), width: w * 0.9, height: h * 0.18),
        Radius.circular(2),
      ),
      Paint()..color = (isDark ? Colors.white24 : Colors.black26).withValues(alpha: alpha),
    );

    for (var i = 0; i < 2; i++) {
      final t = (sceneT + i * 0.35) % 1;
      final start = center + Offset(w * 0.1, -h * 0.1);
      final end = center + Offset(w * 0.7, -h * 0.9);
      _drawFile(canvas, Offset.lerp(start, end, Curves.easeOut.transform(t))!, size.width * 0.1, _blue.withValues(alpha: alpha));
    }
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawFollowUp(Canvas canvas, Size size, double alpha) {
    final c = _p(0.54, 0.44, size);
    final box = size.width * 0.34;
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: box, height: box * 0.9),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: alpha * 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = _green.withValues(alpha: alpha * 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.022,
    );

    for (var i = 0; i < 3; i++) {
      final y = c.dy - box * 0.28 + i * box * 0.28;
      final done = sceneT > 0.15 + i * 0.25;
      if (done) {
        _drawCheck(canvas, Offset(c.dx - box * 0.28, y), size.width * 0.07, _green.withValues(alpha: alpha));
      } else {
        canvas.drawCircle(
          Offset(c.dx - box * 0.28, y),
          size.width * 0.028,
          Paint()
            ..color = (isDark ? Colors.white38 : Colors.black26).withValues(alpha: alpha),
        );
      }
      canvas.drawLine(
        Offset(c.dx - box * 0.12, y),
        Offset(c.dx + box * 0.3, y),
        Paint()
          ..color = (isDark ? Colors.white54 : Colors.black38).withValues(alpha: alpha * (done ? 0.85 : 0.45))
          ..strokeWidth = size.width * 0.022
          ..strokeCap = StrokeCap.round,
      );
    }
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawSickReport(Canvas canvas, Size size, double alpha) {
    final c = _p(0.54, 0.44, size);
    final s = size.width * 0.2;
    final pulse = (math.sin(sceneT * math.pi * 5) + 1) * 0.5;
    canvas.drawCircle(
      c,
      s * 0.55 + pulse * s * 0.06,
      Paint()..color = DriftProTheme.error.withValues(alpha: alpha * 0.25),
    );
    _drawPerson(canvas, c, s, DriftProTheme.error.withValues(alpha: alpha));

    final cross = s * 0.22;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = size.width * 0.032
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-cross, -cross * 0.2), c + Offset(cross, cross * 0.2), paint);
    canvas.drawLine(c + Offset(-cross, cross * 0.2), c + Offset(cross, -cross * 0.2), paint);
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawBirthday(Canvas canvas, Size size, double alpha) {
    final c = _p(0.54, 0.44, size);
    final s = size.width * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c + Offset(0, s * 0.14), width: s, height: s * 0.5),
        Radius.circular(s * 0.08),
      ),
      Paint()..color = const Color(0xFFFFB74D).withValues(alpha: alpha),
    );
    final flame = (math.sin(sceneT * math.pi * 7) + 1) * 0.5;
    canvas.drawCircle(
      c + Offset(0, -s * 0.2),
      s * (0.1 + flame * 0.035),
      Paint()..color = const Color(0xFFFF7043).withValues(alpha: alpha),
    );
    canvas.drawLine(
      c + Offset(0, -s * 0.06),
      c + Offset(0, -s * 0.18),
      Paint()
        ..color = (isDark ? Colors.white70 : Colors.black54).withValues(alpha: alpha)
        ..strokeWidth = size.width * 0.024,
    );
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawHubSync(Canvas canvas, Size size, double alpha) {
    final hub = _p(0.54, 0.44, size);
    final pulse = (math.sin(sceneT * math.pi * 4) + 1) * 0.5;
    canvas.drawCircle(hub, size.width * 0.1, Paint()..color = _green.withValues(alpha: alpha * 0.35));
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        hub,
        size.width * (0.1 + i * 0.05 + pulse * 0.02),
        Paint()
          ..color = _green.withValues(alpha: alpha * (0.9 - i * 0.2))
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.024,
      );
    }
    for (var i = 0; i < 4; i++) {
      final t = (sceneT + i * 0.2) % 1;
      final angle = i * (math.pi / 2) + 0.4;
      final pos = hub + Offset(math.cos(angle), math.sin(angle)) * size.width * (0.12 + t * 0.16);
      canvas.drawCircle(pos, size.width * 0.024, Paint()..color = _greenLight.withValues(alpha: alpha * (1 - t * 0.5)));
    }
    final tp = TextPainter(
      text: TextSpan(text: '↻', style: TextStyle(color: _green.withValues(alpha: alpha), fontSize: size.width * 0.16, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, hub - Offset(tp.width / 2, tp.height / 2));
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawPackageLeg(Canvas canvas, Size size, double alpha) {
    final a = _p(0.44, 0.62, size);
    final b = _p(0.58, 0.44, size);
    final c = _p(0.72, 0.58, size);
    final paint = Paint()
      ..color = _green.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.036
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    canvas.drawLine(b, c, paint);

    for (final (label, pt) in [('A', a), ('B', b), ('C', c)]) {
      _drawNode(canvas, pt, label, size.width * 0.034, _green, alpha);
    }

    final pos = sceneT < 0.5
        ? Offset.lerp(a, b, sceneT * 2)!
        : Offset.lerp(b, c, (sceneT - 0.5) * 2)!;
    _drawPackage(canvas, pos, size.width * 0.12, _greenLight.withValues(alpha: alpha));
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawAvvikAlert(Canvas canvas, Size size, double alpha) {
    final c = _p(0.54, 0.44, size);
    final s = size.width * 0.24;
    final blink = (math.sin(sceneT * math.pi * 4) + 1) * 0.5;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - s * 0.48)
        ..lineTo(c.dx + s * 0.46, c.dy + s * 0.36)
        ..lineTo(c.dx - s * 0.46, c.dy + s * 0.36)
        ..close(),
      Paint()..color = DriftProTheme.warning.withValues(alpha: alpha * (0.75 + blink * 0.25)),
    );
    canvas.drawLine(
      Offset(c.dx, c.dy - s * 0.14),
      Offset(c.dx, c.dy + s * 0.08),
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = size.width * 0.03
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(c + Offset(0, s * 0.2), size.width * 0.018, Paint()..color = Colors.white.withValues(alpha: alpha));
    _drawCaption(canvas, size, scene.caption, alpha);
  }

  void _drawScene(Canvas canvas, Size size) {
    final alpha = sceneOpacity;
    switch (scene) {
      case DriftProLivingScene.routeDelivery:
        _drawRouteDelivery(canvas, size, alpha);
      case DriftProLivingScene.pcFiles:
        _drawPcFiles(canvas, size, alpha);
      case DriftProLivingScene.followUp:
        _drawFollowUp(canvas, size, alpha);
      case DriftProLivingScene.sickReport:
        _drawSickReport(canvas, size, alpha);
      case DriftProLivingScene.birthday:
        _drawBirthday(canvas, size, alpha);
      case DriftProLivingScene.hubSync:
        _drawHubSync(canvas, size, alpha);
      case DriftProLivingScene.packageLeg:
        _drawPackageLeg(canvas, size, alpha);
      case DriftProLivingScene.avvikAlert:
        _drawAvvikAlert(canvas, size, alpha);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = isDark ? const Color(0xFFE8EDE9) : const Color(0xFF2D3436);
    final outline = dOutline(size);

    canvas.save();
    canvas.clipPath(outline);
    _withSceneScale(canvas, size, () => _drawScene(canvas, size));
    canvas.restore();

    canvas.drawPath(
      outline,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.05
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant DriftProLivingMarkPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.sceneT != sceneT ||
        oldDelegate.sceneOpacity != sceneOpacity ||
        oldDelegate.isDark != isDark;
  }
}
