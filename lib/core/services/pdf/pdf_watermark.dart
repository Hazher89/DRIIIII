import 'dart:ui' show Rect, Size;

import 'package:flutter/services.dart' show rootBundle;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Gjennomsiktig MAVI-logo som bakgrunnsvannmerke på alle PDF-sider (under tekst).
///
/// Stil inspirert av klassisk «DRAFT»-vannmerke: stort, diagonal, lesbart under innhold.
abstract final class PdfWatermark {
  PdfWatermark._();

  /// MAVI Logistikk — standard merke for DriftPro-rapporter.
  static const primaryLogoAsset = 'assets/vision/mavi_logo.png';

  static const fallbackLogoAsset =
      'assets/branding/driftpro_logo_primary_transparent.png';

  static PdfBitmap? _cachedLogo;

  static Future<PdfBitmap?> loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo;
    for (final path in [primaryLogoAsset, fallbackLogoAsset]) {
      try {
        final data = await rootBundle.load(path);
        _cachedLogo = PdfBitmap(data.buffer.asUint8List());
        return _cachedLogo;
      } catch (_) {}
    }
    return null;
  }

  /// Tegner logo sentrert og litt på skrå, med lav opacity.
  static void paintLogo(
    PdfGraphics graphics, {
    required PdfBitmap bitmap,
    required Size size,
    double opacity = 0.14,
    double widthFactor = 0.58,
    double angleDegrees = -32,
  }) {
    final aspect = bitmap.width / bitmap.height;
    if (aspect <= 0 || !aspect.isFinite) return;

    final drawW = size.width * widthFactor.clamp(0.35, 0.85);
    final drawH = drawW / aspect;

    final state = graphics.save();
    graphics.setTransparency(opacity.clamp(0.06, 0.28));
    graphics.translateTransform(size.width / 2, size.height / 2);
    graphics.rotateTransform(angleDegrees);
    graphics.drawImage(
      bitmap,
      Rect.fromLTWH(-drawW / 2, -drawH / 2, drawW, drawH),
    );
    graphics.restore(state);
  }

  /// Legger logo bak alt innhold på alle sider (og nye sider).
  static Future<void> applyLogoBackground(
    PdfDocument doc, {
    PdfBitmap? logo,
    double opacity = 0.14,
    double widthFactor = 0.58,
    double angleDegrees = -32,
  }) async {
    final bitmap = logo ?? await loadLogo();
    if (bitmap == null || doc.pages.count == 0) return;

    final size = doc.pages[0].getClientSize();
    final stamp = PdfPageTemplateElement(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    stamp.background = true;
    stamp.dock = PdfDockStyle.fill;

    paintLogo(
      stamp.graphics,
      bitmap: bitmap,
      size: size,
      opacity: opacity,
      widthFactor: widthFactor,
      angleDegrees: angleDegrees,
    );

    doc.template.stamps.add(stamp);
  }

  /// Kall rett før `doc.save()` i alle PDF-generatorer.
  static Future<void> finalizeDocument(PdfDocument doc) async {
    await applyLogoBackground(doc);
  }
}
