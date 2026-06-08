import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../models/hms/equipment.dart';
import '../../../models/hms/hms_ticket_template.dart';
import '../../../models/hms/hms_sja_step.dart';
import '../../../models/hms/stakeholder_risk_assessment.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/safety_round.dart';
import '../../../models/sja_form.dart';
import '../../../models/ticket.dart';
import 'hms_pdf_builder.dart';
import 'safety_round_pdf.dart';

/// PDF-generatorer for alle HMS-dokumenttyper.
abstract final class HmsPdfGenerators {
  static Future<Uint8List> ticket(
    Ticket ticket, {
    List<TicketComment> comments = const [],
    bool includeInternalNotes = false,
  }) async {
    final b = HmsPdfBuilder();
    final ref = ticket.ticketNumber != null ? 'AVVIK-${ticket.ticketNumber}' : ticket.id.substring(0, 8);

    b.drawDocumentHeader(
      documentType: 'Avvik / HMS-rapport',
      title: ticket.title,
      subtitle: ticket.description,
      reference: ref,
      documentDate: ticket.createdAt,
    );

    b.section('Klassifisering');
    b.keyValueGrid([
      ('Status', ticket.status.label),
      ('Alvorlighet', ticket.severity.label),
      ('Kategori', ticket.category ?? '—'),
      ('HMS-område', ticket.hmsDomain.label),
      ('Avdeling', ticket.departmentName ?? '—'),
      ('Frist', ticket.dueDate != null ? DateFormat('dd.MM.yyyy').format(ticket.dueDate!) : '—'),
    ]);

    b.section('Personer');
    b.keyValueGrid([
      ('Meldt av', ticket.isAnonymous ? 'Anonym' : (ticket.reporterName ?? '—')),
      ('Saksbehandler', ticket.assigneeName ?? '—'),
      ('Løst av', ticket.resolvedByName ?? '—'),
      ('Løst dato', ticket.resolvedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(ticket.resolvedAt!) : '—'),
    ]);

    if (ticket.gpsAddress != null ||
        ticket.locationDescription != null ||
        ticket.gpsLatitude != null) {
      b.section('Sted og observasjon');
      b.field('Adresse', ticket.gpsAddress);
      b.field('Stedsbeskrivelse', ticket.locationDescription);
      if (ticket.gpsLatitude != null && ticket.gpsLongitude != null) {
        b.field('GPS', '${ticket.gpsLatitude!.toStringAsFixed(5)}, ${ticket.gpsLongitude!.toStringAsFixed(5)}');
      }
      if (ticket.observedAt != null) {
        b.field('Observert', DateFormat('dd.MM.yyyy HH:mm').format(ticket.observedAt!));
      }
      if (ticket.hasPersonalInjury) {
        b.field('Personskade', 'Ja — registrert');
      }
    }

    b.section('Årsak og tiltak');
    b.field('Rotårsak', ticket.rootCause);
    b.field('Utførte tiltak', ticket.completedMeasures);
    b.field('Løsningskommentar', ticket.resolutionComment);
    b.field('Eskaleringsgrunn', ticket.escalationReason);

    if (ticket.actionPlan.isNotEmpty) {
      b.section('Tiltaksplan');
      for (var i = 0; i < ticket.actionPlan.length; i++) {
        final a = ticket.actionPlan[i];
        final desc = a['description'] ?? a['title'] ?? a.toString();
        final status = a['status'] ?? a['done'];
        b.bullets(['${i + 1}. $desc${status != null ? ' [$status]' : ''}']);
      }
    }

    if (includeInternalNotes && (ticket.internalNotes ?? '').trim().isNotEmpty) {
      b.section('Interne notater (kun ledelse)');
      b.paragraph(ticket.internalNotes);
    }

    if (comments.isNotEmpty) {
      b.section('Kommentarer og historikk');
      for (final c in comments) {
        final when = c.createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(c.createdAt!) : '';
        final who = c.userName ?? 'Bruker';
        if (c.isStatusChange && c.newStatus != null) {
          b.paragraph('[$when] $who endret status til ${c.newStatus!.label}');
        }
        if (c.comment.trim().isNotEmpty) {
          b.paragraph('[$when] $who: ${c.comment.trim()}');
        }
      }
    }

    if (ticket.imageUrls.isNotEmpty || ticket.videoUrls.isNotEmpty) {
      b.section('Vedlegg');
      b.field('Bilder', '${ticket.imageUrls.length} vedlagt');
      if (ticket.annotatedImageUrls.isNotEmpty) {
        b.field('Annoterte bilder', '${ticket.annotatedImageUrls.length} vedlagt');
      }
      if (ticket.videoUrls.isNotEmpty) {
        b.field('Video', '${ticket.videoUrls.length} vedlagt');
      }
    }

    return b.build();
  }

