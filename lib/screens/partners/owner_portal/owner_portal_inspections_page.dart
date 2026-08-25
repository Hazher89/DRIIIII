import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/services/hms/hms_pdf_export_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/vehicle_inspection_pdf.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/vehicle_inspection.dart';
import '../widgets/partner_portal_page_shell.dart';
import 'owner_portal_common.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class OwnerPortalInspectionsPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalInspectionsPage({super.key, required this.partner});

  @override
  State<OwnerPortalInspectionsPage> createState() => _OwnerPortalInspectionsPageState();
}

class _OwnerPortalInspectionsPageState extends State<OwnerPortalInspectionsPage> {
  List<PartnerVehicleInspection> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await OwnerPortalData.load(widget.partner);
    if (mounted) {
      setState(() {
        _items = d.inspections;
        _loading = false;
      });
    }
  }

  Future<void> _exportPdf(PartnerVehicleInspection inspection) async {
    await HmsPdfExportService.runWithFeedback(
      context,
      fileName: VehicleInspectionPdf.fileNameFor(inspection),
      generate: () async {
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
          partner: widget.partner,
          inspectorName: inspection.inspectedByName,
          photoBytes: photoBytes,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final withDeviation = _items.where((i) => i.hasDeviation).length;
    final byVehicle = <String, List<PartnerVehicleInspection>>{};
    for (final ins in _items) {
      final key = ins.unitCode ?? ins.registrationNumber ?? 'Ukjent';
      byVehicle.putIfAbsent(key, () => []).add(ins);
    }

    return PartnerPortalPageShell(
      title: 'Bilkontroll',
      body: _loading
          ? const DriftProLoadingCenter()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OwnerKpiCard(
                            label: 'Kontroller',
                            value: '${_items.length}',
                            icon: Icons.fact_check,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OwnerKpiCard(
                            label: 'Med avvik',
                            value: '$withDeviation',
                            icon: Icons.warning_amber,
                            accent: withDeviation > 0 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Ingen bilkontroller registrert ennå.')),
                    )
                  else
                    for (final entry in byVehicle.entries) ...[
                      OwnerSectionTitle(
                        title: entry.key.startsWith('NO_') ? MaviUnitCodes.normalize(entry.key) : entry.key,
                        subtitle: '${entry.value.length} kontroll(er)',
                      ),
                      ...entry.value.map((ins) {
                        final label = ins.registrationNumber ?? ins.unitCode ?? 'Bil';
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: ListTile(
                            leading: Icon(
                              ins.hasDeviation ? Icons.warning_amber : Icons.check_circle,
                              color: ins.hasDeviation ? Colors.orange : Colors.green,
                            ),
                            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${ins.stampLine}\n'
                              '${ins.hasDeviation ? (ins.deviationNotes ?? "Avvik") : "OK"}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              tooltip: 'Last ned PDF-rapport',
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              onPressed: () => _exportPdf(ins),
                            ),
                          ),
                        );
                      }),
                    ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
