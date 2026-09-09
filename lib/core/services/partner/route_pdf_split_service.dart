import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'route_pdf_text_service.dart';

/// Én rute-PDF etter splitting av samledokument.
class RoutePdfSplitPart {
  final String fileName;
  final Uint8List bytes;
  final String? maviCode;
  final int startPage;
  final int endPageInclusive;
  final int pageCount;

  const RoutePdfSplitPart({
    required this.fileName,
    required this.bytes,
    required this.maviCode,
    required this.startPage,
    required this.endPageInclusive,
    required this.pageCount,
  });
}

/// Resultat av analyse/splitting: én fil → 1..N rute-PDF-er.
class RoutePdfExpandResult {
  final String sourceFileName;
  final int sourcePageCount;
  final List<RoutePdfSplitPart> parts;
  final bool wasSplit;

  const RoutePdfExpandResult({
    required this.sourceFileName,
    required this.sourcePageCount,
    required this.parts,
    required this.wasSplit,
  });

  int get routeCount => parts.length;
}

/// Splitt samle-PDF (mange Trip Overview i én fil) til én PDF per rute.
///
/// Ny rute starter når en side ser ut som Trip Overview / Resource ID-header
/// (strekkode-siden). Fortsettelsessider følger til neste start.
class RoutePdfSplitService {
  RoutePdfSplitService._();

  /// True når sides tekst markerer start på ny rute (ikke bare stopp-liste).
  static bool isRouteStartPageText(String raw) {
    if (raw.trim().isEmpty) return false;
    final lower = raw.toLowerCase();

    final hasTripOverview = lower.contains('trip overview');
    final hasResourceLabel =
        lower.contains('resource id') || lower.contains('ressource id');
    final hasDriver = lower.contains('driver name') || lower.contains('sjåfør');
    final hasStowing = lower.contains('stowing lane');
    final headerCode = RoutePdfTextService.parseResourceIdTripOverviewHeader(raw);

    if (hasTripOverview && (hasResourceLabel || headerCode != null || hasDriver)) {
      return true;
    }
    // Strekkode-/forside uten eksplisitt «Trip Overview»-tekst.
    if (headerCode != null && (hasDriver || hasStowing || hasResourceLabel)) {
      return true;
    }
    if (hasResourceLabel && hasDriver && hasStowing) return true;
    return false;
  }

  /// Utvider én opplastet PDF til rute-PDF-er (split ved behov).
  static RoutePdfExpandResult expandBytes(
    Uint8List bytes, {
    required String fileName,
  }) {
    final safeName = fileName.trim().isEmpty ? 'rute.pdf' : fileName.trim();
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final pageCount = doc.pages.count;
      if (pageCount <= 1) {
        doc.dispose();
        final code = RoutePdfTextService.extractResourceIdFromBytes(bytes) ??
            RoutePdfTextService.extractResourceIdFromFileName(safeName);
        return RoutePdfExpandResult(
          sourceFileName: safeName,
          sourcePageCount: pageCount == 0 ? 1 : pageCount,
          wasSplit: false,
          parts: [
            RoutePdfSplitPart(
              fileName: safeName,
              bytes: bytes,
              maviCode: code,
              startPage: 0,
              endPageInclusive: 0,
              pageCount: pageCount == 0 ? 1 : pageCount,
            ),
          ],
        );
      }

      final extractor = PdfTextExtractor(doc);
      final starts = <int>[];
      for (var i = 0; i < pageCount; i++) {
        final layout = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
          layoutText: true,
        );
        final linear = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
          layoutText: false,
        );
        final text = '$layout\n$linear';
        if (isRouteStartPageText(text)) {
          starts.add(i);
        }
      }

      // Ingen tydelige start-sider → behandle som én rute.
      if (starts.isEmpty) {
        doc.dispose();
        final code = RoutePdfTextService.extractResourceIdFromBytes(bytes) ??
            RoutePdfTextService.extractResourceIdFromFileName(safeName);
        return RoutePdfExpandResult(
          sourceFileName: safeName,
          sourcePageCount: pageCount,
          wasSplit: false,
          parts: [
            RoutePdfSplitPart(
              fileName: safeName,
              bytes: bytes,
              maviCode: code,
              startPage: 0,
              endPageInclusive: pageCount - 1,
              pageCount: pageCount,
            ),
          ],
        );
      }

      // Første sider før første Trip Overview tilhører første rute.
      if (starts.first != 0) {
        starts.insert(0, 0);
      }

      // Kun én start → én rute (ikke split).
      if (starts.length == 1) {
        doc.dispose();
        final code = RoutePdfTextService.extractResourceIdFromBytes(bytes) ??
            RoutePdfTextService.extractResourceIdFromFileName(safeName);
        return RoutePdfExpandResult(
          sourceFileName: safeName,
          sourcePageCount: pageCount,
          wasSplit: false,
          parts: [
            RoutePdfSplitPart(
              fileName: safeName,
              bytes: bytes,
              maviCode: code,
              startPage: 0,
              endPageInclusive: pageCount - 1,
              pageCount: pageCount,
            ),
          ],
        );
      }

      final parts = <RoutePdfSplitPart>[];
      final base = _stripPdfExt(safeName);
      for (var s = 0; s < starts.length; s++) {
        final from = starts[s];
        final to = s + 1 < starts.length ? starts[s + 1] - 1 : pageCount - 1;
        final partBytes = _exportPageRange(doc, from, to);
        final code = RoutePdfTextService.extractResourceIdFromBytes(partBytes) ??
            RoutePdfTextService.extractResourceIdFromFileName(safeName);
        final label = code ?? 'del${s + 1}';
        parts.add(
          RoutePdfSplitPart(
            fileName: '${base}_${label}_p${from + 1}-${to + 1}.pdf',
            bytes: partBytes,
            maviCode: code,
            startPage: from,
            endPageInclusive: to,
            pageCount: to - from + 1,
          ),
        );
      }
      doc.dispose();
      return RoutePdfExpandResult(
        sourceFileName: safeName,
        sourcePageCount: pageCount,
        wasSplit: true,
        parts: parts,
      );
    } catch (_) {
      final code = RoutePdfTextService.extractResourceIdFromFileName(safeName);
      return RoutePdfExpandResult(
        sourceFileName: safeName,
        sourcePageCount: 1,
        wasSplit: false,
        parts: [
          RoutePdfSplitPart(
            fileName: safeName,
            bytes: bytes,
            maviCode: code,
            startPage: 0,
            endPageInclusive: 0,
            pageCount: 1,
          ),
        ],
      );
    }
  }

  /// Utvider flere opplastede filer (single + samle-PDF).
  static List<RoutePdfExpandResult> expandMany(
    List<({String fileName, Uint8List bytes})> files,
  ) {
    return [
      for (final f in files)
        expandBytes(f.bytes, fileName: f.fileName),
    ];
  }

  static String _stripPdfExt(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return name.substring(0, name.length - 4);
    return name;
  }

  static Uint8List _exportPageRange(PdfDocument source, int from, int to) {
    final dest = PdfDocument();
    dest.pageSettings.setMargins(0);
    try {
      for (var i = from; i <= to; i++) {
        final srcPage = source.pages[i];
        final template = srcPage.createTemplate();
        dest.pageSettings.size = srcPage.size;
        final page = dest.pages.add();
        page.graphics.drawPdfTemplate(
          template,
          Offset.zero,
          srcPage.size,
        );
      }
      final saved = dest.saveSync();
      return Uint8List.fromList(saved);
    } finally {
      dest.dispose();
    }
  }
}
