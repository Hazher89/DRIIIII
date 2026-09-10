import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/chat/chat_flag_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../models/partner/partner_links.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'fleet_route_driver_stats_screen.dart';
import 'fleet_route_overview_screen.dart';
import 'fleet_shift_admin_screen.dart';
import 'partner_route_dispatch_history_screen.dart';
import 'widgets/partner_available_vehicles_bar.dart';
import 'widgets/partner_route_master_scheduler.dart';
import 'widgets/partner_route_pdf_search_panel.dart';
import 'widgets/partner_route_planner_ui.dart';
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
  bool _chatEnabled = true;

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
      var chatOn = true;
      try {
        final flag = await ChatFlagService.fetchForCompany(cid);
        chatOn = flag.maviEnabled;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _sharesToday = shares;
          _chatEnabled = chatOn;
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

  void _openHistory() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const PartnerRouteDispatchHistoryScreen(),
      ),
    );
  }

  void _openStats() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FleetRouteDriverStatsScreen()),
    );
  }

  void _openRouteOverview() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FleetRouteOverviewScreen()),
    );
  }

  void _openChat() {
    context.push(AppPaths.partnersChat);
  }

  List<RoutePlannerTool> _tools() {
    return [
      RoutePlannerTool(
        icon: Icons.grid_view_rounded,
        label: 'Ruteoversikt',
        onPressed: _openRouteOverview,
        emphasized: true,
      ),
      RoutePlannerTool(
        icon: Icons.history_rounded,
        label: 'Historikk',
        onPressed: _openHistory,
      ),
      RoutePlannerTool(
        icon: Icons.schedule_outlined,
        label: 'Skiftplan',
        onPressed: _openShiftAdmin,
      ),
      RoutePlannerTool(
        icon: Icons.insights_outlined,
        label: 'MAVI-statistikk',
        onPressed: _openStats,
      ),
      RoutePlannerTool(
        icon: Icons.manage_search_outlined,
        label: 'Søk PDF',
        onPressed: _openPdfSearch,
      ),
      if (_chatEnabled)
        RoutePlannerTool(
          icon: Icons.forum_outlined,
          label: 'Meldinger',
          onPressed: _openChat,
        ),
      RoutePlannerTool(
        icon: Icons.refresh_rounded,
        label: 'Oppdater',
        onPressed: () => reload(),
      ),
    ];
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
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: RoutePlannerUi.toolChipGroup(
                context: context,
                tools: _tools(),
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
      ),
      body: body,
    );
  }
}