  static Future<Uint8List> riskAssessment(RiskAssessment ra) async {
    final b = HmsPdfBuilder();
    final score = ra.riskScore ?? (ra.probability * ra.consequence);
    final residual = ra.residualProbability * ra.residualConsequence;

    b.drawDocumentHeader(
      documentType: 'Risikovurdering (ROS)',
      title: ra.title,
      subtitle: ra.description,
      reference: 'ROS-${ra.id.substring(0, 8).toUpperCase()}',
      documentDate: ra.createdAt,
    );

    b.section('Identifikasjon');
    b.keyValueGrid([
      ('Status', ra.status),
      ('Område / prosess', ra.area ?? ra.activityProcess ?? '—'),
      ('Sted', ra.locationDetail ?? '—'),
      ('Scenario', ra.scenarioCategory ?? '—'),
      ('Ansvarlig', ra.responsiblePersonName ?? ra.responsiblePerson ?? '—'),
      ('Opprettet av', ra.creatorName ?? '—'),
      ('Frist', ra.deadline != null ? DateFormat('dd.MM.yyyy').format(ra.deadline!) : '—'),
      ('Revisjonsdato', ra.reviewDate != null ? DateFormat('dd.MM.yyyy').format(ra.reviewDate!) : '—'),
    ]);

    b.section('Fare og konsekvens');
    b.field('Farekilde', ra.hazardSource);
    b.field('Berørte personer', ra.affectedPersons);
    b.field('Juridisk referanse', ra.legalReference);
    b.field('ISO / standard', ra.isoStandard);
    b.field('Evalueringsmetode', ra.evaluationMethod);

    b.section('Risikomatrise');
    b.keyValueGrid([
      ('Innledende sannsynlighet', '${ra.initialProbability}'),
      ('Innledende konsekvens', '${ra.initialConsequence}'),
      ('Innledende risiko', '${ra.initialProbability * ra.initialConsequence}'),
      ('Nåværende sannsynlighet', '${ra.probability}'),
      ('Nåværende konsekvens', '${ra.consequence}'),
      ('Nåværende risikoscore', '$score'),
      ('Rest risiko (S)', '${ra.residualProbability}'),
      ('Rest risiko (K)', '${ra.residualConsequence}'),
      ('Rest risikoscore', '$residual'),
    ]);

    b.section('Tiltak');
    b.field('Eksisterende tiltak', ra.existingMeasures);
    b.field('Foreslåtte tiltak', ra.proposedMeasures);
    b.field('Resttiltak', ra.residualMeasures);

    b.section('Behandling');
    b.field('Rotårsak', ra.rootCause);
    b.field('Behandlingsnotater', ra.treatmentNotes);
    b.field('Revisjonsnotater', ra.reviewNotes);
    if (ra.treatedAt != null) {
      b.field('Behandlet', DateFormat('dd.MM.yyyy HH:mm').format(ra.treatedAt!));
    }

    if (ra.documentUrls.isNotEmpty || ra.imageUrls.isNotEmpty) {
      b.section('Vedlegg');
      b.field('Dokumenter', '${ra.documentUrls.length} fil(er)');
      b.field('Bilder', '${ra.imageUrls.length} bilde(r)');
    }

    return b.build();
  }

  static Future<Uint8List> stakeholderRisk(StakeholderRiskAssessment assessment) async {
    final b = HmsPdfBuilder();
    final content = assessment.content;

    b.drawDocumentHeader(
      documentType: 'Interessepart og risikovurdering',
      title: assessment.title,
      subtitle: content.sourceFile.isNotEmpty ? content.sourceFile : null,
      reference: 'IP-${assessment.id.substring(0, 8).toUpperCase()}',
      documentDate: assessment.createdAt,
    );

    b.section('Oversikt');
    b.keyValueGrid([
      ('Status', assessment.status),
      ('År', '${assessment.assessmentYear ?? '—'}'),
      ('Seksjoner', '${content.sections.length}'),
      ('Oppdatert', assessment.updatedAt != null ? DateFormat('dd.MM.yyyy').format(assessment.updatedAt!) : '—'),
    ]);

    for (final section in content.sections) {
      b.section(section.title);
      if (section.documentTitle.trim().isNotEmpty) {
        b.paragraph(section.documentTitle);
      }

      final headers = section.columnKeys
          .map((k) => section.columnLabels[k] ?? k)
          .where((h) => h.trim().isNotEmpty)
          .toList();
      final keys = section.columnKeys.where((k) {
        final label = section.columnLabels[k] ?? k;
        return label.trim().isNotEmpty;
      }).toList();

      void addRows(Iterable<StakeholderRiskRow> rows, {String? groupTitle}) {
        if (groupTitle != null && groupTitle.trim().isNotEmpty) {
          b.paragraph(groupTitle);
        }
        final tableRows = <List<String>>[];
        for (final row in rows) {
          tableRows.add(keys.map((k) => row.cells[k]?.trim() ?? '').toList());
        }
        if (tableRows.isNotEmpty && headers.isNotEmpty) {
          b.table(
            headers: headers,
            rows: tableRows,
            landscapeIfWide: PdfPageOrientation.landscape,
          );
        }
      }

      for (final group in section.groups) {
        addRows(group.rows, groupTitle: group.title);
      }
      if (section.rows.isNotEmpty) {
        addRows(section.rows);
      }
    }

    return b.build();
  }

