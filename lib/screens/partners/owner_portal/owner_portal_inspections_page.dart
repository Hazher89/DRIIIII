import 'package:flutter/material.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/vehicle_inspection_checklist.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/vehicle_inspection.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/vehicle_inspection_detail_page.dart';
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

  void _openDetail(PartnerVehicleInspection inspection) {
    VehicleInspectionDetailPage.open(
      context,
      inspection: inspection,
      partner: widget.partner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final withDeviation = _items.where((i) => i.hasDeviation).length;
    final openFollowUp = _items.where((i) => i.followUpOpen).length;
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
                  if (openFollowUp > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$openFollowUp kontroll${openFollowUp == 1 ? '' : 'er'} '
                          'venter på oppfølging fra MAVI.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                        title: entry.key.startsWith('NO_')
                            ? MaviUnitCodes.normalize(entry.key)
                            : entry.key,
                        subtitle: '${entry.value.length} kontroll(er)',
                      ),
                      ...entry.value.map((ins) => _InspectionCard(
                            inspection: ins,
                            onTap: () => _openDetail(ins),
                          )),
                    ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _InspectionCard extends StatelessWidget {
  const _InspectionCard({
    required this.inspection,
    required this.onTap,
  });

  final PartnerVehicleInspection inspection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = VehicleInspectionChecklistSummary.fromInspection(inspection);
    final hasAvvik = inspection.hasDeviation || summary.avvikCount > 0;
    final statusColor = hasAvvik
        ? (inspection.followUpOpen ? Colors.orange.shade800 : const Color(0xFFEA580C))
        : Colors.green.shade700;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasAvvik ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inspection.registrationNumber ?? inspection.unitCode ?? 'Bil',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          inspection.stampLine,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[500]),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _pill('OK ${summary.okCount}', Colors.green.shade700),
                  if (summary.avvikCount > 0)
                    _pill('Avvik ${summary.avvikCount}', Colors.orange.shade800),
                  if (inspection.followUpOpen)
                    _pill('Venter oppfølging', Colors.orange.shade800),
                  if (inspection.followUpAcknowledgedAt != null)
                    _pill('Lukket', Colors.green.shade700),
                  if (inspection.nextInspectionAt != null)
                    _pill(
                      'Neste ${inspection.nextInspectionAt!.day}.${inspection.nextInspectionAt!.month}.${inspection.nextInspectionAt!.year}',
                      Colors.blueGrey,
                    ),
                ],
              ),
              if ((inspection.deviationNotes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  inspection.deviationNotes!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ],
              if (summary.avvikItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Avvik: ${summary.avvikItems.take(3).map((e) => e.label).join(', ')}'
                  '${summary.avvikItems.length > 3 ? '…' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
