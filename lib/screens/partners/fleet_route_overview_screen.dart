import 'package:flutter/material.dart';

import 'fleet_route_overview_tab.dart';
import 'widgets/partner_modern_ui.dart';

/// Fullskjerm ruteoversikt (MAVI × dag) — åpnes fra planlegger-forsiden.
class FleetRouteOverviewScreen extends StatelessWidget {
  const FleetRouteOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F1419)
          : const Color(0xFFF3F4F6),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: PartnerModernUi.surface(context),
        foregroundColor: PartnerModernUi.textPrimary(context),
        title: const Text('Ruteoversikt'),
      ),
      body: const FleetRouteOverviewTab(),
    );
  }
}
