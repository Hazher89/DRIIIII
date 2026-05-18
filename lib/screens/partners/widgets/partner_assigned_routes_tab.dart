import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';

/// Tildelte ruter for én partner — status, skift, sporingsinfo.
class PartnerAssignedRoutesTab extends StatefulWidget {
  final Partner partner;

  const PartnerAssignedRoutesTab({super.key, required this.partner});

  @override
  State<PartnerAssignedRoutesTab> createState() =>
      _PartnerAssignedRoutesTabState();
}

class _PartnerAssignedRoutesTabState extends State<PartnerAssignedRoutesTab> {
  List<PartnerRouteShare> _routes = [];
  List<PartnerVehicle> _vehicles = [];
  List<FleetShiftDefinition> _shifts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await PartnerService.ensureDefaultFleetShifts(widget.partner.companyId);
      final routes = await PartnerService.fetchRouteShares(widget.partner.id);
      final vehicles = await PartnerService.fetchVehicles(widget.partner.id);
      final shifts =
          await PartnerService.fetchFleetShifts(widget.partner.companyId);
      if (mounted) {
        setState(() {
          _routes = routes;
          _vehicles = vehicles;
          _shifts = shifts;
          _loading = false;
        });
      }
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  String? _vehicleLabel(String? vehicleId) {
    if (vehicleId == null) return null;
    for (final v in _vehicles) {
      if (v.id == vehicleId) return '${v.unitCode} · ${v.registrationNumber}';
    }
    return null;
  }

  String? _shiftName(String? shiftId) {
    if (shiftId == null) return null;
    for (final s in _shifts) {
      if (s.id == shiftId) return s.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final accepted = _routes.where((r) => r.ackStatus == 'accepted').length;
    final pending = _routes.where((r) => r.ackStatus == 'pending').length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _kpi('Totalt', '${_routes.length}', Icons.route),
              const SizedBox(width: 8),
              _kpi('Akseptert', '$accepted', Icons.check_circle_outline),
              const SizedBox(width: 8),
              _kpi('Venter', '$pending', Icons.hourglass_empty),
            ],
          ),
          const SizedBox(height: 16),
          if (_routes.isEmpty)
            const Center(child: Text('Ingen tildelte ruter ennå'))
          else
            ..._routes.map((r) => _routeCard(r)),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(label, style: DriftProTheme.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeCard(PartnerRouteShare r) {
    final ackColor = switch (r.ackStatus) {
      'accepted' => Colors.green,
      'rejected' => Colors.red,
      _ => Colors.orange,
    };
    final ackLabel = switch (r.ackStatus) {
      'accepted' => 'Akseptert',
      'rejected' => 'Avvist',
      _ => 'Venter',
    };
    final vehicle = _vehicleLabel(r.partnerVehicleId);
    final shift = _shiftName(r.shiftId);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ackColor.withValues(alpha: 0.15),
          child: Icon(Icons.local_shipping, color: ackColor, size: 20),
        ),
        title: Text(r.title ?? 'Rute ${r.shareDate.day}.${r.shareDate.month}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dato: ${r.shareDate.day}.${r.shareDate.month}.${r.shareDate.year}'),
            if (vehicle != null) Text('Bil: $vehicle'),
            if (shift != null) Text('Skift: $shift'),
            Text(ackLabel, style: TextStyle(color: ackColor, fontWeight: FontWeight.w700)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: () async {
            try {
              final url = await PartnerService.getRoutePdfSignedUrl(r.pdfStoragePath);
              await launchUrl(Uri.parse(url));
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Kunne ikke åpne PDF: $e')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}
