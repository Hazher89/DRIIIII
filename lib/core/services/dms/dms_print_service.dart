import 'dart:typed_data';
import 'dart:ui';

import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../pdf/pdf_watermark.dart';

/// Utskrift / PDF-utskrift for alle dokumenttyper i DMS.
class DmsPrintService {
  DmsPrintService._();

  static Future<void> printPdfBytes(
    Uint8List pdfBytes, {
    String name = 'Dokument',
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) async => pdfBytes,
      name: name,
    );
  }

  static Future<void> printText({
    required String text,
    required String title,
  }) async {
    final bytes = await _textToPdf(text, title);
    await printPdfBytes(bytes, name: title);
  }

  static Future<void> printSpreadsheet({
    required Map<String, List<List<String>>> sheets,
    required String title,
  }) async {
    final bytes = await _spreadsheetToPdf(sheets, title);
    await printPdfBytes(bytes, name: title);
  }

  static Future<void> printImage(Uint8List imageBytes, {String title = 'Bilde'}) async {
    final doc = sf.PdfDocument();
    final page = doc.pages.add();
    final image = sf.PdfBitmap(imageBytes);
    final size = page.getClientSize();
    final aspect = image.width / image.height;
    double w = size.width;
    double h = w / aspect;
    if (h > size.height) {
      h = size.height;
      w = h * aspect;
    }
    page.graphics.drawImage(
      image,
      Rect.fromLTWH((size.width - w) / 2, 20, w, h),
    );
    await PdfWatermark.finalizeDocument(doc);
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    await printPdfBytes(bytes, name: title);
  }

  static Future<Uint8List> _textToPdf(String text, String title) async {
    final doc = sf.PdfDocument();
    final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 10);
    final brush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0));
    final headerFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14,
        style: sf.PdfFontStyle.bold);

    var page = doc.pages.add();
    var y = 20.0;
    final pageWidth = page.getClientSize().width;
    page.graphics.drawString(
      title,
      headerFont,
      brush: brush,
      bounds: Rect.fromLTWH(40, y, pageWidth - 80, 24),
    );
    y += 32;

    for (final line in text.split('\n')) {
      if (y > page.getClientSize().height - 40) {
        page = doc.pages.add();
        y = 20;
      }
      page.graphics.drawString(
        line,
        font,
        brush: brush,
        bounds: Rect.fromLTWH(40, y, page.getClientSize().width - 80, 16),
      );
      y += 14;
    }

    await PdfWatermark.finalizeDocument(doc);
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    return bytes;
  }

  static Future<Uint8List> _spreadsheetToPdf(
    Map<String, List<List<String>>> sheets,
    String title,
  ) async {
    final doc = sf.PdfDocument();
    final titleFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12,
        style: sf.PdfFontStyle.bold);
    final cellFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 8);
    final brush = sf.PdfSolidBrush(sf.PdfColor(0, 0, 0));
    final headerBrush = sf.PdfSolidBrush(sf.PdfColor(33, 115, 70));
    final whiteBrush = sf.PdfSolidBrush(sf.PdfColor(255, 255, 255));

    for (final entry in sheets.entries) {
      var page = doc.pages.add();
      var y = 20.0;
      final pageWidth = page.getClientSize().width;
      page.graphics.drawString(
        '$title – ${entry.key}',
        titleFont,
        brush: brush,
        bounds: Rect.fromLTWH(20, y, pageWidth - 40, 20),
      );
      y += 28;

      final data = entry.value;
      if (data.isEmpty) continue;

      final colCount =
          data.fold<int>(0, (m, r) => r.length > m ? r.length : m);
      final colWidth =
          ((pageWidth - 40) / colCount.clamp(1, 8)).clamp(40.0, 120.0);

      for (var r = 0; r < data.length && r < 80; r++) {
        if (y > page.getClientSize().height - 30) {
          page = doc.pages.add();
          y = 20;
        }
        var x = 20.0;
        for (var c = 0; c < colCount && c < 12; c++) {
          final val = c < data[r].length ? data[r][c] : '';
          final cellRect = Rect.fromLTWH(x, y, colWidth, 16);
          if (r == 0) {
            page.graphics.drawRectangle(brush: headerBrush, bounds: cellRect);
            page.graphics.drawString(
              val,
              cellFont,
              brush: whiteBrush,
              bounds: cellRect,
            );
          } else {
            page.graphics.drawString(
              val,
              cellFont,
              brush: brush,
              bounds: cellRect,
            );
          }
          x += colWidth;
        }
        y += 16;
      }
    }

    await PdfWatermark.finalizeDocument(doc);
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    return bytes;
  }
}
