import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/fleet_analytics_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/mavi_driver_day_assignment.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_modern_ui.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// MAVI-statistikk — diagrammer, KPI og sjåføroversikt med drill-down.
class FleetRouteDriverStatsScreen extends StatefulWidget {
  const FleetRouteDriverStatsScreen({super.key});

  @override
  State<FleetRouteDriverStatsScreen> createState() =>
      _FleetRouteDriverStatsScreenState();
}

class _FleetRouteDriverStatsScreenState
    extends State<FleetRouteDriverStatsScreen> {
  FleetCalendarPeriod _period = FleetCalendarPeriod.month;
  FleetDriverSortKey _driverSort = FleetDriverSortKey.customersDesc;
  FleetDriverFilterKey _filter = FleetDriverFilterKey.withRoutes;
  String? _partnerFilter;
  String? _regionFilter;
  String? _vehicleFilter;
  final _maviSearch = TextEditingController();

  late DateTime _fromDay;
  late DateTime _toDay;
  int _selectedYear;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<FleetPartnerVehicleRow> _fleet = [];
  List<PartnerRouteShare> _shares = [];
  List<PartnerVehicleFleetSnapshot> _snaps = [];
  List<FleetShiftDefinition> _shifts = [];
  List<MaviDriverDayAssignment> _dayAssignments = [];

  static const _sortKeys = [
    FleetDriverSortKey.customersDesc,
    FleetDriverSortKey.kmDesc,
    FleetDriverSortKey.routesDesc,
    FleetDriverSortKey.friDesc,
    FleetDriverSortKey.customersAsc,
    FleetDriverSortKey.kmAsc,
    FleetDriverSortKey.routesAsc,
    FleetDriverSortKey.fairnessDesc,
    FleetDriverSortKey.fairnessAsc,
    FleetDriverSortKey.customerFairnessDesc,
    FleetDriverSortKey.customersPerRouteDesc,
    FleetDriverSortKey.maviAsc,
    FleetDriverSortKey.partnerAsc,
  ];

  static const _roleFilters = [
    FleetDriverFilterKey.all,
    FleetDriverFilterKey.withRoutes,
    FleetDriverFilterKey.withCustomers,
    FleetDriverFilterKey.withKm,
    FleetDriverFilterKey.friOnly,
    FleetDriverFilterKey.enmannsbil,
    FleetDriverFilterKey.tomannsbil,
    FleetDriverFilterKey.intern,
    FleetDriverFilterKey.tjenestebil,
    FleetDriverFilterKey.onlyActiveMavi,
  ];

  static const _accent = Color(0xFF2E7D32);
  static const _accentSoft = Color(0xFFE8F5E9);
  static const _blue = Color(0xFF1565C0);
  static const _amber = Color(0xFFF9A825);
  static const _orange = Color(0xFFEF6C00);
  static const _purple = Color(0xFF6A1B9A);
  static const _teal = Color(0xFF00897B);

  _FleetRouteDriverStatsScreenState() : _selectedYear = DateTime.now().year {
    final now = DateTime.now();
    _fromDay = DateTime(now.year, now.month, 1);
    _toDay = DateTime(now.year, now.month, now.day);
  }

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

  void _applyPreset(FleetCalendarPeriod p) {
    final now = DateTime.now();
    setState(() {
      _period = p;
      _selectedYear = now.year;
      switch (p) {
        case FleetCalendarPeriod.day:
          _fromDay = DateTime(now.year, now.month, now.day);
          _toDay = _fromDay;
          break;
        case FleetCalendarPeriod.week:
          _fromDay = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _toDay = DateTime(now.year, now.month, now.day);
          break;
        case FleetCalendarPeriod.month:
          _fromDay = DateTime(now.year, now.month, 1);
          _toDay = DateTime(now.year, now.month, now.day);
          break;
        case FleetCalendarPeriod.year:
          _fromDay = DateTime(now.year, 1, 1);
          _toDay = DateTime(now.year, now.month, now.day);
          break;
      }
    });
    _load(light: true);
  }

  void _applyYear(int year) {
    final now = DateTime.now();
    final end = year == now.year
        ? DateTime(now.year, now.month, now.day)
        : DateTime(year, 12, 31);
    setState(() {
      _selectedYear = year;
      _period = FleetCalendarPeriod.year;
      _fromDay = DateTime(year, 1, 1);
      _toDay = end;
    });
    _load(light: true);
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDay,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('nb'),
      helpText: 'Fra og med',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fromDay = DateTime(picked.year, picked.month, picked.day);
      if (_fromDay.isAfter(_toDay)) _toDay = _fromDay;
      _period = FleetCalendarPeriod.month;
    });
    await _load(light: true);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDay.isBefore(_fromDay) ? _fromDay : _toDay,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('nb'),
      helpText: 'Til og med',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _toDay = DateTime(picked.year, picked.month, picked.day);
      if (_toDay.isBefore(_fromDay)) _fromDay = _toDay;
      _period = FleetCalendarPeriod.month;
    });
    await _load(light: true);
  }

  /// [light] = behold UI synlig under lasting (unngår grå fullskjerm).
  Future<void> _load({bool light = false}) async {
    final keep = light && _fleet.isNotEmpty;
    setState(() {
      if (keep) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final fleet = await PartnerService.fetchCompanyFleet(cid, forPlanning: false);
      final shares = await PartnerService.fetchRouteSharesForCalendarWindow(
        companyId: cid,
        fromDay: _fromDay,
        toDay: _toDay,
        includePdfSearchText: true,
        limitPerQuery: 15000,
      );
      final snaps = await PartnerService.fetchFleetSnapshotsRange(
        companyId: cid,
        from: _fromDay,
        to: _toDay,
      );
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final assignments = await PartnerService.fetchMaviDayAssignments(
        companyId: cid,
        from: _fromDay,
        to: _toDay,
      );
      if (mounted) {
        setState(() {
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _shares = shares;
          _snaps = snaps;
          _shifts = shifts;
          _dayAssignments = assignments;
          _loading = false;
          _refreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
          _refreshing = false;
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
        dayAssignments: _dayAssignments,
        fromDay: _fromDay,
        toDay: _toDay,
      );

  Set<String> get _activeVehicleIds => _fleet.map((r) => r.vehicle.id).toSet();

  List<String> get _partnerNames {
    final names =
        _bundle.drivers.map((d) => d.partnerName).where((n) => n.isNotEmpty).toSet().toList();
    names.sort();
    return names;
  }

  List<String> get _regionNames {
    final names = _bundle.regions.map((r) => r.region).toList();
    names.sort();
    return names;
  }

  List<FleetDriverStat> get _vehicleOptions {
    final list = [..._bundle.drivers]
      ..sort((a, b) => a.displayMavi.compareTo(b.displayMavi));
    return list;
  }

  List<FleetDriverStat> get _visibleDrivers {
    var list = _bundle.filtered(
      filter: _filter,
      partnerName: _partnerFilter,
      maviQuery: _maviSearch.text,
      activeVehicleIds: _activeVehicleIds,
      onlyVehicleIds: _vehicleFilter == null ? null : {_vehicleFilter!},
    );
    if (_regionFilter != null) {
      list = list.where((d) => (d.routesByRegion[_regionFilter!] ?? 0) > 0).toList();
    }
    return FleetDriverStatsBundle.sorted(list, _driverSort);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1419) : const Color(0xFFEEF1F4);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: PartnerModernUi.surface(context),
        foregroundColor: PartnerModernUi.textPrimary(context),
        title: const Text('MAVI-statistikk'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Oppdater',
            onPressed: (_loading || _refreshing) ? null : () => _load(light: true),
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _error != null && _fleet.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(light: true),
                  color: _accent,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          ),
                        ),
                      _filterToolbar(),
                      const SizedBox(height: 8),
                      Text(
                        'Trykk på tall, diagram eller sjåfør for mer info.',
                        style: TextStyle(
                          fontSize: 12,
                          color: PartnerModernUi.muted(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _kpiStrip(),
                      const SizedBox(height: 12),
                      _pieCardsRow(),
                      const SizedBox(height: 12),
                      _chartsRow(),
                      const SizedBox(height: 12),
                      _leaderboards(),
                      const SizedBox(height: 12),
                      _driversHeader(),
                      ..._visibleDrivers.asMap().entries.map(
                            (e) => _driverCard(e.key, e.value),
                          ),
                      if (_visibleDrivers.isEmpty)
                        _emptyBox(
                          _refreshing
                              ? 'Henter data…'
                              : 'Ingen sjåfører matcher filteret i perioden.',
                        ),
                      const SizedBox(height: 16),
                      _regionsSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _filterToolbar() {
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Periode · ${_bundle.rangeLabel}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
              ),
              Text(
                '${_shares.length} PDF-ruter lastet',
                style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Km, kunder og vekt leses fra Trip Overview i PDF. Fri hentes fra flåtestatus/skift.',
            style: TextStyle(fontSize: 11, height: 1.35, color: PartnerModernUi.muted(context)),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _presetChip('I dag', FleetCalendarPeriod.day),
                _presetChip('Uke', FleetCalendarPeriod.week),
                _presetChip('Måned', FleetCalendarPeriod.month),
                _presetChip('År', FleetCalendarPeriod.year),
                const SizedBox(width: 8),
                ...[2024, 2025, 2026].map((y) {
                  final sel = _selectedYear == y && _period == FleetCalendarPeriod.year;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('$y', style: const TextStyle(fontSize: 11)),
                      selected: sel,
                      onSelected: (_) => _applyYear(y),
                      visualDensity: VisualDensity.compact,
                      selectedColor: _accent.withValues(alpha: 0.22),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _dateButton('Fra og med', df.format(_fromDay), _pickFrom),
              _dateButton('Til og med', df.format(_toDay), _pickTo),
              FilledButton.icon(
                onPressed: (_loading || _refreshing)
                    ? null
                    : () => _load(light: true),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Oppdater'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _maviSearch,
            decoration: InputDecoration(
              hintText: 'Søk MAVI, sjåfør, partner…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: PartnerModernUi.border(context).withValues(alpha: 0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: PartnerModernUi.border(context)),
              ),
              suffixIcon: _maviSearch.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _maviSearch.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _roleFilters.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(f.label, style: const TextStyle(fontSize: 11)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    selectedColor: _accentSoft,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_partnerNames.length > 1)
                _dropdown<String?>(
                  label: 'Partner',
                  value: _partnerFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle partnere')),
                    ..._partnerNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                  ],
                  onChanged: (v) => setState(() => _partnerFilter = v),
                ),
              if (_regionNames.isNotEmpty)
                _dropdown<String?>(
                  label: 'Område',
                  value: _regionFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle områder')),
                    ..._regionNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                  ],
                  onChanged: (v) => setState(() => _regionFilter = v),
                ),
              _dropdown<String?>(
                label: 'Sjåfør / MAVI',
                value: _vehicleFilter,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Alle sjåfører')),
                  ..._vehicleOptions.map(
                    (d) => DropdownMenuItem(
                      value: d.vehicleId,
                      child: Text(
                        '${d.displayMavi}${d.displayDriver != null ? ' · ${d.displayDriver}' : ''}',
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _vehicleFilter = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sortering',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PartnerModernUi.muted(context),
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sortKeys
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s.label, style: const TextStyle(fontSize: 10)),
                        selected: _driverSort == s,
                        onSelected: (_) => setState(() => _driverSort = s),
                        visualDensity: VisualDensity.compact,
                        selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, FleetCalendarPeriod p) {
    final selected = _period == p &&
        (p != FleetCalendarPeriod.year || _selectedYear == DateTime.now().year);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => _applyPreset(p),
        visualDensity: VisualDensity.compact,
        selectedColor: _accent.withValues(alpha: 0.22),
      ),
    );
  }

  Widget _dateButton(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PartnerModernUi.border(context)),
          color: PartnerModernUi.surface(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_outlined, size: 16, color: PartnerModernUi.muted(context)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context))),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<T>(
        key: ValueKey<Object?>('$label|$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _kpiStrip() {
    final b = _bundle;
    final visible = _visibleDrivers;
    final routes = visible.fold<int>(0, (a, d) => a + d.routeCount);
    final cust = visible.fold<int>(0, (a, d) => a + d.customerCount);
    final km = visible.fold<double>(0, (a, d) => a + d.totalKm);
    final fri = visible.fold<int>(0, (a, d) => a + d.friDays);
    final kg = visible.fold<double>(0, (a, d) => a + d.totalWeightKg);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _kpiTile(
          'Ruter',
          '$routes',
          Icons.route_outlined,
          _accent,
          onTap: () => _showMetricSheet(
            title: 'Ruter i perioden',
            body:
                '$routes ruter totalt for ${visible.length} sjåfører.\n'
                'Snitt: ${b.avgRoutesPerMavi.toStringAsFixed(1)} ruter per MAVI.\n'
                'Tallene kommer fra sendte/registrerte rute-PDF-er i valgt datoperiode.',
            drivers: [...visible]..sort((a, c) => c.routeCount.compareTo(a.routeCount)),
            valueOf: (d) => '${d.routeCount} ruter',
          ),
        ),
        _kpiTile(
          'Kunder',
          '$cust',
          Icons.people_outline,
          _blue,
          onTap: () => _showMetricSheet(
            title: 'Kunder i perioden',
            body:
                '$cust kunder totalt.\n'
                'Snitt: ${b.avgCustomersPerMavi.toStringAsFixed(1)} kunder per MAVI.\n'
                'Kundenantall hentes fra rute-PDF (stopp / Trip Overview).',
            drivers: [...visible]..sort((a, c) => c.customerCount.compareTo(a.customerCount)),
            valueOf: (d) => '${d.customerCount} kunder',
          ),
        ),
        _kpiTile(
          'Km (PDF)',
          km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k' : km.toStringAsFixed(0),
          Icons.straighten,
          _orange,
          onTap: () => _showMetricSheet(
            title: 'Kilometer (fra PDF)',
            body:
                '${km.toStringAsFixed(0)} km totalt fra «Total distance» i rute-PDF.\n'
                'Kun ruter der PDF har km-felt telles. Mangler felt = 0 for den ruta.',
            drivers: [...visible]..sort((a, c) => c.totalKm.compareTo(a.totalKm)),
            valueOf: (d) => '${d.totalKm.toStringAsFixed(0)} km',
          ),
        ),
        _kpiTile(
          'Fri-dager',
          '$fri',
          Icons.beach_access_outlined,
          _purple,
          onTap: () => _showMetricSheet(
            title: 'Fri-dager',
            body: '$fri fri-dager i perioden (fra flåte-status / dagskalender).',
            drivers: [...visible.where((d) => d.friDays > 0)]
              ..sort((a, c) => c.friDays.compareTo(a.friDays)),
            valueOf: (d) => '${d.friDays} fri',
          ),
        ),
        _kpiTile(
          'Vekt (t)',
          (kg / 1000).toStringAsFixed(1),
          Icons.scale_outlined,
          _teal,
          onTap: () => _showMetricSheet(
            title: 'Vekt (fra PDF)',
            body:
                '${(kg / 1000).toStringAsFixed(1)} tonn totalt fra «Consumed Weight» i PDF når feltet finnes.',
            drivers: [...visible]..sort((a, c) => c.totalWeightKg.compareTo(a.totalWeightKg)),
            valueOf: (d) => '${(d.totalWeightKg / 1000).toStringAsFixed(1)} t',
          ),
        ),
        _kpiTile(
          'MAVI',
          '${visible.length}',
          Icons.local_shipping_outlined,
          _amber,
          onTap: () => _showMetricSheet(
            title: 'Sjåfører i utvalget',
            body:
                '${visible.length} MAVI matcher filter og periode.\n'
                'Trykk en sjåfør i listen under for full detalj.',
            drivers: visible,
            valueOf: (d) =>
                '${d.routeCount} r · ${d.customerCount} k · ${d.totalKm.toStringAsFixed(0)} km',
          ),
        ),
        if (b.mostCustomers != null)
          _kpiTile(
            'Flest kunder',
            b.mostCustomers!.displayMavi,
            Icons.emoji_events_outlined,
            _blue,
            subtitle: '${b.mostCustomers!.customerCount} kunder',
            onTap: () => _showDriverDetail(b.mostCustomers!),
          ),
        if (b.mostKm != null)
          _kpiTile(
            'Lengst kjørt',
            b.mostKm!.displayMavi,
            Icons.speed_outlined,
            _orange,
            subtitle: '${b.mostKm!.totalKm.toStringAsFixed(0)} km',
            onTap: () => _showDriverDetail(b.mostKm!),
          ),
        if (b.mostFri != null)
          _kpiTile(
            'Mest fri',
            b.mostFri!.displayMavi,
            Icons.wb_sunny_outlined,
            _purple,
            subtitle: '${b.mostFri!.friDays} dager',
            onTap: () => _showDriverDetail(b.mostFri!),
          ),
      ],
    );
  }

  Widget _kpiTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: PartnerModernUi.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 118),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PartnerModernUi.border(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pieCardsRow() {
    final visible = _visibleDrivers;
    final withRoute = visible.where((d) => d.routeCount > 0).length;
    final withKm = visible.where((d) => d.totalKm > 0).length;
    final withFri = visible.where((d) => d.friDays > 0).length;
    final total = visible.isEmpty ? 1 : visible.length;

    final topCust = [...visible]..sort((a, b) => b.customerCount.compareTo(a.customerCount));
    final top5Cust = topCust.take(5).where((d) => d.customerCount > 0).toList();
    final restCust = visible.fold<int>(0, (a, d) => a + d.customerCount) -
        top5Cust.fold<int>(0, (a, d) => a + d.customerCount);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final cards = [
          _donutCard(
            title: 'Dekning rute',
            center: '${((withRoute / total) * 100).round()}%',
            subtitle: '$withRoute av ${visible.length} med rute',
            sections: [
              _Slice('Med rute', withRoute.toDouble(), _accent),
              _Slice('Uten', (total - withRoute).toDouble().clamp(0, 1e9), Colors.blueGrey.shade200),
            ],
          ),
          _donutCard(
            title: 'Km i PDF',
            center: '${((withKm / total) * 100).round()}%',
            subtitle: '$withKm med Total distance',
            sections: [
              _Slice('Har km', withKm.toDouble(), _orange),
              _Slice('Mangler', (total - withKm).toDouble().clamp(0, 1e9), Colors.blueGrey.shade200),
            ],
          ),
          _donutCard(
            title: 'Fri i perioden',
            center: '$withFri',
            subtitle: 'sjåfører med fri-dager',
            sections: [
              _Slice('Fri', withFri.toDouble().clamp(0.01, 1e9), _purple),
              _Slice('Øvrige', (total - withFri).toDouble().clamp(0.01, 1e9), Colors.blueGrey.shade200),
            ],
          ),
          _donutCard(
            title: 'Kunder (topp 5)',
            center: '${top5Cust.fold<int>(0, (a, d) => a + d.customerCount)}',
            subtitle: 'vs øvrige $restCust',
            sections: [
              for (var i = 0; i < top5Cust.length; i++)
                _Slice(
                  top5Cust[i].displayMavi,
                  top5Cust[i].customerCount.toDouble(),
                  [_blue, _accent, _teal, _amber, _orange][i % 5],
                ),
              if (restCust > 0) _Slice('Øvrige', restCust.toDouble(), Colors.blueGrey.shade200),
            ],
          ),
        ];
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += 2)
              Padding(
                padding: EdgeInsets.only(bottom: i + 2 < cards.length ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[i]),
                    if (i + 1 < cards.length) ...[
                      const SizedBox(width: 10),
                      Expanded(child: cards[i + 1]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _donutCard({
    required String title,
    required String center,
    required String subtitle,
    required List<_Slice> sections,
  }) {
    final total = sections.fold<double>(0, (a, s) => a + s.value);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: total <= 0
                        ? [
                            PieChartSectionData(
                              value: 1,
                              color: Colors.blueGrey.shade100,
                              title: '',
                              radius: 40,
                            ),
                          ]
                        : sections
                            .where((s) => s.value > 0)
                            .map(
                              (s) => PieChartSectionData(
                                value: s.value,
                                color: s.color,
                                title: '',
                                radius: 42,
                              ),
                            )
                            .toList(),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(subtitle, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
          const SizedBox(height: 6),
          ...sections.where((s) => s.value > 0).take(4).map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: PartnerModernUi.textPrimary(context)),
                        ),
                      ),
                      Text(
                        s.value >= 100 ? s.value.toStringAsFixed(0) : s.value.toStringAsFixed(s.value == s.value.roundToDouble() ? 0 : 1),
                        style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _chartsRow() {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final left = _kmBarCard();
        final right = _trendCard();
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 10),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          children: [
            left,
            const SizedBox(height: 10),
            right,
          ],
        );
      },
    );
  }

  Widget _kmBarCard() {
    final top = [..._visibleDrivers]
      ..sort((a, b) => b.totalKm.compareTo(a.totalKm));
    final rows = top.where((d) => d.totalKm > 0).take(10).toList();
    if (rows.isEmpty) {
      return _card(
        child: Text(
          'Ingen km i PDF for valgt filter/periode.',
          style: TextStyle(color: PartnerModernUi.muted(context)),
        ),
      );
    }
    final maxY = rows.map((d) => d.totalKm).reduce((a, b) => a > b ? a : b);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Topp 10 · km fra PDF',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total distance i Trip Overview',
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.15,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final d = rows[group.x.toInt()];
                      return BarTooltipItem(
                        '${d.displayMavi}\n${d.totalKm.toStringAsFixed(0)} km',
                        const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) => Text(
                        v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0),
                        style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= rows.length) return const SizedBox.shrink();
                        final label = rows[i].displayMavi.replaceFirst(RegExp(r'^NO_[A-Z]_'), '');
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: PartnerModernUi.border(context),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: rows[i].totalKm,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          color: _orange,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendCard() {
    final trend = _bundle.dailyTrend;
    if (trend.isEmpty) {
      return _card(
        child: Text(
          'Ingen dagsdata i perioden.',
          style: TextStyle(color: PartnerModernUi.muted(context)),
        ),
      );
    }
    final maxY = trend
        .map((p) => [p.routesSent, p.fri].reduce((a, b) => a > b ? a : b))
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble()
        .clamp(1, 1e9);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trend · ruter og fri',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Per dag i valgt periode',
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.2,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final day = trend[s.x.toInt()].day;
                      final label = s.barIndex == 0 ? 'Ruter' : 'Fri';
                      return LineTooltipItem(
                        '${day.day}.${day.month}: $label ${s.y.toStringAsFixed(0)}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      );
                    }).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (trend.length / 6).clamp(1, 30).toDouble(),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                        final d = trend[i].day;
                        return Text(
                          '${d.day}.${d.month}',
                          style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: PartnerModernUi.border(context),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < trend.length; i++)
                        FlSpot(i.toDouble(), trend[i].routesSent.toDouble()),
                    ],
                    isCurved: true,
                    color: _accent,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _accent.withValues(alpha: 0.12),
                    ),
                  ),
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < trend.length; i++)
                        FlSpot(i.toDouble(), trend[i].fri.toDouble()),
                    ],
                    isCurved: true,
                    color: _purple,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(_accent, 'Ruter'),
              const SizedBox(width: 12),
              _legendDot(_purple, 'Fri'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
      ],
    );
  }

  Widget _leaderboards() {
    final visible = _visibleDrivers;
    List<FleetDriverStat> top(FleetDriverSortKey key, bool Function(FleetDriverStat) pred) {
      return FleetDriverStatsBundle.sorted(visible.where(pred).toList(), key).take(5).toList();
    }

    final boards = [
      _board('Flest kunder', top(FleetDriverSortKey.customersDesc, (d) => d.customerCount > 0),
          (d) => '${d.customerCount} knd', _blue),
      _board('Lengst kjørt', top(FleetDriverSortKey.kmDesc, (d) => d.totalKm > 0),
          (d) => '${d.totalKm.toStringAsFixed(0)} km', _orange),
      _board('Flest ruter', top(FleetDriverSortKey.routesDesc, (d) => d.routeCount > 0),
          (d) => '${d.routeCount} ruter', _accent),
      _board('Mest fri', top(FleetDriverSortKey.friDesc, (d) => d.friDays > 0),
          (d) => '${d.friDays} dager', _purple),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < boards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: boards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < boards.length; i += 2)
              Padding(
                padding: EdgeInsets.only(bottom: i + 2 < boards.length ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: boards[i]),
                    if (i + 1 < boards.length) ...[
                      const SizedBox(width: 10),
                      Expanded(child: boards[i + 1]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _board(
    String title,
    List<FleetDriverStat> rows,
    String Function(FleetDriverStat) metric,
    Color color,
  ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: PartnerModernUi.textPrimary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text('Ingen data', style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)))
          else
            ...rows.asMap().entries.map((e) {
              final d = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _showDriverDetail(d),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Text(
                            '${e.key + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: PartnerModernUi.muted(context),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.displayMavi,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: PartnerModernUi.textPrimary(context),
                                ),
                              ),
                              Text(
                                d.partnerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: PartnerModernUi.muted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          metric(d),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _driversHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          Text(
            'Sjåfører',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const Spacer(),
          Text(
            '${_visibleDrivers.length} · ${_driverSort.label}',
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _driverCard(int index, FleetDriverStat d) {
    final b = _bundle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showDriverDetail(d),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PartnerModernUi.border(context)),
            ),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _accent.withValues(alpha: 0.15),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.displayMavi,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          fontFamily: 'monospace',
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                      if (d.displayDriver != null)
                        Text(
                          d.displayDriver!,
                          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                        ),
                      Text(
                        d.partnerName,
                        style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${d.customerCount}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                    ),
                    Text('kunder', style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _statPill('${d.routeCount} ruter', _accent),
                _statPill('${d.totalKm.toStringAsFixed(0)} km', _orange),
                if (d.totalWeightKg > 0)
                  _statPill('${(d.totalWeightKg / 1000).toStringAsFixed(1)} t', _teal),
                if (d.friDays > 0) _statPill('${d.friDays} fri', _purple),
                _statPill('${d.customersPerRoute.toStringAsFixed(1)} knd/rute', _blue),
                _statPill(d.fleetRolesLabel, Colors.blueGrey),
                if (d.topRegion != null) _statPill(d.topRegion!, Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${d.routeVsAvg >= 0 ? '+' : ''}${d.routeVsAvg.toStringAsFixed(1)} ruter · '
              '${d.customerVsAvg >= 0 ? '+' : ''}${d.customerVsAvg.toStringAsFixed(1)} kunder vs snitt '
              '(${b.avgRoutesPerMavi.toStringAsFixed(1)} / ${b.avgCustomersPerMavi.toStringAsFixed(1)})',
              style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
            ),
            if (d.routesByRegion.length > 1) ...[
              const SizedBox(height: 8),
              ...() {
                final entries = d.routesByRegion.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                return entries.take(4).map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: PartnerModernUi.textPrimary(context),
                                ),
                              ),
                            ),
                            Text(
                              '${e.value} r · ${d.customersByRegion[e.key] ?? 0} k',
                              style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                            ),
                          ],
                        ),
                      ),
                    );
              }(),
            ],
            const SizedBox(height: 6),
            Text(
              'Trykk for full detalj →',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statPill(String t, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.95)),
      ),
    );
  }

  Widget _regionsSection() {
    final regions = FleetDriverStatsBundle.sortedRegions(
      _bundle.regions,
      FleetRegionSortKey.routesDesc,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Områder',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: PartnerModernUi.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Fordeling av ruter per område i perioden',
          style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
        ),
        const SizedBox(height: 8),
        if (regions.isEmpty)
          _emptyBox('Ingen områdedata.')
        else
          ...regions.map((r) {
            final pct = _bundle.totalRoutes > 0 ? r.routeCount / _bundle.totalRoutes * 100 : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: PartnerModernUi.surface(context),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() => _regionFilter = r.region);
                    _showMetricSheet(
                      title: 'Område: ${r.region}',
                      body:
                          '${r.routeCount} ruter · ${r.customerCount} kunder · ${r.driverCount} sjåfører '
                          '(${pct.toStringAsFixed(0)}% av rutene i perioden).'
                          '${r.topDriverMavi != null ? '\nTopp: ${r.topDriverMavi}' : ''}\n\n'
                          'Filter er satt til dette området — se listen over.',
                      drivers: _visibleDrivers,
                      valueOf: (d) =>
                          '${d.routesByRegion[r.region] ?? 0} r · '
                          '${d.customersByRegion[r.region] ?? 0} k',
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: PartnerModernUi.border(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.region,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: PartnerModernUi.textPrimary(context),
                                ),
                              ),
                            ),
                            Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: PartnerModernUi.muted(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (pct / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: PartnerModernUi.border(context),
                            color: _accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${r.routeCount} ruter · ${r.customerCount} kunder · ${r.driverCount} sjåfører'
                          '${r.topDriverMavi != null ? ' · topp ${r.topDriverMavi}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: PartnerModernUi.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  void _showDriverDetail(FleetDriverStat d) {
    final b = _bundle;
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final regions = d.routesByRegion.entries.toList()
          ..sort((a, c) => c.value.compareTo(a.value));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    d.displayMavi,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (d.displayDriver != null)
                    Text(d.displayDriver!, style: const TextStyle(fontSize: 15)),
                  Text(
                    d.partnerName,
                    style: TextStyle(color: PartnerModernUi.muted(ctx)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${df.format(_fromDay)} – ${df.format(_toDay)}',
                    style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(ctx)),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statPill('${d.routeCount} ruter', _accent),
                      _statPill('${d.customerCount} kunder', _blue),
                      _statPill('${d.totalKm.toStringAsFixed(0)} km', _orange),
                      if (d.totalWeightKg > 0)
                        _statPill(
                          '${(d.totalWeightKg / 1000).toStringAsFixed(1)} t',
                          _teal,
                        ),
                      if (d.friDays > 0) _statPill('${d.friDays} fri', _purple),
                      _statPill(
                        '${d.customersPerRoute.toStringAsFixed(1)} kunder/rute',
                        _blue,
                      ),
                      _statPill(d.fleetRolesLabel, Colors.blueGrey),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Sammenligning mot snitt',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PartnerModernUi.textPrimary(ctx),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ruter: ${d.routeVsAvg >= 0 ? '+' : ''}${d.routeVsAvg.toStringAsFixed(1)} '
                    '(snitt ${b.avgRoutesPerMavi.toStringAsFixed(1)})\n'
                    'Kunder: ${d.customerVsAvg >= 0 ? '+' : ''}${d.customerVsAvg.toStringAsFixed(1)} '
                    '(snitt ${b.avgCustomersPerMavi.toStringAsFixed(1)})\n'
                    'Km/rute: ${d.kmPerRoute.toStringAsFixed(1)}'
                    '${d.routesWithKm > 0 ? ' · ${d.routesWithKm} ruter med km i PDF' : ''}',
                    style: const TextStyle(height: 1.4, fontSize: 13),
                  ),
                  if (regions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Områder',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: PartnerModernUi.textPrimary(ctx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...regions.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(e.key)),
                            Text(
                              '${e.value} ruter · ${d.customersByRegion[e.key] ?? 0} kunder',
                              style: TextStyle(
                                fontSize: 12,
                                color: PartnerModernUi.muted(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _vehicleFilter = d.vehicleId;
                        _filter = FleetDriverFilterKey.all;
                      });
                    },
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    child: const Text('Vis kun denne sjåføren i listen'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMetricSheet({
    required String title,
    required String body,
    required List<FleetDriverStat> drivers,
    required String Function(FleetDriverStat) valueOf,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(body, style: const TextStyle(height: 1.35, fontSize: 13)),
                  const SizedBox(height: 12),
                  Text(
                    'Sjåfører (${drivers.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PartnerModernUi.textPrimary(ctx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: drivers.isEmpty
                        ? const Center(child: Text('Ingen sjåfører i utvalget'))
                        : ListView.separated(
                            itemCount: drivers.length.clamp(0, 80),
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = drivers[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  d.displayMavi,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (d.displayDriver != null) d.displayDriver!,
                                    d.partnerName,
                                  ].whereType<String>().join(' · '),
                                ),
                                trailing: Text(
                                  valueOf(d),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showDriverDetail(d);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartnerModernUi.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _emptyBox(String text) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: PartnerModernUi.muted(context)),
      ),
    );
  }
}

class _Slice {
  final String label;
  final double value;
  final Color color;
  const _Slice(this.label, this.value, this.color);
}
