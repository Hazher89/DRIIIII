import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/driftpro_client.dart';
import '../core/services/supabase_service.dart';
import '../last_mile/models/lm_fleet_snapshot.dart';
import '../last_mile/services/driftpro_fleet_sync_service.dart';
import '../models/user_profile.dart';
import '../screens/partners/fleet_shift_admin_screen.dart';
import '../screens/partners/partner_route_planner_screen.dart';
import 'screens/dispatch_home_screen.dart';
import 'screens/dispatch_orders_screen.dart';
import 'screens/dispatch_planner_screen.dart';
import 'screens/dispatch_tracking_screen.dart';

enum DispatchSection {
  home,
  orders,
  planner,
  pdfImport,
  tracking,
  shifts,
}

/// Mac/PC last-mile command center — erstatter SAP + TransFleet (faser).
class DispatchShell extends StatefulWidget {
  final UserProfile profile;

  const DispatchShell({super.key, required this.profile});

  @override
  State<DispatchShell> createState() => _DispatchShellState();
}

class _DispatchShellState extends State<DispatchShell> {
  DispatchSection _section = DispatchSection.home;
  LmFleetSnapshot? _fleet;
  String? _companyLabel;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _syncFleet();
  }

  Future<void> _syncFleet() async {
    setState(() => _syncing = true);
    try {
      final fleet = await DriftproFleetSyncService.syncFromDriftpro();
      final cid = await SupabaseService.getCurrentCompanyId();
      var label = 'DriftPro';
      if (cid != null) {
        final meta = await SupabaseService.fetchCompanyDashboardMeta(cid);
        label = meta.companyName ?? label;
      }
      if (!mounted) return;
      setState(() {
        _fleet = fleet;
        _companyLabel = label;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Widget _body() {
    switch (_section) {
      case DispatchSection.home:
        return DispatchHomeScreen(
          profile: widget.profile,
          onOpenLegacyPlanner: () => setState(() => _section = DispatchSection.pdfImport),
          onOpenOrders: () => setState(() => _section = DispatchSection.orders),
          onOpenPlanner: () => setState(() => _section = DispatchSection.planner),
          onOpenTracking: () => setState(() => _section = DispatchSection.tracking),
        );
      case DispatchSection.orders:
        return const DispatchOrdersScreen();
      case DispatchSection.planner:
        return DispatchPlannerScreen(fleet: _fleet);
      case DispatchSection.pdfImport:
        return PartnerRoutePlannerScreen(embedded: true);
      case DispatchSection.tracking:
        return const DispatchTrackingScreen();
      case DispatchSection.shifts:
        return const FleetShiftAdminScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final fleet = _fleet;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DriftProClient.displayName),
            Text(
              fleet == null
                  ? 'Synkroniserer med DriftPro…'
                  : '$_companyLabel · ${fleet.vehicleCount} MAVI · ${fleet.partnerCount} bedrifter',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Hent flåte, sjåfør og bedrifter fra DriftPro',
            child: IconButton(
              onPressed: _syncing ? null : _syncFleet,
              icon: _syncing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined),
            ),
          ),
          PopupMenuButton<String>(
            icon: CircleAvatar(radius: 16, child: Text(widget.profile.initials)),
            itemBuilder: (ctx) => [
              PopupMenuItem(enabled: false, child: Text(widget.profile.fullName)),
              const PopupMenuItem(value: 'logout', child: Text('Logg ut')),
            ],
            onSelected: (v) {
              if (v == 'logout') _signOut();
            },
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            selectedIndex: _section.index,
            onDestinationSelected: (i) => setState(() => _section = DispatchSection.values[i]),
            labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Oversikt'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inbox_outlined),
                selectedIcon: Icon(Icons.inbox),
                label: Text('Ordre'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.alt_route_outlined),
                selectedIcon: Icon(Icons.alt_route),
                label: Text('Planlegger'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.picture_as_pdf_outlined),
                selectedIcon: Icon(Icons.picture_as_pdf),
                label: Text('PDF-import'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.my_location_outlined),
                selectedIcon: Icon(Icons.my_location),
                label: Text('Sporing'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.schedule_outlined),
                selectedIcon: Icon(Icons.schedule),
                label: Text('Skift'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
