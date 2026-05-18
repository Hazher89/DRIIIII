import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../models/safety_round.dart';

/// Genererer PDF-rapport for arkivert vernerunde.
class SafetyRoundPdfGenerator {
  static Future<Uint8List> generate(SafetyRound round) async {
    final doc = PdfDocument();
    final page = doc.pages.add();
    final g = page.graphics;
    final titleFont = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
    final headFont = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final smallFont = PdfStandardFont(PdfFontFamily.helvetica, 8);

    var y = 20.0;
    const margin = 40.0;
    final width = page.getClientSize().width - margin * 2;

    g.drawString('VERNERUNDE – HMS RAPPORT', titleFont, bounds: Rect.fromLTWH(margin, y, width, 24));
    y += 28;
    g.drawString(round.title, headFont, bounds: Rect.fromLTWH(margin, y, width, 18));
    y += 22;

    final completed = round.completedAt ?? round.createdAt ?? DateTime.now();
    final df = DateFormat('dd.MM.yyyy HH:mm');
    g.drawString('Arkivnr: ${round.archiveNumber ?? "—"}', bodyFont, bounds: Rect.fromLTWH(margin, y, width, 14));
    y += 14;
    g.drawString('Fullført: ${df.format(completed)}', bodyFont, bounds: Rect.fromLTWH(margin, y, width, 14));
    y += 14;
    g.drawString('Utført av: ${round.conductorName ?? round.conductedBy}', bodyFont,
        bounds: Rect.fromLTWH(margin, y, width, 14));
    y += 14;
    if (round.location != null && round.location!.isNotEmpty) {
      g.drawString('Sted: ${round.location}', bodyFont, bounds: Rect.fromLTWH(margin, y, width, 14));
      y += 14;
    }
    if (round.signerRole != null) {
      g.drawString('Rolle: ${round.signerRole}', bodyFont, bounds: Rect.fromLTWH(margin, y, width, 14));
      y += 14;
    }
    if (round.signedAt != null) {
      g.drawString(
        'Signert/stemplet: ${df.format(round.signedAt!)} – ${round.signedByName ?? ""}',
        bodyFont,
        bounds: Rect.fromLTWH(margin, y, width, 14),
      );
      y += 18;
    }

    g.drawString('SJEKKLISTE', headFont, bounds: Rect.fromLTWH(margin, y, width, 16));
    y += 18;

    String? lastSection;
    for (final item in round.checklist) {
      final section = item['section_title'] as String?;
      if (section != null && section != lastSection) {
        lastSection = section;
        if (y > page.getClientSize().height - 80) {
          doc.pages.add();
          y = 20;
        }
        g.drawString(section, headFont, bounds: Rect.fromLTWH(margin, y, width, 14));
        y += 14;
        final legal = item['legal_ref'] as String?;
        if (legal != null && legal.isNotEmpty) {
          g.drawString(legal, smallFont, bounds: Rect.fromLTWH(margin, y, width, 12));
          y += 12;
        }
      }
      final task = item['task'] ?? item['item'] ?? '';
      final status = _statusLabel(item['status'] as String?);
      final comment = item['comment'] as String? ?? '';
      final line = '[$status] $task${comment.isNotEmpty ? " – $comment" : ""}';
      if (y > page.getClientSize().height - 40) {
        doc.pages.add();
        y = 20;
      }
      g.drawString(line, bodyFont, bounds: Rect.fromLTWH(margin + 8, y, width - 8, 28));
      y += 14;
    }

    if (round.findings.isNotEmpty) {
      y += 10;
      if (y > page.getClientSize().height - 60) {
        doc.pages.add();
        y = 20;
      }
      g.drawString('AVVIK / FUNN', headFont, bounds: Rect.fromLTWH(margin, y, width, 16));
      y += 16;
      for (final f in round.findings) {
        final line =
            '• ${f['description']} (${f['severity'] ?? "—"})';
        g.drawString(line, bodyFont, bounds: Rect.fromLTWH(margin, y, width, 28));
        y += 14;
      }
    }

    y += 20;
    g.drawString(
      'Generert av DriftPro – dokumentasjon for internkontroll og Arbeidstilsynet.',
      smallFont,
      bounds: Rect.fromLTWH(margin, y, width, 24),
    );

    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    return bytes;
  }

  static String _statusLabel(String? s) {
    switch (s) {
      case 'ok':
        return 'OK';
      case 'avvik':
        return 'AVVIK';
      case 'n/a':
        return 'N/A';
      default:
        return '—';
    }
  }
}
