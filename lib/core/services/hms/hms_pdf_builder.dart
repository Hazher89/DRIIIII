import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Formell HMS-PDF med DriftPro-header, seksjoner og sidetall.
class HmsPdfBuilder {
  static const double margin = 42;
  static const double bottomReserve = 48;

  final PdfDocument doc = PdfDocument();
  late PdfPage page;
  double y = margin;

  final PdfFont titleFont =
      PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
  final PdfFont docTypeFont =
      PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
  final PdfFont sectionFont =
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
  final PdfFont labelFont =
      PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
  final PdfFont bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
  final PdfFont smallFont = PdfStandardFont(PdfFontFamily.helvetica, 7.5);
  final PdfFont tableHeaderFont =
      PdfStandardFont(PdfFontFamily.helvetica, 7.5, style: PdfFontStyle.bold);
  final PdfFont tableCellFont = PdfStandardFont(PdfFontFamily.helvetica, 7);

  final PdfBrush darkBrush = PdfSolidBrush(PdfColor(28, 28, 28));
  final PdfBrush mutedBrush = PdfSolidBrush(PdfColor(90, 90, 90));
  final PdfBrush whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
  final PdfBrush brandBrush = PdfSolidBrush(PdfColor(33, 115, 70));
  final PdfBrush brandLightBrush = PdfSolidBrush(PdfColor(232, 245, 236));
  final PdfBrush lineBrush = PdfSolidBrush(PdfColor(210, 210, 210));

  final DateFormat _df = DateFormat('dd.MM.yyyy');
  final DateFormat _dtf = DateFormat('dd.MM.yyyy HH:mm');

  double get _pageWidth => page.getClientSize().width;
  double get _contentWidth => _pageWidth - margin * 2;
  double get _pageHeight => page.getClientSize().height;

  HmsPdfBuilder() {
    page = doc.pages.add();
    y = margin;
  }

  void newPage({PdfPageOrientation orientation = PdfPageOrientation.portrait}) {
    doc.pageSettings.orientation = orientation;
    page = doc.pages.add();
    y = margin;
  }

  void ensureSpace(double needed) {
    if (y + needed > _pageHeight - bottomReserve) {
      newPage();
    }
  }

