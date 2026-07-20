import 'package:flutter/material.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/services/partner/partner_service.dart';
import '../../models/partner/partner_links.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'fleet_route_driver_stats_screen.dart';
import 'fleet_shift_admin_screen.dart';
import 'widgets/partner_available_vehicles_bar.dart';
import 'widgets/partner_route_master_scheduler.dart';
import 'widgets/partner_route_pdf_search_panel.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Ruteplanlegging: én arbeidsflate for fordeling + publisering.
class PartnerRoutePlannerScreen extends StatefulWidget {
  final bool embedded;
  final bool nestedScroll;
  final VoidCallback? onDataChanged;

  const PartnerRoutePlannerScreen({
    super.key,
    this.embedded = false,
    this.nestedScroll = false,
    this.onDataChanged,
  });

  @override
  State<PartnerRoutePlannerScreen> createState() => PartnerRoutePlannerScreenState();
}

class PartnerRoutePlannerScreenState extends State<PartnerRoutePlannerScreen> {
  List<FleetPartnerVehicleRow> _fleet = [];
  List<PartnerRouteShare> _sharesToday = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload({bool notifyParent = false, bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final fleet = await PartnerService.fetchCompanyFleet(cid, forPlanning: true);
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final shares = await PartnerService.fetchRouteSharesForCalendarWindow(
        companyId: cid,
        fromDay: day,
        toDay: day,
      );
      if (mounted) {
        setState(() {
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _sharesToday = shares;
          if (!silent) _loading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _loading = false);
    }
    if (notifyParent) {
      widget.onDataChanged?.call();
    }
  }

  Future<void> _openShiftAdmin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FleetShiftAdminScreen()),
    );
    reload();
  }

  void _openPdfSearch() {
    PartnerRoutePdfSearchPanel.show(context, fleet: _fleet);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }

    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);

    final body = RefreshIndicator(
      onRefresh: reload,
      color: DriftProTheme.primaryGreen,
      child: PartnerRouteMasterScheduler(
        fleet: _fleet,
        nestedScroll: widget.nestedScroll,
        onChanged: () => reload(notifyParent: true, silent: true),
        leadingSlivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                DriftProClient.isMobile ? 4 : 12,
                12,
                0,
              ),
              child: PartnerAvailableVehiclesPanel(
                fleet: _fleet,
                sharesToday: _sharesToday,
                day: day,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: DriftProClient.isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(builder: (_) => const FleetRouteDriverStatsScreen()),
                            );
                          },
                          icon: const Icon(Icons.insights_outlined, size: 18),
                          label: const Text('MAVI-statistikk'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _openShiftAdmin,
                                icon: const Icon(Icons.schedule_outlined, size: 18),
                                label: const Text('Skiftplan'),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Søk i rute-PDF',
                              onPressed: _openPdfSearch,
                              icon: const Icon(Icons.manage_search_outlined),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute(builder: (_) => const FleetRouteDriverStatsScreen()),
                              );
                            },
                            icon: const Icon(Icons.insights_outlined, size: 18),
                            label: const Text('MAVI-statistikk'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: _openShiftAdmin,
                          icon: const Icon(Icons.schedule_outlined, size: 18),
                          label: const Text('Skiftplan'),
                        ),
                        IconButton(
                          tooltip: 'Søk i rute-PDF',
                          onPressed: _openPdfSearch,
                          icon: const Icon(Icons.manage_search_outlined),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruter & planlegging'),
        actions: [
          IconButton(
            tooltip: 'Søk i rute-PDF',
            onPressed: _openPdfSearch,
            icon: const Icon(Icons.manage_search_outlined),
          ),
          IconButton(tooltip: 'Oppdater', onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: body,
    );
  }
}
