import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Gjennomsiktig logo-vannmerke på alle PDF-sider (under tekst).
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

  /// Legger logo bak alt innhold på alle sider (og nye sider).
  static Future<void> applyLogoBackground(
    PdfDocument doc, {
    PdfBitmap? logo,
    double opacity = 0.10,
    double widthFactor = 0.48,
  }) async {
    final bitmap = logo ?? await loadLogo();
    if (bitmap == null || doc.pages.count == 0) return;

    final size = doc.pages[0].getClientSize();
    final stamp = PdfPageTemplateElement(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    stamp.background = true;

    final aspect = bitmap.width / bitmap.height;
    final drawW = size.width * widthFactor;
    final drawH = drawW / aspect;
    final x = (size.width - drawW) / 2;
    final y = (size.height - drawH) / 2;

    stamp.graphics.setTransparency(opacity.clamp(0.04, 0.25));
    stamp.graphics.drawImage(bitmap, Rect.fromLTWH(x, y, drawW, drawH));
    stamp.graphics.setTransparency(1.0);

    doc.template.stamps.add(stamp);
  }

  /// Kall rett før `doc.save()` i alle PDF-generatorer.
  static Future<void> finalizeDocument(PdfDocument doc) async {
    await applyLogoBackground(doc);
  }
}
