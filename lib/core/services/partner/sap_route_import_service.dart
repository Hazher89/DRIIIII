import 'dart:typed_data';

import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/sap_route_inbox.dart';
import 'mavi_unit_codes.dart';
import 'partner_service.dart';
import 'route_pdf_text_service.dart';
import 'staged_route_duplicate_helper.dart';

/// Importerer ventende SAP-PDF-er til staged ruter (samme logikk som AUTO MASS).
class SapRouteImportService {
  SapRouteImportService._();

  static const _downloadConcurrency = 6;

  static Future<SapRouteImportResult> importPendingToStaged({
    required String companyId,
    required DateTime routeDate,
    required List<FleetPartnerVehicleRow> fleet,
    List<String>? inboxIds,
    /// Når false: feilede PDF-er returneres til UI for manuell tildeling (ikke avvist i DB).
    bool rejectOnFailure = true,
    void Function(int done, int total)? onProgress,
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
    var staged = await PartnerService.fetchStagedRouteShares(
      companyId,
      importSource: PartnerService.stagedImportSap,
    );
    final lines = <SapRouteImportLine>[];
    final skippedItems = <SapRouteImportSkippedItem>[];
    var imported = 0;
    var skipped = 0;
    final total = targets.length;
    var progressDone = 0;

    void bumpProgress() {
      progressDone++;
      onProgress?.call(progressDone, total);
    }

    for (var offset = 0; offset < targets.length; offset += _downloadConcurrency) {
      final slice = targets.skip(offset).take(_downloadConcurrency).toList();
      final downloaded = await Future.wait(slice.map((item) async {
        if (item.importedRouteShareId != null) {
          return _DownloadOutcome.already(item);
        }
        try {
          final bytes =
              await PartnerService.downloadRoutePdfBytes(item.pdfStoragePath);
          if (bytes == null || bytes.isEmpty) {
            return _DownloadOutcome.fail(item, 'Kunne ikke lese PDF');
          }
          final bundle = RoutePdfTextService.parseBundle(
            bytes,
            fallbackDate: fallbackDay,
            fileName: item.fileName,
          );
          final code = bundle.meta.maviCode ??
              RoutePdfTextService.extractResourceIdFromBytes(bytes);
          return _DownloadOutcome.ok(
            item: item,
            bytes: bytes,
            bundle: bundle,
            code: code,
          );
        } catch (e) {
          return _DownloadOutcome.fail(item, e.toString());
        }
      }));

      for (final row in downloaded) {
        final item = row.item;
        if (row.kind == _DownloadKind.already) {
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: true,
            message: 'Allerede importert',
          ));
          bumpProgress();
          continue;
        }
        if (row.kind == _DownloadKind.fail) {
          await _failItem(
            item: item,
            rejectOnFailure: rejectOnFailure,
            reason: row.error ?? 'Feil',
            bytes: null,
            skippedItems: skippedItems,
          );
          skipped++;
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: false,
            message: row.error,
          ));
          bumpProgress();
          continue;
        }

        final bytes = row.bytes!;
        final bundle = row.bundle!;
        final code = row.code;

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
          bumpProgress();
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
          bumpProgress();
          continue;
        }

        final Partner? partner = partnerById[vehicle.partnerId];
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
          bumpProgress();
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
          bumpProgress();
          continue;
        }

        final contentDup = StagedRouteDuplicateHelper.findDuplicateInStaged(
          staged: staged,
          pdfSearchText: bundle.searchText,
          bytes: bytes,
          contentSha256: item.contentSha256,
        );
        if (contentDup != null) {
          await PartnerService.markSapRouteInboxImported(
            inboxId: item.id,
            routeShareId: contentDup.id,
            detectedMaviCode: MaviUnitCodes.normalize(vehicle.unitCode),
          );
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: true,
            maviCode: MaviUnitCodes.normalize(vehicle.unitCode),
            message: 'Duplikat — allerede i kø',
          ));
          bumpProgress();
          continue;
        }

        try {
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
          final created = await PartnerService.fetchRouteShareById(shareId);
          if (created != null) {
            staged = [...staged, created];
          }
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
            bytes: bytes,
            detectedCode: code,
            skippedItems: skippedItems,
          );
          skipped++;
          lines.add(SapRouteImportLine(
            fileName: item.fileName,
            ok: false,
            message: e.toString(),
          ));
        }
        bumpProgress();
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

enum _DownloadKind { already, fail, ok }

class _DownloadOutcome {
  final SapRouteInboxItem item;
  final _DownloadKind kind;
  final Uint8List? bytes;
  final RoutePdfParseBundle? bundle;
  final String? code;
  final String? error;

  const _DownloadOutcome._({
    required this.item,
    required this.kind,
    this.bytes,
    this.bundle,
    this.code,
    this.error,
  });

  factory _DownloadOutcome.already(SapRouteInboxItem item) =>
      _DownloadOutcome._(item: item, kind: _DownloadKind.already);

  factory _DownloadOutcome.fail(SapRouteInboxItem item, String error) =>
      _DownloadOutcome._(item: item, kind: _DownloadKind.fail, error: error);

  factory _DownloadOutcome.ok({
    required SapRouteInboxItem item,
    required Uint8List bytes,
    required RoutePdfParseBundle bundle,
    required String? code,
  }) =>
      _DownloadOutcome._(
        item: item,
        kind: _DownloadKind.ok,
        bytes: bytes,
        bundle: bundle,
        code: code,
      );
}
