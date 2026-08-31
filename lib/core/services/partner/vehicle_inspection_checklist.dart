import '../../../models/partner/vehicle_inspection.dart';

enum VehicleChecklistRowKind { ok, avvik, warning, note, empty }

class VehicleInspectionChecklistRow {
  final String key;
  final String label;
  final String displayValue;
  final String statusLabel;
  final VehicleChecklistRowKind kind;

  const VehicleInspectionChecklistRow({
    required this.key,
    required this.label,
    required this.displayValue,
    required this.statusLabel,
    required this.kind,
  });

  bool get isAvvik => kind == VehicleChecklistRowKind.avvik;
}

class VehicleInspectionChecklistSummary {
  final List<VehicleInspectionChecklistRow> rows;
  final int okCount;
  final int avvikCount;
  final int notCheckedCount;

  const VehicleInspectionChecklistSummary({
    required this.rows,
    required this.okCount,
    required this.avvikCount,
    required this.notCheckedCount,
  });

  List<VehicleInspectionChecklistRow> get okItems =>
      rows.where((r) => r.kind == VehicleChecklistRowKind.ok).toList();

  List<VehicleInspectionChecklistRow> get avvikItems =>
      rows.where((r) => r.isAvvik).toList();

  List<VehicleInspectionChecklistRow> get otherItems => rows
      .where((r) =>
          r.kind != VehicleChecklistRowKind.ok &&
          r.kind != VehicleChecklistRowKind.avvik)
      .toList();

  factory VehicleInspectionChecklistSummary.fromInspection(
    PartnerVehicleInspection inspection,
  ) {
    var ok = 0;
    var avvik = 0;
    var notChecked = 0;
    final parsed = <VehicleInspectionChecklistRow>[];

    for (final field in VehicleInspectionTemplate.items) {
      final raw = inspection.checklist[field.key];
      final text = raw == null ? '' : '$raw'.trim();
      if (text.isEmpty && field.type != InspectionFieldType.text) {
        parsed.add(VehicleInspectionChecklistRow(
          key: field.key,
          label: field.label,
          displayValue: '—',
          statusLabel: 'Ikke utfylt',
          kind: VehicleChecklistRowKind.empty,
        ));
        continue;
      }

      switch (field.type) {
        case InspectionFieldType.okAvvik:
          switch (text) {
            case 'ok':
              ok++;
              parsed.add(VehicleInspectionChecklistRow(
                key: field.key,
                label: field.label,
                displayValue: 'OK',
                statusLabel: 'OK',
                kind: VehicleChecklistRowKind.ok,
              ));
            case 'avvik':
              avvik++;
              parsed.add(VehicleInspectionChecklistRow(
                key: field.key,
                label: field.label,
                displayValue: 'Avvik',
                statusLabel: 'Avvik',
                kind: VehicleChecklistRowKind.avvik,
              ));
            case 'not_checked':
              notChecked++;
              parsed.add(VehicleInspectionChecklistRow(
                key: field.key,
                label: field.label,
                displayValue: 'Kan ikke sjekkes',
                statusLabel: 'Ukjent',
                kind: VehicleChecklistRowKind.warning,
              ));
            default:
              parsed.add(VehicleInspectionChecklistRow(
                key: field.key,
                label: field.label,
                displayValue: text,
                statusLabel: text,
                kind: VehicleChecklistRowKind.note,
              ));
          }
        case InspectionFieldType.number:
          final mm = double.tryParse(text.replaceAll(',', '.'));
          final display = text.contains('mm') ? text : '$text mm';
          if (mm != null && mm < 3.0) {
            avvik++;
            parsed.add(VehicleInspectionChecklistRow(
              key: field.key,
              label: field.label,
              displayValue: display,
              statusLabel: 'Avvik (< 3 mm)',
              kind: VehicleChecklistRowKind.avvik,
            ));
          } else if (mm != null) {
            ok++;
            parsed.add(VehicleInspectionChecklistRow(
              key: field.key,
              label: field.label,
              displayValue: display,
              statusLabel: 'OK',
              kind: VehicleChecklistRowKind.ok,
            ));
          } else {
            parsed.add(VehicleInspectionChecklistRow(
              key: field.key,
              label: field.label,
              displayValue: display,
              statusLabel: 'Notert',
              kind: VehicleChecklistRowKind.note,
            ));
          }
        case InspectionFieldType.text:
          if (text.isEmpty) continue;
          parsed.add(VehicleInspectionChecklistRow(
            key: field.key,
            label: field.label,
            displayValue: text,
            statusLabel: 'Kommentar',
            kind: VehicleChecklistRowKind.note,
          ));
      }
    }

    return VehicleInspectionChecklistSummary(
      rows: parsed,
      okCount: ok,
      avvikCount: avvik,
      notCheckedCount: notChecked,
    );
  }
}