  static Future<Uint8List> sja(
    SjaForm form, {
    List<HmsSjaStep> steps = const [],
    List<HmsSjaSignature> signatures = const [],
  }) async {
    final b = HmsPdfBuilder();

    b.drawDocumentHeader(
      documentType: 'Sikker Jobb Analyse (SJA)',
      title: form.title,
      subtitle: form.workDescription,
      reference: 'SJA-${form.id.substring(0, 8).toUpperCase()}',
      documentDate: form.plannedDate,
    );

    b.section('Planlegging');
    b.keyValueGrid([
      ('Status', form.status.label),
      ('Sted', form.location ?? '—'),
      ('Planlagt dato', DateFormat('dd.MM.yyyy').format(form.plannedDate)),
      ('Påkrevde signaturer', '${form.requiredSignatures}'),
      ('Ansvarlig', form.responsiblePersonName ?? form.responsiblePerson ?? '—'),
      ('Godkjent av', form.approvedBy ?? '—'),
    ]);

    if (form.requiredPpe.isNotEmpty) {
      b.section('Verneutstyr (PPE)');
      b.bullets(form.requiredPpe);
    }

    if (steps.isNotEmpty) {
      b.section('Arbeidssteg');
      b.table(
        headers: const ['#', 'Operasjon', 'Fare', 'Tiltak', 'S', 'K'],
        rows: steps
            .map(
              (s) => [
                '${s.stepOrder}',
                s.operation,
                s.hazard,
                s.measure,
                s.probability?.toString() ?? '',
                s.consequence?.toString() ?? '',
              ],
            )
            .toList(),
      );
    } else if (form.hazards.isNotEmpty || form.measures.isNotEmpty) {
      b.section('Farer og tiltak');
      for (var i = 0; i < form.hazards.length; i++) {
        final h = form.hazards[i];
        b.paragraph('Fare ${i + 1}: ${h['description'] ?? h['hazard'] ?? h}');
      }
      for (var i = 0; i < form.measures.length; i++) {
        final m = form.measures[i];
        b.paragraph('Tiltak ${i + 1}: ${m['description'] ?? m['measure'] ?? m}');
      }
    }

    if (signatures.isNotEmpty) {
      b.section('Signaturer');
      b.table(
        headers: const ['Navn', 'Tidspunkt', 'Metode'],
        rows: signatures
            .map(
              (s) => [
                s.profileName ?? s.profileId.substring(0, 8),
                DateFormat('dd.MM.yyyy HH:mm').format(s.signedAt.toLocal()),
                s.method,
              ],
            )
            .toList(),
      );
    }

    return b.build();
  }

  static Future<Uint8List> equipment(
    Equipment item, {
    List<EquipmentMaintenanceLog> logs = const [],
    List<EquipmentPurchase> purchases = const [],
  }) async {
    final b = HmsPdfBuilder();

    b.drawDocumentHeader(
      documentType: 'Utstyr / maskin',
      title: item.name,
      subtitle: item.description,
      reference: item.serialNumber ?? item.id.substring(0, 8),
      documentDate: item.createdAt,
    );

    b.section('Registrering');
    b.keyValueGrid([
      ('Kategori', item.category.label),
      ('Status', item.status.label),
      ('Serienr.', item.serialNumber ?? '—'),
      ('Merke / modell', '${item.brand ?? ''} ${item.model ?? ''}'.trim().isEmpty ? '—' : '${item.brand ?? ''} ${item.model ?? ''}'.trim()),
      ('Lokasjon', item.location ?? '—'),
      ('Ansvarlig', item.responsibleName ?? item.assignedName ?? '—'),
    ]);

    if (logs.isNotEmpty) {
      b.section('Service og vedlikehold');
      b.table(
        headers: const ['Dato', 'Type', 'Notat'],
        rows: logs
            .take(40)
            .map(
              (l) => [
                DateFormat('dd.MM.yyyy').format(l.performedAt),
                l.type.label,
                l.notes ?? '',
              ],
            )
            .toList(),
      );
    }

    if (purchases.isNotEmpty) {
      b.section('Innkjøp');
      b.table(
        headers: const ['Dato', 'Leverandør', 'Beløp', 'Notat'],
        rows: purchases
            .take(20)
            .map(
              (p) => [
                DateFormat('dd.MM.yyyy').format(p.purchasedAt),
                p.supplier ?? '',
                p.amount != null ? '${p.amount!.toStringAsFixed(0)} kr' : '',
                p.notes ?? '',
              ],
            )
            .toList(),
      );
    }

    return b.build();
  }

  static Future<Uint8List> safetyRound(SafetyRound round) =>
      SafetyRoundPdfGenerator.generate(round);
}
