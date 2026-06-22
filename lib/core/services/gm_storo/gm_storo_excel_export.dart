import 'dart:typed_data';

import '../../../models/gm_storo_scan.dart';
import '../dms/dms_file_editor_service.dart';

/// Excel-eksport for GM & STORO innsendinger.
class GmStoroExcelExport {
  static Uint8List exportScans(List<GmStoroScanRecord> scans) {
    final rows = <List<String>>[
      [
        'Skannet',
        'Skanner',
        'Destinasjon',
        'SSCC / Kolli',
        'Package',
        'Shipment',
        'Consignee',
        'Mottaker',
        'Adresse',
        'Postnr/sted',
        'Vekt',
        'Ready date',
        'Ready time',
        'Article EG',
        'Article NDC',
        'Area',
        'Enhet',
        'Avsender',
        'Dobbel',
        'Strekkode rå',
      ],
    ];

    for (final s in scans) {
      final d = s.data;
      rows.add([
        s.scannedAt.toIso8601String(),
        s.scannerName ?? '',
        d.destinationLabel,
        d.sscc ?? '',
        d.packageId ?? '',
        d.shipmentId ?? '',
        d.consignee ?? '',
        d.recipientName ?? '',
        d.recipientAddress ?? '',
        d.recipientPostal ?? '',
        d.weightKg ?? '',
        d.readyDate ?? '',
        d.readyTime ?? '',
        d.articleEg ?? '',
        d.articleNdc ?? '',
        d.areaCode ?? '',
        d.unitType ?? '',
        d.senderName ?? '',
        s.isDuplicate ? 'JA' : 'NEI',
        d.barcodeRaw ?? '',
      ]);
    }

    return DmsFileEditorService.encodeXlsx({'GM_STORO': rows});
  }

  static Uint8List exportBatches(List<GmStoroBatch> batches) {
    final summaryRows = <List<String>>[
      ['Innsendt', 'Skanner', 'Antall', 'Status', 'Batch ID'],
    ];
    final detailRows = <List<String>>[
      [
        'Batch',
        'Skannet',
        'SSCC',
        'Package',
        'Shipment',
        'Consignee',
        'Mottaker',
        'Vekt',
        'Destinasjon',
      ],
    ];

    for (final b in batches) {
      summaryRows.add([
        (b.submittedAt ?? b.createdAt).toIso8601String(),
        b.scannerName ?? b.createdBy,
        '${b.labelCount}',
        b.status,
        b.id,
      ]);
      for (final s in b.scans) {
        detailRows.add([
          b.id,
          s.scannedAt.toIso8601String(),
          s.data.sscc ?? '',
          s.data.packageId ?? '',
          s.data.shipmentId ?? '',
          s.data.consignee ?? '',
          s.data.recipientName ?? '',
          s.data.weightKg ?? '',
          s.data.destinationLabel,
        ]);
      }
    }

    return DmsFileEditorService.encodeXlsx({
      'Oversikt': summaryRows,
      'Alle etiketter': detailRows,
    });
  }
}
