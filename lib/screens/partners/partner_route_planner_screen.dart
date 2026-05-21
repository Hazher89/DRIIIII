import 'package:flutter/material.dart';

import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'fleet_route_dashboard_screen.dart';
import 'fleet_shift_admin_screen.dart';
import 'widgets/partner_route_master_scheduler.dart';
import 'widgets/partner_route_pdf_search_panel.dart';
import 'widgets/partner_ui.dart';

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

  Future<void> reload({bool notifyParent = false}) async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final fleet = await PartnerService.fetchCompanyFleet(cid);
      if (mounted) {
        setState(() {
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    if (notifyParent) {
      widget.onDataChanged?.call();
    }
  }

  int get _maviCount => _fleet.length;

  int get _partnerCount => _fleet.map((r) => r.partner.id).toSet().length;

  Future<void> _openShiftAdmin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FleetShiftAdminScreen()),
    );
    reload();
  }

  Future<void> _openStats() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const FleetRouteDashboardScreen()),
    );
    reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final body = RefreshIndicator(
      onRefresh: reload,
      color: DriftProTheme.primaryGreen,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
        children: [
          PartnerHeroBanner(
            compact: true,
            title: 'Ruter & planlegging',
            subtitle:
                'Kalender for alle MAVI-er • Ny rute og AUTO MASS for masse-PDF med SMS-varsling.',
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.alt_route_rounded, color: Colors.white, size: 26),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Administrer skift',
                  onPressed: _openShiftAdmin,
                  icon: const Icon(Icons.tune_rounded, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Flåte & statistikk',
                  onPressed: _openStats,
                  icon: const Icon(Icons.insights_outlined, color: Colors.white),
                ),
              ],
            ),
          ),
          PartnerKpiStrip(
            items: [
              PartnerKpiItem(
                label: 'MAVI-biler',
                value: '$_maviCount',
                color: DriftProTheme.primaryGreen,
                icon: Icons.local_shipping_outlined,
              ),
              PartnerKpiItem(
                label: 'Partnere',
                value: '$_partnerCount',
                color: DriftProTheme.accentBlue,
                icon: Icons.apartment_outlined,
              ),
              PartnerKpiItem(
                label: 'Skift',
                value: 'Admin',
                color: const Color(0xFF7B1FA2),
                icon: Icons.schedule_outlined,
                onTap: _openShiftAdmin,
              ),
              PartnerKpiItem(
                label: 'Statistikk',
                value: 'Live',
                color: const Color(0xFFEF6C00),
                icon: Icons.analytics_outlined,
                onTap: _openStats,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PartnerRouteMasterScheduler(
              fleet: _fleet,
              onChanged: () => reload(notifyParent: true),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ToolSection(
              icon: Icons.manage_search_outlined,
              iconColor: const Color(0xFF1565C0),
              title: 'Søk i rute-PDF',
              subtitle: 'Finn adresse, kunde eller MAVI i tidligere ruter',
              child: PartnerRoutePdfSearchPanel(fleet: _fleet, searchController: _pdfSearchCtrl),
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
    this.initiallyExpanded = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: PartnerUi.surface(context),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(color: Colors.grey.withValues(alpha: isDark ? 0.25 : 0.12)),
        boxShadow: isDark ? null : DriftProTheme.cardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          title: Text(title, style: DriftProTheme.headingSm.copyWith(fontSize: 15)),
          subtitle: Text(subtitle, style: DriftProTheme.caption),
          children: [child],
        ),
      ),
    );
  }
}
