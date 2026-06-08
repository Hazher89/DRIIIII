import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../models/partner/partner_links.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'fleet_route_driver_stats_screen.dart';
import 'fleet_shift_admin_screen.dart';
import 'widgets/partner_available_vehicles_bar.dart';
import 'widgets/partner_route_master_scheduler.dart';
import 'widgets/partner_route_pdf_search_panel.dart';
import 'widgets/partner_ui.dart';

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
  final TextEditingController _pdfSearchCtrl = TextEditingController();
  List<FleetPartnerVehicleRow> _fleet = [];
  List<PartnerRouteShare> _sharesToday = [];
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);

    final slivers = <Widget>[
      if (widget.nestedScroll)
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: PartnerAvailableVehiclesPanel(
            fleet: _fleet,
            sharesToday: _sharesToday,
            day: day,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
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
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _openShiftAdmin,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: const Text('Skiftplan'),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: PartnerRouteMasterScheduler(
            fleet: _fleet,
            onChanged: () => reload(notifyParent: true, silent: true),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _ToolSection(
            icon: Icons.manage_search_outlined,
            iconColor: const Color(0xFF1565C0),
            title: 'Søk i rute-PDF',
            subtitle: 'Finn adresse, kunde eller MAVI i tidligere ruter',
            child: PartnerRoutePdfSearchPanel(fleet: _fleet, searchController: _pdfSearchCtrl),
          ),
        ),
      ),
    ];

    final body = RefreshIndicator(
      onRefresh: reload,
      color: DriftProTheme.primaryGreen,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruter & planlegging'),
        actions: [
          IconButton(tooltip: 'Oppdater', onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: body,
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(icon, color: iconColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        children: [Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: child)],
      ),
    );
  }
}
