import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/fleet_analytics_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/mavi_driver_day_assignment.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_modern_ui.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// MAVI-statistikk — ryddig oversikt over alle sjåfører og tall.
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
  final _maviSearch = TextEditingController();

  late DateTime _fromDay;
  late DateTime _toDay;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<FleetPartnerVehicleRow> _fleet = [];
  List<PartnerRouteShare> _shares = [];
  List<PartnerVehicleFleetSnapshot> _snaps = [];
  List<FleetShiftDefinition> _shifts = [];
  List<MaviDriverDayAssignment> _dayAssignments = [];

  static const _accent = Color(0xFF2E7D32);
  static const _blue = Color(0xFF1565C0);
  static const _orange = Color(0xFFEF6C00);
  static const _purple = Color(0xFF6A1B9A);

  static const _sortOptions = [
    FleetDriverSortKey.customersDesc,
    FleetDriverSortKey.kmDesc,
    FleetDriverSortKey.routesDesc,
    FleetDriverSortKey.friDesc,
    FleetDriverSortKey.maviAsc,
    FleetDriverSortKey.partnerAsc,
  ];

  static const _filterOptions = [
    FleetDriverFilterKey.withRoutes,
    FleetDriverFilterKey.all,
    FleetDriverFilterKey.enmannsbil,
    FleetDriverFilterKey.tomannsbil,
    FleetDriverFilterKey.intern,
    FleetDriverFilterKey.friOnly,
  ];

  _FleetRouteDriverStatsScreenState() {
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
      switch (p) {
        case FleetCalendarPeriod.day:
          _fromDay = DateTime(now.year, now.month, now.day);
          _toDay = _fromDay;
        case FleetCalendarPeriod.week:
          _fromDay = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _toDay = DateTime(now.year, now.month, now.day);
        case FleetCalendarPeriod.month:
          _fromDay = DateTime(now.year, now.month, 1);
          _toDay = DateTime(now.year, now.month, now.day);
        case FleetCalendarPeriod.year:
          _fromDay = DateTime(now.year, 1, 1);
          _toDay = DateTime(now.year, now.month, now.day);
      }
    });
    _load(light: true);
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDay,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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

  /// [light] = behold listen synlig mens data hentes (unngår grå fullskjerm).
  Future<void> _load({bool light = false}) async {
    final keepContent = light && _fleet.isNotEmpty;
    setState(() {
      if (keepContent) {
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
    final names = _bundle.drivers
        .map((d) => d.partnerName)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return names;
  }

  List<FleetDriverStat> get _visibleDrivers {
    final list = _bundle.filtered(
      filter: _filter,
      partnerName: _partnerFilter,
      maviQuery: _maviSearch.text,
      activeVehicleIds: _activeVehicleIds,
    );
    return FleetDriverStatsBundle.sorted(list, _driverSort);
  }

  String _shortMavi(String mavi) {
    final n = mavi.replaceFirst(RegExp(r'^NO_[A-Z]_'), '');
    return n.isEmpty ? mavi : n;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1419) : const Color(0xFFF4F6F8);
    final df = DateFormat('d. MMM yyyy', 'nb_NO');

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
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: () => _load(light: true),
                  color: _accent,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          ),
                        ),
                      _periodBar(df),
                      const SizedBox(height: 12),
                      _kpiRow(),
                      const SizedBox(height: 12),
                      _controls(),
                      const SizedBox(height: 16),
                      _driversHeader(),
                      const SizedBox(height: 8),
                      if (_visibleDrivers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _refreshing
                                ? 'Henter data…'
                                : 'Ingen sjåfører i perioden.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: PartnerModernUi.muted(context)),
                          ),
                        )
                      else
                        ..._visibleDrivers.asMap().entries.map(
                              (e) => _driverRow(e.key + 1, e.value),
                            ),
                    ],
                  ),
                ),
    );
  }

  Widget _periodBar(DateFormat df) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${df.format(_fromDay)} – ${df.format(_toDay)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in [
                FleetCalendarPeriod.week,
                FleetCalendarPeriod.month,
                FleetCalendarPeriod.year,
              ])
                ChoiceChip(
                  label: Text(p.label),
                  selected: _period == p,
                  onSelected: (_loading || _refreshing)
                      ? null
                      : (_) => _applyPreset(p),
                  selectedColor: _accent.withValues(alpha: 0.2),
                  visualDensity: VisualDensity.compact,
                ),
              OutlinedButton.icon(
                onPressed: (_loading || _refreshing) ? null : _pickFrom,
                icon: const Icon(Icons.event, size: 16),
                label: Text('Fra ${df.format(_fromDay)}'),
              ),
              OutlinedButton.icon(
                onPressed: (_loading || _refreshing) ? null : _pickTo,
                icon: const Icon(Icons.event_available, size: 16),
                label: Text('Til ${df.format(_toDay)}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiRow() {
    final v = _visibleDrivers;
    final routes = v.fold<int>(0, (a, d) => a + d.routeCount);
    final cust = v.fold<int>(0, (a, d) => a + d.customerCount);
    final km = v.fold<double>(0, (a, d) => a + d.totalKm);
    final fri = v.fold<int>(0, (a, d) => a + d.friDays);

    return Row(
      children: [
        Expanded(child: _kpi('Ruter', '$routes', _accent)),
        const SizedBox(width: 8),
        Expanded(child: _kpi('Kunder', '$cust', _blue)),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi(
            'Km',
            km >= 1000 ? '${(km / 1000).toStringAsFixed(1)}k' : km.toStringAsFixed(0),
            _orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _kpi('Sjåfører', '${v.length}', _purple)),
        if (fri > 0) ...[
          const SizedBox(width: 8),
          Expanded(child: _kpi('Fri', '$fri', Colors.brown)),
        ],
      ],
    );
  }

  Widget _kpi(String label, String value, Color color) {
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return _card(
      child: Column(
        children: [
          TextField(
            controller: _maviSearch,
            decoration: InputDecoration(
              hintText: 'Søk MAVI, sjåfør eller partner…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 640;
              final filterDd = _dropdown<FleetDriverFilterKey>(
                label: 'Vis',
                value: _filter,
                items: _filterOptions
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              );
              final sortDd = _dropdown<FleetDriverSortKey>(
                label: 'Sorter',
                value: _driverSort,
                items: _sortOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _driverSort = v);
                },
              );
              final partnerDd = _dropdown<String?>(
                label: 'Partner',
                value: _partnerFilter,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Alle')),
                  ..._partnerNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                ],
                onChanged: (v) => setState(() => _partnerFilter = v),
              );
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: filterDd),
                    const SizedBox(width: 8),
                    Expanded(child: sortDd),
                    const SizedBox(width: 8),
                    Expanded(child: partnerDd),
                  ],
                );
              }
              return Column(
                children: [
                  filterDd,
                  const SizedBox(height: 8),
                  sortDd,
                  const SizedBox(height: 8),
                  partnerDd,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$label|$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _driversHeader() {
    return Row(
      children: [
        Text(
          'Alle sjåfører',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: PartnerModernUi.textPrimary(context),
          ),
        ),
        const Spacer(),
        Text(
          '${_visibleDrivers.length} stk',
          style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
        ),
      ],
    );
  }

  Widget _driverRow(int rank, FleetDriverStat d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
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
                        _shortMavi(d.displayMavi),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.2,
                          color: PartnerModernUi.textPrimary(context),
                        ),
                      ),
                      if (d.displayDriver != null)
                        Text(
                          d.displayDriver!,
                          style: TextStyle(
                            fontSize: 13,
                            color: PartnerModernUi.textPrimary(context),
                          ),
                        ),
                      Text(
                        d.partnerName,
                        style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                      ),
                      if (d.fleetRoles.isNotEmpty)
                        Text(
                          d.fleetRolesLabel,
                          style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numCell('Ruter', '${d.routeCount}', _accent)),
                Expanded(child: _numCell('Kunder', '${d.customerCount}', _blue)),
                Expanded(
                  child: _numCell('Km', d.totalKm.toStringAsFixed(0), _orange),
                ),
                Expanded(
                  child: _numCell(
                    'Fri',
                    '${d.friDays}',
                    d.friDays > 0 ? _purple : PartnerModernUi.muted(context),
                  ),
                ),
              ],
            ),
            if (d.topRegion != null) ...[
              const SizedBox(height: 8),
              Text(
                'Område: ${d.topRegion}',
                style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
        ),
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: child,
    );
  }
}
