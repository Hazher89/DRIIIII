import 'package:flutter/material.dart';

import '../../core/services/partner/fleet_analytics_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_modern_ui.dart';

/// MAVI-basert rute-statistikk — rettferdig fordeling, områder, filtre og sortering.
class FleetRouteDriverStatsScreen extends StatefulWidget {
  const FleetRouteDriverStatsScreen({super.key});

  @override
  State<FleetRouteDriverStatsScreen> createState() => _FleetRouteDriverStatsScreenState();
}

class _FleetRouteDriverStatsScreenState extends State<FleetRouteDriverStatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  FleetCalendarPeriod _period = FleetCalendarPeriod.month;
  FleetDriverSortKey _driverSort = FleetDriverSortKey.routesDesc;
  FleetRegionSortKey _regionSort = FleetRegionSortKey.routesDesc;
  FleetDriverFilterKey _filter = FleetDriverFilterKey.withRoutes;
  String? _partnerFilter;
  String? _regionFilter;
  final _maviSearch = TextEditingController();

  bool _loading = true;
  String? _error;
  List<FleetPartnerVehicleRow> _fleet = [];
  List<PartnerRouteShare> _shares = [];
  List<PartnerVehicleFleetSnapshot> _snaps = [];
  List<FleetShiftDefinition> _shifts = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
    _maviSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
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
      final shifts = await PartnerService.fetchFleetShifts(cid);
      if (mounted) {
        setState(() {
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _shares = shares;
          _snaps = snaps;
          _shifts = shifts;
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
        shifts: _shifts,
      );

  Set<String> get _activeVehicleIds => _fleet.map((r) => r.vehicle.id).toSet();

  List<String> get _partnerNames {
    final names = _bundle.drivers.map((d) => d.partnerName).where((n) => n.isNotEmpty).toSet().toList();
    names.sort();
    return names;
  }

  List<String> get _regionNames {
    final names = _bundle.regions.map((r) => r.region).toList();
    names.sort();
    return names;
  }

  List<FleetDriverStat> get _visibleDrivers {
    var list = _bundle.filtered(
      filter: _filter,
      partnerName: _partnerFilter,
      maviQuery: _maviSearch.text,
      activeVehicleIds: _activeVehicleIds,
    );
    if (_regionFilter != null) {
      list = list.where((d) => (d.routesByRegion[_regionFilter!] ?? 0) > 0).toList();
    }
    return FleetDriverStatsBundle.sorted(list, _driverSort);
  }

  List<FleetRegionStat> get _visibleRegions =>
      FleetDriverStatsBundle.sortedRegions(_bundle.regions, _regionSort);

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
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Sjåfører'),
            Tab(text: 'Områder'),
            Tab(text: 'Rettferdighet'),
          ],
        ),
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
              : Column(
                  children: [
                    _headerPanel(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _driversTab(),
                          _regionsTab(),
                          _fairnessTab(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _headerPanel() {
    final b = _bundle;
    return Material(
      color: PartnerModernUi.surface(context),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Fordeling per MAVI · ${b.period.periodDescription(DateTime.now())}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: PartnerModernUi.textPrimary(context)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kpiChip('Ruter', '${b.totalRoutes}', Icons.route_outlined),
                _kpiChip('Kunder', '${b.totalCustomers}', Icons.people_outline),
                _kpiChip('Snitt ruter', b.avgRoutesPerMavi.toStringAsFixed(1), Icons.trending_flat),
                _kpiChip('Snitt kunder', b.avgCustomersPerMavi.toStringAsFixed(1), Icons.person_outline),
                if (b.mostActiveRegion != null)
                  _kpiChip(
                    'Mest kjørt',
                    b.mostActiveRegion!.region,
                    Icons.map_outlined,
                    subtitle: '${b.mostActiveRegion!.routeCount} ruter',
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: PartnerModernSegmented<FleetCalendarPeriod>(
              options: FleetCalendarPeriod.values,
              selected: _period,
              labelOf: (p) => p.label,
              onSelected: (p) {
                setState(() => _period = p);
                _load();
              },
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _kpiChip(String label, String value, IconData icon, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: PartnerModernUi.muted(context)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
              Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: PartnerModernUi.textPrimary(context))),
              if (subtitle != null)
                Text(subtitle, style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterBar({required bool showRegionFilter, required List<Widget> sortChips}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PartnerModernSearchBar(
          controller: _maviSearch,
          hint: 'Søk MAVI, sjåfør, partner eller område…',
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: DropdownButtonFormField<String?>(
              initialValue: _partnerFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Partner',
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
        if (showRegionFilter && _regionNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: DropdownButtonFormField<String?>(
              initialValue: _regionFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Område / skiftregion',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle områder')),
                ..._regionNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
              ],
              onChanged: (v) => setState(() => _regionFilter = v),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Sortering', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context))),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: sortChips),
        ),
      ],
    );
  }

  Widget _driversTab() {
    final visible = _visibleDrivers;
    return ListView(
      children: [
        _filterBar(
          showRegionFilter: true,
          sortChips: FleetDriverSortKey.values
              .map(
                (s) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s.label, style: const TextStyle(fontSize: 10)),
                    selected: _driverSort == s,
                    onSelected: (_) => setState(() => _driverSort = s),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              )
              .toList(),
        ),
        _extremesPanel(_bundle),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '${visible.length} sjåfører · sortert: ${_driverSort.label}',
            style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
          ),
        ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Ingen treff.', textAlign: TextAlign.center, style: TextStyle(color: PartnerModernUi.muted(context))),
          )
        else
          ...visible.asMap().entries.map((e) => _driverCard(e.key, e.value, _bundle)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _regionsTab() {
    final visible = _visibleRegions;
    return ListView(
      children: [
        _filterBar(
          showRegionFilter: false,
          sortChips: FleetRegionSortKey.values
              .map(
                (s) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s.label, style: const TextStyle(fontSize: 10)),
                    selected: _regionSort == s,
                    onSelected: (_) => setState(() => _regionSort = s),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              )
              .toList(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Hvem har kjørt mest hvor — ${visible.length} områder',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context)),
          ),
        ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Ingen områdedata i perioden (trenger skift på rutene).',
              textAlign: TextAlign.center,
              style: TextStyle(color: PartnerModernUi.muted(context)),
            ),
          )
        else
          ...visible.map(_regionCard),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fairnessTab() {
    final b = _bundle;
    final withRoutes = b.drivers.where((d) => d.routeCount > 0).toList();
    final spread = FleetDriverStatsBundle.sorted(withRoutes, FleetDriverSortKey.fairnessDesc);
    final under = FleetDriverStatsBundle.sorted(withRoutes, FleetDriverSortKey.fairnessAsc);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Rettferdig fordeling',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: PartnerModernUi.textPrimary(context)),
        ),
        const SizedBox(height: 6),
        Text(
          'Snitt ${b.avgRoutesPerMavi.toStringAsFixed(1)} ruter og ${b.avgCustomersPerMavi.toStringAsFixed(1)} kunder per sjåfør med rute i perioden.',
          style: TextStyle(fontSize: 12, height: 1.4, color: PartnerModernUi.muted(context)),
        ),
        const SizedBox(height: 16),
        _fairnessSection('Mest over snitt (ruter)', spread.take(8).toList(), positive: true),
        const SizedBox(height: 12),
        _fairnessSection('Mest under snitt (ruter)', under.take(8).toList(), positive: false),
        const SizedBox(height: 16),
        _fairnessSection(
          'Mest over snitt (kunder)',
          FleetDriverStatsBundle.sorted(withRoutes, FleetDriverSortKey.customerFairnessDesc).take(8).toList(),
          positive: true,
          useCustomers: true,
        ),
        const SizedBox(height: 12),
        _fairnessSection(
          'Mest under snitt (kunder)',
          FleetDriverStatsBundle.sorted(withRoutes, FleetDriverSortKey.customerFairnessAsc).take(8).toList(),
          positive: false,
          useCustomers: true,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fairnessSection(String title, List<FleetDriverStat> list, {required bool positive, bool useCustomers = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: PartnerModernUi.textPrimary(context))),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Text('Ingen data', style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)))
          else
            ...list.map((d) {
              final delta = useCustomers ? d.customerVsAvg : d.routeVsAvg;
              final label = delta > 0
                  ? '+${delta.toStringAsFixed(1)}'
                  : delta.toStringAsFixed(1);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(d.displayMavi, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                subtitle: Text('${d.routeCount} ruter · ${d.customerCount} kunder · ${d.topRegion ?? "—"}'),
                trailing: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: positive ? Colors.orange.shade800 : Colors.green.shade800,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _regionCard(FleetRegionStat r) {
    final pctRoutes = _bundle.totalRoutes > 0 ? (r.routeCount / _bundle.totalRoutes * 100) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
            Row(
              children: [
                Expanded(
                  child: Text(r.region, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: PartnerModernUi.textPrimary(context))),
                ),
                Text('${pctRoutes.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w700, color: PartnerModernUi.muted(context))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _miniStat('${r.routeCount} ruter'),
                _miniStat('${r.customerCount} kunder'),
                _miniStat('${r.driverCount} sjåfører'),
              ],
            ),
            if (r.topDriverMavi != null) ...[
              const SizedBox(height: 8),
              Text(
                'Mest her: ${r.topDriverMavi}${r.topDriverName != null ? " (${r.topDriverName})" : ""} · ${r.topDriverRoutes} ruter',
                style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
              ),
            ],
            const SizedBox(height: 8),
            ..._driversInRegion(r.region).take(5).map(
                  (d) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(d.displayMavi, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                        Text('${d.routesByRegion[r.region] ?? 0} r · ${d.customersByRegion[r.region] ?? 0} k', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  List<FleetDriverStat> _driversInRegion(String region) {
    final list = _bundle.drivers.where((d) => (d.routesByRegion[region] ?? 0) > 0).toList()
      ..sort((a, b) => (b.routesByRegion[region] ?? 0).compareTo(a.routesByRegion[region] ?? 0));
    return list;
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
            Text('Ekstremer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: PartnerModernUi.textPrimary(context))),
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
            if (b.mostActiveRegion != null) ...[
              const SizedBox(height: 8),
              _extremeRegionTile(b.mostActiveRegion!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _extremeRegionTile(FleetRegionStat r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PartnerModernUi.border(context).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mest kjørt område', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
          const SizedBox(height: 4),
          Text(r.region, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: PartnerModernUi.textPrimary(context))),
          Text('${r.routeCount} ruter · ${r.customerCount} kunder · topp ${r.topDriverMavi ?? "—"}', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
        ],
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
          Text(d.displayMavi, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace', color: PartnerModernUi.textPrimary(context))),
          Text('${d.routeCount} ruter · ${d.customerCount} kunder', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
        ],
      ),
    );
  }

  Widget _driverCard(int index, FleetDriverStat d, FleetDriverStatsBundle b) {
    final vsAvg = d.routeVsAvg;
    final fairnessLabel = vsAvg > 0.4
        ? '+${vsAvg.toStringAsFixed(1)} ruter over snitt'
        : vsAvg < -0.4
            ? '${vsAvg.toStringAsFixed(1)} ruter under snitt'
            : 'Nær snitt (ruter)';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text('${index + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context))),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.displayMavi, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'monospace', color: PartnerModernUi.textPrimary(context))),
                      if (d.displayDriver != null) Text(d.displayDriver!, style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context))),
                      Text(d.partnerName, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${d.routeCount}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: PartnerModernUi.textPrimary(context))),
                    Text('ruter', style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
                    Text('${d.customerCount} kunder', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _miniStat(fairnessLabel),
                if (d.topRegion != null) _miniStat('Topp: ${d.topRegion}'),
                if (d.friDays > 0) _miniStat('${d.friDays} fri'),
                _miniStat('${d.customersPerRoute.toStringAsFixed(1)} knd/rute'),
              ],
            ),
            if (d.routesByRegion.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Områder', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: PartnerModernUi.muted(context))),
              const SizedBox(height: 4),
              ...() {
                final entries = d.routesByRegion.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                return entries.take(6).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(e.key, style: TextStyle(fontSize: 11, color: PartnerModernUi.textPrimary(context)))),
                        Text('${e.value} r · ${d.customersByRegion[e.key] ?? 0} k', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
                      ],
                    ),
                  ),
                );
              }(),
            ],
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
