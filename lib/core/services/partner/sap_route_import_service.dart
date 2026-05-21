import '../../../models/partner/partner_links.dart';
import '../../../models/partner/sap_route_inbox.dart';
import 'mavi_unit_codes.dart';
import 'partner_service.dart';
import 'route_pdf_text_service.dart';

/// Importerer ventende SAP-PDF-er til staged ruter (samme logikk som AUTO MASS).
class SapRouteImportService {
  SapRouteImportService._();

  static Future<SapRouteImportResult> importPendingToStaged({
    required String companyId,
    required DateTime routeDate,
    required List<FleetPartnerVehicleRow> fleet,
    List<String>? inboxIds,
  }) async {
    final pending = await PartnerService.fetchSapRouteInboxPending(companyId);
    final targets = inboxIds == null
        ? pending
        : pending.where((p) => inboxIds.contains(p.id)).toList();

    if (targets.isEmpty) {
      return const SapRouteImportResult(imported: 0, skipped: 0, lines: []);
    }

    final vehicleMap = await _loadVehicleLookup(companyId, fleet);
    final partnerById = {for (final r in fleet) r.partner.id: r.partner};
    for (final p in await PartnerService.fetchPartners(companyId: companyId)) {
      partnerById.putIfAbsent(p.id, () => p);
    }

    final day = DateTime(routeDate.year, routeDate.month, routeDate.day);
    final lines = <SapRouteImportLine>[];
    var imported = 0;
    var skipped = 0;

    for (final item in targets) {
      try {
        final bytes = await PartnerService.downloadRoutePdfBytes(item.pdfStoragePath);
        if (bytes == null || bytes.isEmpty) {
          await PartnerService.markSapRouteInboxRejected(
            id: item.id,
            reason: 'Kunne ikke lese PDF',
          );
          skipped++;
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: false,
            message: 'Kunne ikke lese PDF',
          ));
          continue;
        }

        final meta = RoutePdfTextService.extractTripOverviewMeta(bytes);
        final code = meta.maviCode ?? RoutePdfTextService.extractResourceIdFromBytes(bytes);
        if (code == null) {
          await PartnerService.markSapRouteInboxRejected(
            id: item.id,
            reason: 'Fant ikke MAVI i PDF',
          );
          skipped++;
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: false,
            message: 'Fant ikke MAVI-nummer i PDF',
          ));
          continue;
        }

        final vehicle = RoutePdfTextService.findVehicleInLookup(vehicleMap, code);
        if (vehicle == null) {
          await PartnerService.markSapRouteInboxRejected(
            id: item.id,
            reason: 'Ingen bil for $code',
          );
          skipped++;
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: false,
            maviCode: code,
            message: 'Ingen bil matcher $code',
          ));
          continue;
        }

        final partner = partnerById[vehicle.partnerId];
        if (partner == null) {
          await PartnerService.markSapRouteInboxRejected(
            id: item.id,
            reason: 'Partner mangler',
          );
          skipped++;
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: false,
            maviCode: code,
            message: 'Partner mangler',
          ));
          continue;
        }

        final shareId = await PartnerService.createStagedRouteShareFromPdf(
          companyId: companyId,
          partner: partner,
          vehicle: vehicle,
          fileName: item.fileName,
          bytes: bytes,
          routeDate: day,
        );

        await PartnerService.markSapRouteInboxImported(
          inboxId: item.id,
          routeShareId: shareId,
          detectedMaviCode: MaviUnitCodes.normalize(vehicle.unitCode),
        );

        imported++;
        lines.add(SapRouteImportLine(
          fileName: item.fileName,
          ok: true,
          maviCode: MaviUnitCodes.normalize(vehicle.unitCode),
        ));
      } catch (e) {
        await PartnerService.markSapRouteInboxRejected(
          id: item.id,
          reason: e.toString(),
        );
        skipped++;
        lines.add(SapRouteImportLine(
          fileName: item.fileName,
          ok: false,
          message: e.toString(),
        ));
      }
    }

    return SapRouteImportResult(
      imported: imported,
      skipped: skipped,
      lines: lines,
    );
  }

  static Future<Map<String, PartnerVehicle>> _loadVehicleLookup(
    String companyId,
    List<FleetPartnerVehicleRow> fleet,
  ) async {
    final vehicles = <PartnerVehicle>[];
    for (final r in fleet) {
      vehicles.add(r.vehicle);
    }
    for (final p in await PartnerService.fetchPartners(companyId: companyId)) {
      vehicles.addAll(await PartnerService.fetchVehicles(p.id));
    }
    return RoutePdfTextService.buildVehicleLookupMap<PartnerVehicle>(
      vehicles: vehicles.where(PartnerService.isMaviFleetVehicle),
      unitCodeOf: (v) => v.unitCode,
      registrationOf: (v) => v.registrationNumber,
    );
  }
}
