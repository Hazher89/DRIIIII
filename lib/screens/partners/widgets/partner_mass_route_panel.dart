import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_links.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Smart PDF-fordeling: leser Resource ID og sender til riktig MAVI/bil.
class PartnerMassRoutePanel extends StatefulWidget {
  final VoidCallback? onDistributed;

  const PartnerMassRoutePanel({super.key, this.onDistributed});

  @override
  State<PartnerMassRoutePanel> createState() => _PartnerMassRoutePanelState();
}

class _PartnerMassRoutePanelState extends State<PartnerMassRoutePanel> {
  bool _busy = false;

  Map<String, PartnerVehicle> _vehicleLookupMap(List<PartnerVehicle> rows) {
    return RoutePdfTextService.buildVehicleLookupMap(
      vehicles: rows,
      unitCodeOf: (v) => v.unitCode,
      registrationOf: (v) => v.registrationNumber,
    );
  }

  Future<Uint8List?> _platformFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) return file.bytes;
    if (!kIsWeb && file.path != null) {
      try {
        return await File(file.path!).readAsBytes();
      } catch (_) {}
    }
    if (file.readStream != null) {
      final out = <int>[];
      await for (final chunk in file.readStream!) {
        out.addAll(chunk);
      }
      if (out.isEmpty) return null;
      return Uint8List.fromList(out);
    }
    return null;
  }

  Future<void> _distributeFiles(List<PlatformFile> files) async {
    if (_busy || files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');

      final partners = await PartnerService.fetchPartners(companyId: cid);
      final partnerById = {for (final p in partners) p.id: p};
      final vehicleRows = <PartnerVehicle>[];
      for (final p in partners) {
        vehicleRows.addAll(await PartnerService.fetchVehicles(p.id));
      }
      final vehicleMap = _vehicleLookupMap(vehicleRows);

      int staged = 0;
      int skipped = 0;
      for (final file in files) {
        final bytes = await _platformFileBytes(file);
        if (bytes == null || bytes.isEmpty) {
          skipped++;
          continue;
        }
        final foundCode = RoutePdfTextService.extractResourceIdFromBytes(bytes);
        if (foundCode == null) {
          skipped++;
          continue;
        }
        final vehicle = RoutePdfTextService.findVehicleInLookup(vehicleMap, foundCode);
        if (vehicle == null) {
          skipped++;
          continue;
        }
        final partner = partnerById[vehicle.partnerId];
        if (partner == null) {
          skipped++;
          continue;
        }
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final storagePath =
            'company_$cid/partner_routes/${DateTime.now().millisecondsSinceEpoch}_${vehicle.unitCode}_$safeName';
        final storedPath = await PartnerService.uploadPartnerRoutePdf(
          storagePath: storagePath,
          bytes: bytes,
        );
        final pdfText = RoutePdfTextService.extractFullText(bytes);
        final schedule = RoutePdfTextService.resolveSchedule(pdfText, fallbackDate: DateTime.now());
        final share = await PartnerService.addRouteShare(
          PartnerRouteShare(
            id: '',
            partnerId: partner.id,
            companyId: cid,
            title: 'Rute ${vehicle.unitCode} — ${file.name}',
            pdfStoragePath: storedPath,
            shareDate: schedule.routeDate,
            isDailyShare: true,
            createdAt: DateTime.now(),
            dispatchStatus: 'staged',
            pdfSearchText: pdfText.isEmpty ? null : pdfText,
            partnerVehicleId: vehicle.id,
          ),
        );
        if (pdfText.isNotEmpty) {
          await PartnerService.saveRoutePdfSearchText(share.id, pdfText);
        }
        if (schedule.routeStartAt != null) {
          await PartnerService.updateRouteShareFields(share.id, {
            'route_start_at': schedule.routeStartAt!.toUtc().toIso8601String(),
          });
        }
        staged++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fordelt $staged rute(r) til riktig bil. $skipped hoppet over. '
              'Gå til «Send til sjåfør» for å velge skift og sende.',
            ),
          ),
        );
      }
      widget.onDistributed?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fordeling feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    await _distributeFiles(picked.files);
  }

  Future<void> _pickFolder() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mappevalg støttes ikke i web. Velg flere PDF-filer.')),
      );
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Velg mappe med rute-PDF',
    );
    if (dir == null) return;
    final entries = await Directory(dir).list().toList();
    final pdfFiles = entries
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    if (pdfFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fant ingen PDF-filer i mappen.')),
      );
      return;
    }
    final files = <PlatformFile>[];
    for (final f in pdfFiles) {
      final bytes = await f.readAsBytes();
      files.add(
        PlatformFile(
          name: f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'route.pdf',
          size: bytes.length,
          bytes: bytes,
          path: f.path,
        ),
      );
    }
    await _distributeFiles(files);
  }

  @override
  Widget build(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.22 : 0.14),
            const Color(0xFF1565C0).withValues(alpha: isDark ? 0.18 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.85),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: DriftProTheme.primaryGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart PDF-fordeling',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Steg 1: Leser NO_O_Mxxxx og kobler PDF til riktig bil. '
                        'Skift velges når du sender til sjåfør (steg 2).',
                        style: TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _pickFiles,
                  icon: _busy
                      ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Velg PDF-filer'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFolder,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Velg mappe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
