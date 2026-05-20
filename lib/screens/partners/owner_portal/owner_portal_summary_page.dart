import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../widgets/partner_ui.dart';
import 'owner_portal_common.dart';

class OwnerPortalSummaryPage extends StatefulWidget {
  final Partner partner;
  const OwnerPortalSummaryPage({super.key, required this.partner});

  @override
  State<OwnerPortalSummaryPage> createState() => _OwnerPortalSummaryPageState();
}

class _OwnerPortalSummaryPageState extends State<OwnerPortalSummaryPage> {
  OwnerPortalData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await OwnerPortalData.load(widget.partner);
    if (mounted) setState(() { _data = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = _data?.summary90;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Oppsummering'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => signOutFromPortal(context),
          ),
        ],
      ),
      body: _loading || s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  PartnerHeroBanner(
                    title: '90-dagers oppsummering',
                    subtitle: 'Hele flåten din — siste 90 dager',
                    leading: const Icon(Icons.analytics_outlined, color: Colors.white, size: 32),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.2,
                      children: [
                        OwnerKpiCard(label: 'Ruter mottatt', value: '${s.routesReceived}', icon: Icons.send),
                        OwnerKpiCard(
                          label: 'Utnyttelse',
                          value: '${s.utilizationPercent.toStringAsFixed(0)}%',
                          icon: Icons.speed,
                        ),
                        OwnerKpiCard(label: 'Jobbdager', value: '${s.harRuteDays}', icon: Icons.work),
                        OwnerKpiCard(label: 'Ledig', value: '${s.ledigDays}', icon: Icons.pause, accent: Colors.orange),
                        OwnerKpiCard(label: 'Fri', value: '${s.friDays}', icon: Icons.beach_access),
                        OwnerKpiCard(label: 'Gitt bort', value: '${s.gittBortDays}', icon: Icons.swap_horiz),
                      ],
                    ),
                  ),
                  const OwnerSectionTitle(title: 'Statusfordeling (kalenderdager)'),
                  _breakdownBar(context, s.statusBreakdown),
                  const OwnerSectionTitle(title: 'Per bil — rangert'),
                  ..._data!.vehicleStats.map((vs) => OwnerVehicleStackCard(stats: vs)),
                  if (s.dailyTrend.isNotEmpty) ...[
                    const OwnerSectionTitle(title: 'Siste dager i trend'),
                    ...s.dailyTrend.reversed.take(14).map(
                          (p) => ListTile(
                            dense: true,
                            title: Text(ownerFmtDate(p.day)),
                            subtitle: Text(
                              'Jobb ${p.harRute} · Ledig ${p.ledig} · Fri ${p.fri} · Ruter sendt ${p.routesSent}',
                            ),
                          ),
                        ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _breakdownBar(BuildContext context, Map<String, int> b) {
    final total = b.values.fold<int>(0, (a, c) => a + c);
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Ingen kalenderdata ennå.'),
      );
    }
    final items = [
      ('Jobb / rute', b['har_rute'] ?? 0, DriftProTheme.primaryGreen),
      ('Ledig', b['ledig'] ?? 0, Colors.orange),
      ('Fri', b['fri'] ?? 0, DriftProTheme.accentBlue),
      ('Gitt bort', b['gitt_bort'] ?? 0, Colors.grey),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items.map((e) {
          final pct = total > 0 ? (e.$2 / total) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('${e.$2} (${(pct * 100).toStringAsFixed(0)}%)'),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: e.$3,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
