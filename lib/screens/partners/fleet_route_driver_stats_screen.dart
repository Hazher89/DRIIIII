import 'package:flutter/material.dart';

import '../../core/services/partner/fleet_analytics_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_modern_ui.dart';

/// MAVI-basert rute-statistikk — rettferdig fordeling, filtre og sortering.
class FleetRouteDriverStatsScreen extends StatefulWidget {
  const FleetRouteDriverStatsScreen({super.key});

  @override
  State<FleetRouteDriverStatsScreen> createState() => _FleetRouteDriverStatsScreenState();
}

class _FleetRouteDriverStatsScreenState extends State<FleetRouteDriverStatsScreen> {
  FleetCalendarPeriod _period = FleetCalendarPeriod.month;
  FleetDriverSortKey _sort = FleetDriverSortKey.routesDesc;
  FleetDriverFilterKey _filter = FleetDriverFilterKey.withRoutes;
  String? _partnerFilter;
  final _maviSearch = TextEditingController();

  bool _loading = true;
  String? _error;
  List<FleetPartnerVehicleRow> _fleet = [];
  List<PartnerRouteShare> _shares = [];
  List<PartnerVehicleFleetSnapshot> _snaps = [];

  @override
  void initState() {
    super.initState();
    _load();
    _maviSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _maviSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final now = DateTime.now();
      final from = _period.rangeStart(now);
      final fleet = await PartnerService.fetchCompanyFleet(cid, forPlanning: false);
      final shares = await PartnerService.fetchRouteSharesForCalendarWindow(
        companyId: cid,
        fromDay: from,
        toDay: now,
      );
      final snaps = await PartnerService.fetchFleetSnapshotsRange(
        companyId: cid,
        from: from,
        to: now,
      );
      if (mounted) {
        setState(() {
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _shares = shares;
          _snaps = snaps;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  FleetDriverStatsBundle get _bundle => FleetAnalyticsService.buildDriverStats(
        period: _period,
        shares: _shares,
        snapshots: _snaps,
        fleet: _fleet,
      );

  Set<String> get _activeVehicleIds => _fleet.map((r) => r.vehicle.id).toSet();

  List<String> get _partnerNames {
    final names = _bundle.drivers.map((d) => d.partnerName).where((n) => n.isNotEmpty).toSet().toList();
    names.sort();
    return names;
  }

  List<FleetDriverStat> get _visible {
    final list = _bundle.filtered(
      filter: _filter,
      partnerName: _partnerFilter,
      maviQuery: _maviSearch.text,
      activeVehicleIds: _activeVehicleIds,
    );
    return FleetDriverStatsBundle.sorted(list, _sort);
  }

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
        title: const Text('MAVI rute-statistikk'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : _body(),
    );
  }

  Widget _body() {
    final b = _bundle;
    final visible = _visible;

    return ListView(
      children: [
        PartnerModernPageHeader(
          title: 'Fordeling per MAVI-bil',
          subtitle: '${b.period.periodDescription(DateTime.now())} · Snitt ${b.avgRoutesPerMavi.toStringAsFixed(1)} ruter per bil med rute',
        ),
        PartnerModernKpiGrid(
          items: [
            ('Ruter totalt', '${b.totalRoutes}'),
            ('Kunder totalt', '${b.totalCustomers}'),
            ('MAVI i flåte', '${b.activeMaviCount}'),
            ('Snitt kunder', b.avgCustomersPerMavi.toStringAsFixed(1)),
          ],
        ),
        const SizedBox(height: 12),
        PartnerModernSegmented<FleetCalendarPeriod>(
          options: FleetCalendarPeriod.values,
          selected: _period,
          labelOf: (p) => p.label,
          onSelected: (p) {
            setState(() => _period = p);
            _load();
          },
        ),
        const SizedBox(height: 12),
        _extremesPanel(b),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Filter & sortering', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context))),
        ),
        const SizedBox(height: 6),
        PartnerModernSearchBar(
          controller: _maviSearch,
          hint: 'Søk MAVI, sjåfør eller partner…',
          onChanged: (_) => setState(() {}),
          onClear: _maviSearch.text.isEmpty
              ? null
              : () {
                  _maviSearch.clear();
                  setState(() {});
                },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: FleetDriverFilterKey.values.map((f) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(f.label, style: const TextStyle(fontSize: 11)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),
        if (_partnerNames.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DropdownButtonFormField<String?>(
              initialValue: _partnerFilter,
              decoration: InputDecoration(
                labelText: 'Partner / bedrift',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle partnere')),
                ..._partnerNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
              ],
              onChanged: (v) => setState(() => _partnerFilter = v),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: FleetDriverSortKey.values.map((s) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 10)),
                  selected: _sort == s,
                  onSelected: (_) => setState(() => _sort = s),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '${visible.length} MAVI-biler',
            style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
          ),
        ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Ingen treff for valgt periode og filter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PartnerModernUi.muted(context)),
            ),
          )
        else
          ...visible.asMap().entries.map((e) => _maviRow(e.key, e.value, b)),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _extremesPanel(FleetDriverStatsBundle b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PartnerModernUi.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PartnerModernUi.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ekstremer i perioden', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: PartnerModernUi.textPrimary(context))),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _extremeTile('Flest ruter', b.mostRoutes)),
                const SizedBox(width: 8),
                Expanded(child: _extremeTile('Færrest ruter', b.leastRoutes)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _extremeTile('Flest kunder', b.mostCustomers)),
                const SizedBox(width: 8),
                Expanded(child: _extremeTile('Færrest kunder', b.leastCustomers)),
              ],
            ),
            if (b.mostFri != null) ...[
              const SizedBox(height: 8),
              _extremeTile('Mest fri', b.mostFri),
            ],
          ],
        ),
      ),
    );
  }

  Widget _extremeTile(String label, FleetDriverStat? d) {
    if (d == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: PartnerModernUi.border(context).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
          const SizedBox(height: 4),
          Text(
            d.displayMavi,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace', color: PartnerModernUi.textPrimary(context)),
          ),
          Text(
            '${d.routeCount} ruter · ${d.customerCount} kunder',
            style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _maviRow(int index, FleetDriverStat d, FleetDriverStatsBundle b) {
    final vsAvg = d.routeVsAvg;
    final fairnessLabel = vsAvg > 0.4
        ? '+${vsAvg.toStringAsFixed(1)} over snitt'
        : vsAvg < -0.4
            ? '${vsAvg.toStringAsFixed(1)} under snitt'
            : 'Nær snitt';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PartnerModernUi.surface(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PartnerModernUi.border(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context)),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayMavi,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      fontFamily: 'monospace',
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                  if (d.displayDriver != null)
                    Text(d.displayDriver!, style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context))),
                  Text(d.partnerName, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _miniStat('${d.routeCount} ruter'),
                      _miniStat('${d.customerCount} kunder'),
                      if (d.routeCount > 0) _miniStat('${d.customersPerRoute.toStringAsFixed(1)} knd/rute'),
                      if (d.friDays > 0) _miniStat('${d.friDays} fri'),
                      _miniStat(fairnessLabel),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${d.routeCount}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: PartnerModernUi.textPrimary(context))),
                Text('ruter', style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
                const SizedBox(height: 4),
                Text('${d.customerCount}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: PartnerModernUi.muted(context))),
                Text('kunder', style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(t, style: TextStyle(fontSize: 10, color: PartnerModernUi.textPrimary(context))),
    );
  }
}
