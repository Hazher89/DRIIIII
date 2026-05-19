import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'fleet_route_dashboard_screen.dart';
import 'fleet_shift_admin_screen.dart';
import 'widgets/partner_route_pdf_search_panel.dart';
import 'widgets/partner_route_publish_panel.dart';

/// Ruteplanlegging: én arbeidsflate for fordeling + publisering.
class PartnerRoutePlannerScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onDataChanged;

  const PartnerRoutePlannerScreen({
    super.key,
    this.embedded = false,
    this.onDataChanged,
  });

  @override
  State<PartnerRoutePlannerScreen> createState() => PartnerRoutePlannerScreenState();
}

class PartnerRoutePlannerScreenState extends State<PartnerRoutePlannerScreen> {
  final TextEditingController _pdfSearchCtrl = TextEditingController();
  List<FleetPartnerVehicleRow> _fleet = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _pdfSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final fleet = await PartnerService.fetchCompanyFleet(cid);
      if (mounted) {
        setState(() {
          _fleet = fleet;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    widget.onDataChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final body = RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: DriftProTheme.primaryGreen),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Ruter & planlegging', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              IconButton(
                tooltip: 'Administrer skift',
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const FleetShiftAdminScreen()),
                  );
                  reload();
                },
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'Flåte & statistikk',
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const FleetRouteDashboardScreen()),
                  );
                  reload();
                },
                icon: const Icon(Icons.analytics_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PartnerRoutePublishPanel(fleet: _fleet, onChanged: reload),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Søk i rute-PDF', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Finn tekst i tidligere distribuerte PDF-er', style: TextStyle(fontSize: 11)),
            children: [
              PartnerRoutePdfSearchPanel(fleet: _fleet, searchController: _pdfSearchCtrl),
            ],
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Ruter & planlegging')),
      body: body,
    );
  }
}
