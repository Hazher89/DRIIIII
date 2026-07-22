import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Formell HMS-PDF med DriftPro-header, seksjoner og sidetall.
class HmsPdfBuilder {
  static const double margin = 42;
  static const double bottomReserve = 48;
  static const double colGap = 16;

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

  /// Header-merke (f.eks. «DRIFTPRO» eller «DRIFTPRO HMS»).
  String brandHeader = 'DRIFTPRO HMS';

  /// Venstre sidetekst i footer.
  String footerLeft = 'DriftPro HMS — konfidensielt internt dokument';

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
      brandHeader,
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

    y = _drawWrappedAt(
      x: margin,
      text: title,
      font: titleFont,
      brush: darkBrush,
      startY: y,
      width: _contentWidth,
      lineHeight: 20,
    ) + 6;

    if (subtitle != null && subtitle.trim().isNotEmpty) {
      y = _drawWrappedAt(
        x: margin,
        text: subtitle.trim(),
        font: bodyFont,
        brush: mutedBrush,
        startY: y,
        width: _contentWidth,
        lineHeight: 12,
      ) + 6;
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
      y += 12;
    }
    y += 6;
    _drawHr();
  }

  void section(String title) {
    ensureSpace(30);
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
    y += 28;
  }

  void field(String label, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;
    ensureSpace(28);
    page.graphics.drawString(
      label,
      labelFont,
      brush: mutedBrush,
      bounds: Rect.fromLTWH(margin, y, _contentWidth, 12),
    );
    y += 14;
    y = _drawWrappedAt(
      x: margin,
      text: v,
      font: bodyFont,
      brush: darkBrush,
      startY: y,
      width: _contentWidth,
      lineHeight: 12,
    ) + 10;
  }

  void paragraph(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return;
    ensureSpace(16);
    y = _drawWrappedAt(
      x: margin,
      text: t,
      font: bodyFont,
      brush: darkBrush,
      startY: y,
      width: _contentWidth,
      lineHeight: 12,
    ) + 10;
  }

  void bullets(Iterable<String> items) {
    for (final item in items) {
      final t = item.trim();
      if (t.isEmpty) continue;
      ensureSpace(16);
      final bulletY = y;
      page.graphics.drawString(
        '•',
        bodyFont,
        brush: darkBrush,
        bounds: Rect.fromLTWH(margin, bulletY, 10, 12),
      );
      y = _drawWrappedAt(
        x: margin + 12,
        text: t,
        font: bodyFont,
        brush: darkBrush,
        startY: bulletY,
        width: _contentWidth - 12,
        lineHeight: 12,
      ) + 6;
    }
    y += 4;
  }

  void keyValueGrid(List<(String, String)> pairs, {int columns = 2}) {
    final filtered = pairs.where((p) => p.$2.trim().isNotEmpty).toList();
    if (filtered.isEmpty) return;

    final cols = columns.clamp(1, 2);
    final colW = (_contentWidth - (cols - 1) * colGap) / cols;

    for (var i = 0; i < filtered.length; i += cols) {
      final rowTop = y;
      var rowBottom = rowTop;

      ensureSpace(36);

      for (var c = 0; c < cols; c++) {
        final idx = i + c;
        if (idx >= filtered.length) break;

        final label = filtered[idx].$1;
        final value = filtered[idx].$2.trim();
        final x = margin + c * (colW + colGap);

        page.graphics.drawString(
          label,
          labelFont,
          brush: mutedBrush,
          bounds: Rect.fromLTWH(x, rowTop, colW, 12),
        );

        final valueEnd = _drawWrappedAt(
          x: x,
          text: value,
          font: bodyFont,
          brush: darkBrush,
          startY: rowTop + 14,
          width: colW,
          lineHeight: 12,
        );

        if (valueEnd > rowBottom) rowBottom = valueEnd;
      }

      y = rowBottom + 12;
    }
  }

  void table({
    required List<String> headers,
    required List<List<String>> rows,
    PdfPageOrientation? landscapeIfWide,
  }) {
    if (headers.isEmpty || rows.isEmpty) return;

    if (landscapeIfWide != null && headers.length > 5) {
      ensureSpace(60);
      newPage(orientation: landscapeIfWide);
    }

    final colCount = headers.length;
    final colW = _contentWidth / colCount;
    const pad = 4.0;
    const lineH = 11.0;

    void drawHeaderRow() {
      final rowH = lineH + pad * 2;
      ensureSpace(rowH + 4);
      var x = margin;
      for (var i = 0; i < colCount; i++) {
        final rect = Rect.fromLTWH(x, y, colW, rowH);
        page.graphics.drawRectangle(brush: brandBrush, bounds: rect);
        _drawWrappedAt(
          x: x + pad,
          text: headers[i],
          font: tableHeaderFont,
          brush: whiteBrush,
          startY: y + pad,
          width: colW - pad * 2,
          lineHeight: lineH,
        );
        x += colW;
      }
      y += rowH;
    }

    drawHeaderRow();

    for (final row in rows) {
      var rowH = lineH + pad * 2;
      final cellLines = <int>[];
      for (var c = 0; c < colCount; c++) {
        final val = c < row.length ? row[c] : '';
        final lines = _wrapLines(val, tableCellFont, colW - pad * 2);
        cellLines.add(lines.length);
      }
      final maxLines = cellLines.fold<int>(1, (a, b) => a > b ? a : b);
      rowH = pad * 2 + maxLines * lineH;

      ensureSpace(rowH);
      var x = margin;
      for (var c = 0; c < colCount; c++) {
        final val = c < row.length ? row[c] : '';
        final rect = Rect.fromLTWH(x, y, colW, rowH);
        page.graphics.drawRectangle(
          pen: PdfPen(PdfColor(220, 220, 220), width: 0.3),
          bounds: rect,
        );
        _drawWrappedAt(
          x: x + pad,
          text: val,
          font: tableCellFont,
          brush: darkBrush,
          startY: y + pad,
          width: colW - pad * 2,
          lineHeight: lineH,
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

  double _drawWrappedAt({
    required double x,
    required String text,
    required PdfFont font,
    required PdfBrush brush,
    required double startY,
    required double width,
    double lineHeight = 12,
  }) {
    final lines = _wrapLines(text, font, width);
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
        bounds: Rect.fromLTWH(x, cy, width, lineHeight + 1),
      );
      cy += lineHeight;
    }
    return cy;
  }

  List<String> _wrapLines(String text, PdfFont font, double maxWidth) {
    if (text.isEmpty) return [''];
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      final words = paragraph.split(RegExp(r'\s+'));
      var current = '';
      for (final word in words) {
        if (word.isEmpty) continue;
        final trial = current.isEmpty ? word : '$current $word';
        if (font.measureString(trial).width > maxWidth && current.isNotEmpty) {
          lines.add(current);
          current = word;
        } else {
          current = trial;
        }
      }
      if (current.isNotEmpty) lines.add(current);
      if (paragraph.isEmpty) lines.add('');
    }
    return lines.isEmpty ? [''] : lines;
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
        footerLeft,
        smallFont,
        brush: mutedBrush,
        bounds: Rect.fromLTWH(margin, h - 22, w - margin * 2, 10),
      );
      p.graphics.drawString(
        'Side ${i + 1} av $total',
        smallFont,
        brush: mutedBrush,
        bounds: Rect.fromLTWH(margin, h - 22, w - margin * 2, 10),
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
