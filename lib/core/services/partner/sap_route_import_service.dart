import 'dart:typed_data';

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
    /// Når false: feilede PDF-er returneres til UI for manuell tildeling (ikke avvist i DB).
    bool rejectOnFailure = true,
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

    final fallbackDay = DateTime(routeDate.year, routeDate.month, routeDate.day);
    var staged = await PartnerService.fetchStagedRouteShares(companyId);
    final lines = <SapRouteImportLine>[];
    final skippedItems = <SapRouteImportSkippedItem>[];
    var imported = 0;
    var skipped = 0;

    for (final item in targets) {
      try {
        if (item.importedRouteShareId != null) {
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: true,
            message: 'Allerede importert',
          ));
          continue;
        }

        final bytes = await PartnerService.downloadRoutePdfBytes(item.pdfStoragePath);
        if (bytes == null || bytes.isEmpty) {
          await _failItem(
            item: item,
            rejectOnFailure: rejectOnFailure,
            reason: 'Kunne ikke lese PDF',
            bytes: null,
            skippedItems: skippedItems,
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
          await _failItem(
            item: item,
            rejectOnFailure: rejectOnFailure,
            reason: 'Fant ikke MAVI-nummer i PDF',
            bytes: bytes,
            detectedCode: null,
            skippedItems: skippedItems,
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
          await _failItem(
            item: item,
            rejectOnFailure: rejectOnFailure,
            reason: 'Ingen bil matcher $code',
            bytes: bytes,
            detectedCode: code,
            skippedItems: skippedItems,
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
          await _failItem(
            item: item,
            rejectOnFailure: rejectOnFailure,
            reason: 'Partner mangler',
            bytes: bytes,
            detectedCode: code,
            skippedItems: skippedItems,
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

        final existing = staged.where(
          (s) => PartnerService.stagedShareMatchesSapFile(
            share: s,
            fileName: item.fileName,
            vehicleId: vehicle.id,
          ),
        ).firstOrNull;
        if (existing != null) {
          await PartnerService.markSapRouteInboxImported(
            inboxId: item.id,
            routeShareId: existing.id,
            detectedMaviCode: MaviUnitCodes.normalize(vehicle.unitCode),
          );
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: true,
            maviCode: MaviUnitCodes.normalize(vehicle.unitCode),
            message: 'Allerede i kø',
          ));
          continue;
        }

        final bundle = RoutePdfTextService.parseBundle(bytes, fallbackDate: fallbackDay);
        final shareId = await PartnerService.createStagedRouteShareFromPdf(
          companyId: companyId,
          partner: partner,
          vehicle: vehicle,
          fileName: item.fileName,
          bytes: bytes,
          routeDate: bundle.schedule.routeDate,
          parsed: bundle,
          stagedImportSource: PartnerService.stagedImportSap,
        );

        await PartnerService.markSapRouteInboxImported(
          inboxId: item.id,
          routeShareId: shareId,
          detectedMaviCode: MaviUnitCodes.normalize(vehicle.unitCode),
        );

        imported++;
        staged = await PartnerService.fetchStagedRouteShares(companyId);
        lines.add(SapRouteImportLine(
          fileName: item.fileName,
          ok: true,
          maviCode: MaviUnitCodes.normalize(vehicle.unitCode),
        ));
      } catch (e) {
        await _failItem(
          item: item,
          rejectOnFailure: rejectOnFailure,
          reason: e.toString(),
          bytes: null,
          skippedItems: skippedItems,
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
      skippedItems: skippedItems,
    );
  }

  static Future<void> _failItem({
    required SapRouteInboxItem item,
    required bool rejectOnFailure,
    required String reason,
    required List<SapRouteImportSkippedItem> skippedItems,
    Uint8List? bytes,
    String? detectedCode,
  }) async {
    if (rejectOnFailure) {
      await PartnerService.markSapRouteInboxRejected(id: item.id, reason: reason);
      return;
    }
    await PartnerService.markSapRouteInboxManual(id: item.id, reason: reason);
    if (bytes != null && bytes.isNotEmpty) {
      skippedItems.add(SapRouteImportSkippedItem(
        inboxId: item.id,
        fileName: item.fileName,
        bytes: bytes,
        reason: reason,
        detectedCode: detectedCode,
      ));
    }
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
