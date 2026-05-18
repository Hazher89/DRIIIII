import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner_links.dart';
import 'fleet_route_dashboard_screen.dart';
import 'fleet_shift_admin_screen.dart';
import 'widgets/partner_mass_route_panel.dart';
import 'widgets/partner_route_dispatch_panel.dart';
import 'widgets/partner_route_pdf_search_panel.dart';

/// Ruteplanlegging: 1) Fordel PDF  2) Velg skift & send  3) Søk i PDF  4) Flåteoversikt
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

class PartnerRoutePlannerScreenState extends State<PartnerRoutePlannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _steps;
  final TextEditingController _pdfSearchCtrl = TextEditingController();
  List<FleetPartnerVehicleRow> _fleet = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _steps = TabController(length: 3, vsync: this);
    reload();
  }

  @override
  void dispose() {
    _steps.dispose();
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

    final body = Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.route_outlined, color: DriftProTheme.primaryGreen),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Rutefordeling',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Administrer skift',
                      onPressed: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const FleetShiftAdminScreen(),
                          ),
                        );
                        reload();
                      },
                      icon: const Icon(Icons.tune),
                    ),
                    IconButton(
                      tooltip: 'Flåte & statistikk',
                      onPressed: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const FleetRouteDashboardScreen(),
                          ),
                        );
                        reload();
                      },
                      icon: const Icon(Icons.analytics_outlined),
                    ),
                    IconButton(
                      tooltip: 'Oppdater',
                      onPressed: reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _steps,
                isScrollable: true,
                tabs: const [
                  Tab(text: '1. Fordel PDF'),
                  Tab(text: '2. Send & skift'),
                  Tab(text: '3. Søk i PDF'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _steps,
            children: [
              _scrollTab([
                PartnerMassRoutePanel(
                  onDistributed: () {
                    reload();
                    _steps.animateTo(1);
                  },
                ),
                const SizedBox(height: 12),
                _tipCard(
                  'Etter PDF-fordeling går du til steg 2. Der velger du biler og hvilket skift '
                  'sjåføren skal se sammen med ruten.',
                ),
              ]),
              _scrollTab([
                PartnerRouteDispatchPanel(
                  fleet: _fleet,
                  onDispatched: reload,
                ),
                const SizedBox(height: 12),
                _todaySummary(),
              ]),
              _scrollTab([
                PartnerRoutePdfSearchPanel(
                  fleet: _fleet,
                  searchController: _pdfSearchCtrl,
                ),
              ]),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Ruter & planlegging')),
      body: body,
    );
  }

  Widget _scrollTab(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: children,
      ),
    );
  }

  Widget _tipCard(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 20, color: Color(0xFF1565C0)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35))),
        ],
      ),
    );
  }

  Future<List<PartnerRouteShare>> _loadTodayShares() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return [];
    final shares = await PartnerService.fetchRouteSharesForCompany(cid, limit: 200);
    final dStr = DateTime.now().toIso8601String().split('T').first;
    return shares
        .where((s) =>
            s.dispatchStatus == 'sent' &&
            s.shareDate.toIso8601String().split('T').first == dStr)
        .toList();
  }

  Widget _todaySummary() {
    return FutureBuilder<List<PartnerRouteShare>>(
      future: _loadTodayShares(),
      builder: (ctx, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return _tipCard('Ingen ruter sendt til sjåfør i dag ennå.');
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sendt i dag (${list.length})', style: DriftProTheme.headingSm),
                const SizedBox(height: 8),
                ...list.take(8).map((s) {
                  String label = s.title ?? 'PDF';
                  for (final row in _fleet) {
                    if (row.vehicle.id == s.partnerVehicleId) {
                      label =
                          '${row.partner.name} · ${MaviUnitCodes.normalize(row.vehicle.unitCode)}';
                      break;
                    }
                  }
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle, color: DriftProTheme.primaryGreen, size: 20),
                    title: Text(label, style: const TextStyle(fontSize: 12)),
                    subtitle: Text(
                      DateFormat('HH:mm').format(s.createdAt),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
