import 'package:flutter/material.dart';

import '../../core/config/driftpro_client.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../last_mile/models/lm_fleet_snapshot.dart';
import '../../last_mile/services/driftpro_fleet_sync_service.dart';
import '../../last_mile/services/last_mile_order_service.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

class DispatchHomeScreen extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback onOpenLegacyPlanner;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenTracking;

  const DispatchHomeScreen({
    super.key,
    required this.profile,
    required this.onOpenLegacyPlanner,
    required this.onOpenOrders,
    required this.onOpenPlanner,
    required this.onOpenTracking,
  });

  @override
  State<DispatchHomeScreen> createState() => _DispatchHomeScreenState();
}

class _DispatchHomeScreenState extends State<DispatchHomeScreen> {
  LmFleetSnapshot? _fleet;
  int _pendingOrders = 0;
  int _sapInboxPending = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final fleet = await DriftproFleetSyncService.syncFromDriftpro();
      final orders = await LastMileOrderService.countPending();
      var sap = 0;
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid != null) {
        sap = (await PartnerService.fetchSapRouteInboxPending(cid)).length;
      }
      if (!mounted) return;
      setState(() {
        _fleet = fleet;
        _pendingOrders = orders;
        _sapInboxPending = sap;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingCenter();
    final fleet = _fleet!;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            DriftProClient.displayName,
            style: DriftProTheme.headingMd.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Erstatter SAP (ordre) og TransFleet (planlegging, sporing). '
            'All masterdata fra DriftPro Supabase.',
            style: DriftProTheme.bodyMd.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard('MAVI-biler', '${fleet.vehicleCount}', Icons.local_shipping, widget.onOpenPlanner),
              _MetricCard('Bedrifter', '${fleet.partnerCount}', Icons.business),
              _MetricCard('Sjåfør', '${fleet.driverPortalCount}', Icons.person),
              _MetricCard('Ordrekø', '$_pendingOrders', Icons.inbox, widget.onOpenOrders),
              _MetricCard('SAP (overgang)', '$_sapInboxPending', Icons.mail, widget.onOpenLegacyPlanner),
            ],
          ),
          const SizedBox(height: 24),
          _ActionCard(
            title: '1. Ordre',
            subtitle: 'PDF/SAP → lm_orders, manuell opprettelse, geokoding',
            icon: Icons.inbox,
            onTap: widget.onOpenOrders,
          ),
          _ActionCard(
            title: '2. Planlegger + VRPTW',
            subtitle: 'Kart, optimalisering, drag-drop, publiser til sjåfør',
            icon: Icons.alt_route,
            onTap: widget.onOpenPlanner,
          ),
          _ActionCard(
            title: '3. Live sporing',
            subtitle: 'Realtime GPS fra sjåfør-app på kart',
            icon: Icons.my_location,
            onTap: widget.onOpenTracking,
          ),
          _ActionCard(
            title: 'Sjåfør-app',
            subtitle: 'flutter run -t lib/main_driver.dart',
            icon: Icons.phone_android,
          ),
          _ActionCard(
            title: 'Kundesporing',
            subtitle: 'https://din-app/?track=TOKEN (etter publisering)',
            icon: Icons.link,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, [this.onTap]);
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: DriftProTheme.primaryGreen),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: DriftProTheme.primaryGreen),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