  void drawDocumentHeader({
    required String documentType,
    required String title,
    String? subtitle,
    String? reference,
    DateTime? documentDate,
  }) {
    final barH = 28.0;
    page.graphics.drawRectangle(
      brush: brandBrush,
      bounds: Rect.fromLTWH(0, 0, _pageWidth, barH),
    );
    page.graphics.drawString(
      'DRIFTPRO HMS',
      docTypeFont,
      brush: whiteBrush,
      bounds: Rect.fromLTWH(margin, 8, _contentWidth * 0.4, 14),
    );
    page.graphics.drawString(
      documentType.toUpperCase(),
      docTypeFont,
      brush: whiteBrush,
      bounds: Rect.fromLTWH(_pageWidth - margin - _contentWidth * 0.55, 8, _contentWidth * 0.55, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    y = barH + 18;

    page.graphics.drawString(
      title,
      titleFont,
      brush: darkBrush,
      bounds: Rect.fromLTWH(margin, y, _contentWidth, 26),
    );
    y += 28;

    if (subtitle != null && subtitle.trim().isNotEmpty) {
      y = _drawWrapped(subtitle.trim(), bodyFont, mutedBrush, y, lineHeight: 12) + 4;
    }

    final meta = <String>[
      'Generert: ${_dtf.format(DateTime.now())}',
      if (documentDate != null) 'Dokumentdato: ${_df.format(documentDate)}',
      if (reference != null && reference.isNotEmpty) 'Referanse: $reference',
    ];
    for (final line in meta) {
      page.graphics.drawString(
        line,
        smallFont,
        brush: mutedBrush,
        bounds: Rect.fromLTWH(margin, y, _contentWidth, 11),
      );
      y += 11;
    }
    y += 8;
    _drawHr();
  }

  void section(String title) {
    ensureSpace(28);
    y += 6;
    page.graphics.drawRectangle(
      brush: brandLightBrush,
      bounds: Rect.fromLTWH(margin, y, _contentWidth, 20),
    );
    page.graphics.drawString(
      title.toUpperCase(),
      sectionFont,
      brush: brandBrush,
      bounds: Rect.fromLTWH(margin + 8, y + 4, _contentWidth - 16, 16),
    );
    y += 26;
  }

  void field(String label, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;
    ensureSpace(20);
    page.graphics.drawString(
      label,
      labelFont,
      brush: darkBrush,
      bounds: Rect.fromLTWH(margin, y, _contentWidth, 12),
    );
    y += 13;
    y = _drawWrapped(v, bodyFont, darkBrush, y, lineHeight: 11.5) + 6;
  }

  void paragraph(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return;
    ensureSpace(16);
    y = _drawWrapped(t, bodyFont, darkBrush, y, lineHeight: 11.5) + 8;
  }

  void bullets(Iterable<String> items) {
    for (final item in items) {
      final t = item.trim();
      if (t.isEmpty) continue;
      ensureSpace(14);
      page.graphics.drawString('•', bodyFont, brush: darkBrush,
          bounds: Rect.fromLTWH(margin, y, 10, 12));
      y = _drawWrapped(t, bodyFont, darkBrush, y, indent: 12, lineHeight: 11.5) + 4;
    }
    y += 4;
  }

  void keyValueGrid(List<(String, String)> pairs, {int columns = 2}) {
    if (pairs.isEmpty) return;
    final colW = (_contentWidth - (columns - 1) * 12) / columns;
    var col = 0;
    var rowY = y;
    var maxRowH = 0.0;

    for (final pair in pairs) {
      final label = pair.$1;
      final value = pair.$2.trim();
      if (value.isEmpty) continue;
      final x = margin + col * (colW + 12);
      page.graphics.drawString(
        label,
        labelFont,
        brush: mutedBrush,
        bounds: Rect.fromLTWH(x, rowY, colW, 11),
      );
      final endY = _drawWrapped(value, bodyFont, darkBrush, rowY + 12,
          width: colW, lineHeight: 11);
      final cellH = endY - rowY + 4;
      if (cellH > maxRowH) maxRowH = cellH;

      col++;
      if (col >= columns) {
        col = 0;
        rowY += maxRowH + 8;
        maxRowH = 0;
        ensureSpace(40);
      }
    }
    y = col == 0 ? rowY : rowY + maxRowH + 8;
  }

  void table({
    required List<String> headers,
    required List<List<String>> rows,
    PdfPageOrientation? landscapeIfWide,
  }) {
    if (headers.isEmpty || rows.isEmpty) return;

    final useLandscape = landscapeIfWide != null && headers.length > 5;
    if (useLandscape) {
      ensureSpace(60);
      newPage(orientation: landscapeIfWide);
    }

    final colCount = headers.length;
    final tableW = _contentWidth;
    final colW = (tableW / colCount).clamp(36.0, 200.0);
    final rowH = 16.0;

    void drawHeaderRow() {
      ensureSpace(rowH + 4);
      var x = margin;
      for (var i = 0; i < colCount; i++) {
        final rect = Rect.fromLTWH(x, y, colW, rowH);
        page.graphics.drawRectangle(brush: brandBrush, bounds: rect);
        page.graphics.drawString(
          headers[i],
          tableHeaderFont,
          brush: whiteBrush,
          bounds: Rect.fromLTWH(x + 3, y + 3, colW - 6, rowH - 4),
          format: PdfStringFormat(
            wordWrap: PdfWordWrapType.word,
            alignment: PdfTextAlignment.left,
          ),
        );
        x += colW;
      }
      y += rowH;
    }

    drawHeaderRow();

    for (final row in rows) {
      ensureSpace(rowH);
      var x = margin;
      for (var c = 0; c < colCount; c++) {
        final val = c < row.length ? row[c] : '';
        final rect = Rect.fromLTWH(x, y, colW, rowH);
        page.graphics.drawRectangle(
          pen: PdfPen(PdfColor(210, 210, 210), width: 0.3),
          bounds: rect,
        );
        page.graphics.drawString(
          val,
          tableCellFont,
          brush: darkBrush,
          bounds: Rect.fromLTWH(x + 3, y + 3, colW - 6, rowH - 4),
          format: PdfStringFormat(
            wordWrap: PdfWordWrapType.word,
            alignment: PdfTextAlignment.left,
          ),
        );
        x += colW;
      }
      y += rowH;
    }
    y += 10;
  }

  void _drawHr() {
    page.graphics.drawLine(
      PdfPen(PdfColor(210, 210, 210), width: 0.8),
      Offset(margin, y),
      Offset(_pageWidth - margin, y),
    );
    y += 10;
  }

  double _drawWrapped(
    String text,
    PdfFont font,
    PdfBrush brush,
    double startY, {
    double indent = 0,
    double? width,
    double lineHeight = 12,
  }) {
    final w = width ?? (_contentWidth - indent);
    final lines = _wrapLines(text, font, w);
    var cy = startY;
    for (final line in lines) {
      if (cy + lineHeight > _pageHeight - bottomReserve) {
        newPage();
        cy = margin;
      }
      page.graphics.drawString(
        line,
        font,
        brush: brush,
        bounds: Rect.fromLTWH(margin + indent, cy, w, lineHeight + 2),
      );
      cy += lineHeight;
    }
    return cy;
  }

  List<String> _wrapLines(String text, PdfFont font, double maxWidth) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final trial = current.isEmpty ? word : '$current $word';
      final size = font.measureString(trial);
      if (size.width > maxWidth && current.isNotEmpty) {
        lines.add(current);
        current = word;
      } else {
        current = trial;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    if (lines.isEmpty) lines.add('');
    return lines;
  }

  void _stampFooters() {
    final total = doc.pages.count;
    for (var i = 0; i < total; i++) {
      final p = doc.pages[i];
      final h = p.getClientSize().height;
      final w = p.getClientSize().width;
      p.graphics.drawLine(
        PdfPen(PdfColor(210, 210, 210), width: 0.5),
        Offset(margin, h - 32),
        Offset(w - margin, h - 32),
      );
      p.graphics.drawString(
        'DriftPro HMS — konfidensielt internt dokument',
        smallFont,
        brush: mutedBrush,
        bounds: Rect.fromLTWH(margin, h - 24, w - margin * 2, 10),
      );
      p.graphics.drawString(
        'Side ${i + 1} av $total',
        smallFont,
        brush: mutedBrush,
        bounds: Rect.fromLTWH(margin, h - 24, w - margin * 2, 10),
        format: PdfStringFormat(alignment: PdfTextAlignment.right),
      );
    }
  }

  Future<Uint8List> build() async {
    _stampFooters();
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    return bytes;
  }
}
