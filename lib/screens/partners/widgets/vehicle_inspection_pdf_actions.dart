import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/vehicle_inspection_pdf.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'partner_route_pdf_actions.dart';

/// Åpne bilkontroll-PDF (lagret arkiv først, deretter regenerering).
abstract final class VehicleInspectionPdfActions {
  static Future<void> openPdf(
    BuildContext context, {
    required PartnerVehicleInspection inspection,
    Partner? partner,
  }) async {
    final title = 'Bilkontroll — ${inspection.vehicleLabel}';
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Henter PDF…'),
          ],
        ),
        duration: Duration(seconds: 45),
      ),
    );

    try {
      final bytes = await loadPdfBytes(
        inspection: inspection,
        partner: partner,
      );
      messenger?.hideCurrentSnackBar();
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _snack(context, 'Kunne ikke hente PDF for bilkontrollen.', isError: true);
        return;
      }
      await PartnerRoutePdfActions.openPdfBytes(
        context,
        bytes: bytes,
        title: title,
      );
    } catch (e) {
      messenger?.hideCurrentSnackBar();
      if (context.mounted) {
        _snack(context, 'Kunne ikke åpne PDF: $e', isError: true);
      }
    }
  }

  static Future<Uint8List?> loadPdfBytes({
    required PartnerVehicleInspection inspection,
    Partner? partner,
  }) async {
    final stored = inspection.pdfStoragePath?.trim();
    if (stored != null && stored.isNotEmpty) {
      final archived = await PartnerService.downloadInspectionPdfBytes(
        stored,
        companyId: inspection.companyId,
      );
      if (archived != null && archived.isNotEmpty) return archived;
    }

    if (partner == null) return null;

    final photoBytes = <Uint8List>[];
    for (final path in inspection.photoPaths) {
      final bytes = await PartnerService.downloadInspectionPdfBytes(
        path,
        companyId: inspection.companyId,
      );
      if (bytes != null && bytes.isNotEmpty) photoBytes.add(bytes);
    }

    return VehicleInspectionPdf.generate(
      inspection: inspection,
      partner: partner,
      inspectorName: inspection.inspectedByName,
      photoBytes: photoBytes,
    );
  }

  static void _snack(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }
}
