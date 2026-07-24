import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../models/partner/partner.dart';
import '../../../models/partner/vehicle_inspection.dart';
import '../hms/hms_pdf_builder.dart';

/// Profesjonell PDF-rapport for bilkontroll (alle samarbeidspartnere).
abstract final class VehicleInspectionPdf {
  static final _df = DateFormat('dd.MM.yyyy');
  static final _dtf = DateFormat('dd.MM.yyyy HH:mm');
  static final _fileStamp = DateFormat('yyyyMMdd_HHmm');

  static String fileNameFor(PartnerVehicleInspection inspection) {
    final vehicle = _vehicleLabel(inspection)
        .replaceAll(RegExp(r'[^A-Za-z0-9ÆØÅæøå\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final stamp = _fileStamp.format(inspection.inspectedAt.toLocal());
    final safe = vehicle.isEmpty ? 'bil' : vehicle;
    return 'Bilkontroll_${safe}_$stamp';
  }

  static Future<Uint8List> generate({
    required PartnerVehicleInspection inspection,
    required Partner partner,
    String? inspectorName,
    List<Uint8List> photoBytes = const [],
  }) async {
    final inspectedLocal = inspection.inspectedAt.toLocal();
    final b = HmsPdfBuilder()
      ..brandHeader = 'MAVI LOGISTIKK AS'
      ..footerLeft = 'MAVI Logistikk AS · DriftPro bilkontroll · konfidensielt';

    final vehicle = _vehicleLabel(inspection);
    final partnerName = _partnerDisplayName(partner);
    final status = inspection.hasDeviation ? 'AVVIK REGISTRERT' : 'OK — INGEN AVVIK';
    final who = (inspectorName ?? inspection.inspectedByName)?.trim();
    final ref = inspection.id.isNotEmpty && inspection.id.length >= 8
        ? 'BK-${inspection.id.substring(0, 8).toUpperCase()}'
        : 'BK-${_fileStamp.format(inspectedLocal)}';

    b.drawDocumentHeader(
      documentType: 'Bilkontrollrapport',
      title: vehicle.isEmpty ? 'Bilkontroll' : 'Bilkontroll — $vehicle',
      subtitle: partnerName,
      reference: ref,
      documentDate: inspection.inspectedAt,
    );

    final summary = _summaryCounts(inspection);
    if (inspection.hasDeviation || summary.avvik > 0) {
      b.statusBanner(
        title: 'Avvik registrert',
        detail: summary.avvik > 0
            ? '${summary.avvik} punkt med avvik'
                '${(inspection.deviationNotes ?? '').trim().isNotEmpty ? ' · se kommentar nedenfor' : ''}'
            : 'Avvik er flagget på denne kontrollen',
        isAlert: true,
      );
    } else {
      b.statusBanner(
        title: 'OK — ingen avvik',
        detail: 'Alle sjekkede punkter er innenfor krav',
        isAlert: false,
      );
    }

    b.section('Oppsummering');
    b.keyValueGrid([
      ('Bedrift', partnerName),
      (
        'Registreringsnummer',
        (inspection.registrationNumber ?? '').trim().isEmpty
            ? '—'
            : inspection.registrationNumber!.trim(),
      ),
      (
        'MAVI-nummer',
        (inspection.unitCode ?? '').trim().isEmpty
            ? '—'
            : inspection.unitCode!.trim(),
      ),
      ('Kontrolldato', _dtf.format(inspectedLocal)),
      ('Kontrollør', (who == null || who.isEmpty) ? 'Ukjent' : who),
      ('Resultat', status),
    ]);

    b.section('Kjøretøy og bedrift');
    b.keyValueGrid([
      ('Bedrift', partnerName),
      if ((partner.orgNumber ?? '').trim().isNotEmpty)
        ('Org.nr', partner.orgNumber!.trim()),
      if ((partner.ownerName ?? '').trim().isNotEmpty)
        ('Bedriftsansvarlig', partner.ownerName!.trim()),
      (
        'Reg.nr',
        (inspection.registrationNumber ?? '').trim().isEmpty
            ? '—'
            : inspection.registrationNumber!.trim(),
      ),
      (
        'MAVI-kode',
        (inspection.unitCode ?? '').trim().isEmpty
            ? '—'
            : inspection.unitCode!.trim(),
      ),
    ]);

    b.section('Kontrollstempling');
    b.keyValueGrid([
      ('Utført', _dtf.format(inspectedLocal)),
      ('Kontrollør', (who == null || who.isEmpty) ? 'Ukjent' : who),
      ('Referanse', ref),
      if (inspection.nextInspectionAt != null)
        ('Neste kontroll', _df.format(inspection.nextInspectionAt!)),
      if (inspection.followUpDueAt != null)
        ('Oppfølgingsfrist', _df.format(inspection.followUpDueAt!)),
      if (inspection.followUpAcknowledgedAt != null)
        (
          'Oppfølging lukket',
          _dtf.format(inspection.followUpAcknowledgedAt!.toLocal()),
        ),
    ]);

    b.section('Sjekkliste — avkryssing');
    final rows = <List<String>>[];
    final rowMarks = <String?>[];
    for (final field in VehicleInspectionTemplate.items) {
      final raw = inspection.checklist[field.key];
      final mark = _rowMark(field, raw);
      final result = _resultLabel(field, raw);
      rows.add([
        mark == 'alert' ? '● ${field.label}' : field.label,
        _formatChecklistValue(field, raw),
        mark == 'alert' ? '⚠ $result' : result,
      ]);
      rowMarks.add(mark);
    }
    b.table(
      headers: const ['Kontrollpunkt', 'Registrert', 'Status'],
      rows: rows,
      rowMarks: rowMarks,
    );

    b.section('Telling');
    b.keyValueGrid([
      ('OK', '${summary.ok}'),
      ('Avvik', '${summary.avvik}'),
      ('Kan ikke sjekkes', '${summary.notChecked}'),
      ('Utfylte tall/tekst', '${summary.filled}'),
    ]);

    if (inspection.hasDeviation ||
        (inspection.deviationNotes ?? '').trim().isNotEmpty ||
        summary.avvik > 0) {
      b.section('Avvik og kommentarer');
      b.statusBanner(
        title: summary.avvik > 0
            ? '${summary.avvik} avvikspunkt markert i rødt i sjekklisten'
            : 'Avvik registrert',
        detail: (inspection.deviationNotes ?? '').trim().isNotEmpty
            ? null
            : 'Se sjekkliste for detaljer',
        isAlert: true,
      );
      b.field(
        'Avvik registrert',
        (inspection.hasDeviation || summary.avvik > 0) ? 'Ja' : 'Nei',
      );
      b.field('Beskrivelse / kommentar', inspection.deviationNotes ?? '—');
      if (inspection.followUpDueAt != null) {
        b.field(
          'Oppfølging innen',
          _df.format(inspection.followUpDueAt!),
        );
      }
      if (inspection.followUpOpen) {
        b.paragraph(
          inspection.followUpOverdue
              ? 'Oppfølging er åpen og forfalt.'
              : 'Oppfølging er åpen.',
        );
      } else if (inspection.followUpAcknowledgedAt != null) {
        b.paragraph(
          'Oppfølging markert som utført '
          '${_dtf.format(inspection.followUpAcknowledgedAt!.toLocal())}.',
        );
      }
    }

    if (photoBytes.isNotEmpty || inspection.photoPaths.isNotEmpty) {
      b.section('Vedlegg — bilder');
      b.paragraph(
        '${photoBytes.isNotEmpty ? photoBytes.length : inspection.photoPaths.length} '
        'bilde(r) dokumenterer tilstand ved kontroll.',
      );
      if (photoBytes.isNotEmpty) {
        b.photoGrid(photoBytes);
      }
    }

    b.section('Bekreftelse og stempel');
    b.paragraph(
      'Denne rapporten dokumenterer utført bilkontroll for '
      '$partnerName'
      '${vehicle.isEmpty ? '' : ' · $vehicle'}. '
      'Rapporten er arkivert i DriftPro og stemplet av MAVI Logistikk AS.',
    );
    b.paragraph(
      who != null && who.isNotEmpty
          ? 'Kontroll stempling · $who · ${_dtf.format(inspectedLocal)}'
          : inspection.stampLine,
    );
    b.paragraph(
      'MAVI Logistikk AS · ${_df.format(inspectedLocal)} · $ref',
    );

    return b.build();
  }

  static String _partnerDisplayName(Partner partner) {
    final trade = (partner.tradeName ?? '').trim();
    if (trade.isNotEmpty) return trade;
    final name = partner.name.trim();
    return name.isEmpty ? 'Samarbeidspartner' : name;
  }

  static String _vehicleLabel(PartnerVehicleInspection inspection) {
    final reg = (inspection.registrationNumber ?? '').trim();
    final unit = (inspection.unitCode ?? '').trim();
    if (reg.isNotEmpty && unit.isNotEmpty) return '$reg · $unit';
    if (reg.isNotEmpty) return reg;
    if (unit.isNotEmpty) return unit;
    return '';
  }

  static String _formatChecklistValue(
    VehicleInspectionField field,
    dynamic raw,
  ) {
    if (raw == null) return '—';
    final text = '$raw'.trim();
    if (text.isEmpty) return '—';
    switch (field.type) {
      case InspectionFieldType.okAvvik:
        return _okAvvikLabel(text);
      case InspectionFieldType.number:
        return text.contains('mm') ? text : '$text mm';
      case InspectionFieldType.text:
        return text;
    }
  }

  static String _resultLabel(VehicleInspectionField field, dynamic raw) {
    if (raw == null) return '—';
    final text = '$raw'.trim();
    if (text.isEmpty) return '—';
    switch (field.type) {
      case InspectionFieldType.okAvvik:
        return _okAvvikLabel(text);
      case InspectionFieldType.number:
        final mm = double.tryParse(text.replaceAll(',', '.'));
        if (mm == null) return '—';
        if (mm < 3.0) return 'AVVIK (< 3,0 mm)';
        return 'OK';
      case InspectionFieldType.text:
        return 'Notert';
    }
  }

  /// `alert` = rød avviksrad, `warn` = gul (kan ikke sjekkes), ellers null.
  static String? _rowMark(VehicleInspectionField field, dynamic raw) {
    if (raw == null) return null;
    final text = '$raw'.trim();
    if (text.isEmpty) return null;
    switch (field.type) {
      case InspectionFieldType.okAvvik:
        if (text == 'avvik') return 'alert';
        if (text == 'not_checked') return 'warn';
        return null;
      case InspectionFieldType.number:
        final mm = double.tryParse(text.replaceAll(',', '.'));
        if (mm != null && mm < 3.0) return 'alert';
        return null;
      case InspectionFieldType.text:
        return null;
    }
  }

  static String _okAvvikLabel(String raw) {
    switch (raw) {
      case 'ok':
        return 'OK';
      case 'avvik':
        return 'AVVIK';
      case 'not_checked':
        return 'Kan ikke sjekkes';
      default:
        return raw;
    }
  }

  static ({int ok, int avvik, int notChecked, int filled}) _summaryCounts(
    PartnerVehicleInspection inspection,
  ) {
    var ok = 0;
    var avvik = 0;
    var notChecked = 0;
    var filled = 0;
    for (final field in VehicleInspectionTemplate.items) {
      final raw = inspection.checklist[field.key];
      final text = raw == null ? '' : '$raw'.trim();
      switch (field.type) {
        case InspectionFieldType.okAvvik:
          switch (text) {
            case 'ok':
              ok++;
            case 'avvik':
              avvik++;
            case 'not_checked':
              notChecked++;
          }
        case InspectionFieldType.number:
          if (text.isEmpty) break;
          filled++;
          final mm = double.tryParse(text.replaceAll(',', '.'));
          if (mm != null && mm < 3.0) {
            avvik++;
          } else if (mm != null) {
            ok++;
          }
        case InspectionFieldType.text:
          if (text.isNotEmpty) filled++;
      }
    }
    return (ok: ok, avvik: avvik, notChecked: notChecked, filled: filled);
  }
}
