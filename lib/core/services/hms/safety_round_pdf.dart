import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../models/safety_round.dart';
import 'hms_pdf_builder.dart';

/// Genererer profesjonell PDF-rapport for arkivert vernerunde
/// (MAVI-vannmerke, sideskift, oversiktlig layout — samme stil som øvrige HMS-eksport).
class SafetyRoundPdfGenerator {
  static Future<Uint8List> generate(SafetyRound round) async {
    final b = HmsPdfBuilder()
      ..brandHeader = 'DRIFTPRO HMS'
      ..footerLeft =
          'DriftPro — vernerunde / internkontroll · konfidensielt';

    final completed = round.completedAt ?? round.createdAt ?? DateTime.now();
    final df = DateFormat('dd.MM.yyyy');
    final dtf = DateFormat('dd.MM.yyyy HH:mm');
    final participants = round.participantNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final hasAvvik = round.avvikCount > 0 || round.findings.isNotEmpty;

    b.drawDocumentHeader(
      documentType: 'Vernerunde · HMS-rapport',
      title: round.title.trim().isEmpty ? 'Vernerunde' : round.title.trim(),
      subtitle: 'Dokumentasjon for internkontroll og Arbeidstilsynet',
      reference: round.archiveNumber,
      documentDate: completed,
    );

    b.statusBanner(
      title: hasAvvik
          ? 'Avvik registrert (${round.avvikCount} punkt)'
          : 'Ingen avvik — alle sjekket OK',
      detail:
          '${round.okCount} OK · ${round.avvikCount} avvik · ${round.checklist.length} punkter totalt',
      isAlert: hasAvvik,
    );

    b.section('Rundeoversikt');
    b.keyValueGrid([
      ('Dato', dtf.format(completed)),
      ('Sted', (round.location ?? '').trim().isEmpty ? '—' : round.location!.trim()),
      (
        'Utført av',
        (round.conductorName ?? round.conductedBy).trim().isEmpty
            ? '—'
            : (round.conductorName ?? round.conductedBy).trim(),
      ),
      (
        'Deltakere',
        participants.isEmpty
            ? 'Ikke registrert'
            : participants.join(', '),
      ),
      if (round.signerRole != null && round.signerRole!.trim().isNotEmpty)
        ('Rolle', round.signerRole!.trim()),
      if (round.signedAt != null)
        (
          'Signert / stemplet',
          '${dtf.format(round.signedAt!)}${round.signedByName != null && round.signedByName!.trim().isNotEmpty ? ' · ${round.signedByName!.trim()}' : ''}',
        ),
      if (round.scheduledDate != null)
        ('Planlagt dato', df.format(round.scheduledDate!)),
      if (round.nextRoundDate != null)
        ('Neste runde', df.format(round.nextRoundDate!)),
      ('Status', _overallLabel(round.overallStatus)),
      if (round.archiveNumber != null && round.archiveNumber!.trim().isNotEmpty)
        ('Arkivnr', round.archiveNumber!.trim()),
    ]);

    final notes = (round.roundNotes ?? '').trim();
    if (notes.isNotEmpty) {
      b.section('Notater fra runden');
      b.paragraph(notes);
    }

    if (round.checklist.isNotEmpty) {
      b.section('Sjekkliste');
      final rows = <List<String>>[];
      final marks = <String?>[];
      String? lastSection;

      for (final item in round.checklist) {
        final section = (item['section_title'] as String?)?.trim();
        final task = (item['task'] ?? item['item'] ?? '').toString().trim();
        if (task.isEmpty) continue;
        final status = _statusLabel(item['status'] as String?);
        final comment = (item['comment'] as String?)?.trim() ?? '';
        final legal = (item['legal_ref'] as String?)?.trim() ?? '';

        var punkt = task;
        if (section != null && section.isNotEmpty && section != lastSection) {
          lastSection = section;
          punkt = '$section — $task';
        }
        if (legal.isNotEmpty) {
          punkt = '$punkt ($legal)';
        }

        rows.add([status, punkt, comment.isEmpty ? '—' : comment]);
        marks.add(switch (item['status'] as String?) {
          'avvik' => 'alert',
          'n/a' => 'warn',
          _ => null,
        });
      }

      if (rows.isNotEmpty) {
        b.table(
          headers: const ['Status', 'Kontrollpunkt', 'Kommentar'],
          rows: rows,
          rowMarks: marks,
        );
      }
    }

    if (round.findings.isNotEmpty) {
      b.section('Avvik / funn');
      final findingRows = <List<String>>[];
      final findingMarks = <String?>[];
      for (final f in round.findings) {
        final desc = (f['description'] ?? f['title'] ?? '').toString().trim();
        if (desc.isEmpty) continue;
        final sev = (f['severity'] ?? '—').toString().trim();
        final action = (f['action'] ?? f['tiltak'] ?? '').toString().trim();
        findingRows.add([
          sev.isEmpty ? '—' : sev,
          desc,
          action.isEmpty ? '—' : action,
        ]);
        findingMarks.add('alert');
      }
      if (findingRows.isNotEmpty) {
        b.table(
          headers: const ['Alvorlighet', 'Beskrivelse', 'Tiltak'],
          rows: findingRows,
          rowMarks: findingMarks,
        );
      }
    }

    b.section('Bekreftelse');
    b.paragraph(
      'Denne rapporten er generert fra DriftPro og utgjør dokumentasjon '
      'av gjennomført vernerunde. MAVI Logistikk-merket i bakgrunnen '
      'bekrefter offisiell DriftPro-eksport.',
    );

    return b.build();
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

  static String _overallLabel(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'fullført':
      case 'ferdig':
        return 'Fullført';
      case 'planlagt':
      case 'scheduled':
        return 'Planlagt';
      case 'pågående':
      case 'in_progress':
        return 'Pågående';
      default:
        return status.isEmpty ? '—' : status;
    }
  }
}
