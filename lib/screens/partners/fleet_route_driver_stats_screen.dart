import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/fleet_analytics_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/route_pdf_text_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/mavi_driver_day_assignment.dart';
import '../../models/partner/partner_links.dart';
import 'widgets/partner_modern_ui.dart';
import 'widgets/partner_route_pdf_actions.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// MAVI-statistikk — ryddig oversikt med diagrammer og drill-down.
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
  final _maviSearch = TextEditingController();

  late DateTime _fromDay;
  late DateTime _toDay;

  bool _initialLoading = true;
  bool _refreshing = false;
  String? _error;
  /// Periodevelger direkte i siden — ingen modal (web blir ellers grå).
  bool _periodPickerOpen = false;
  late DateTime _draftFrom;
  late DateTime _draftTo;
  /// true = redigerer fra, false = til
  bool _editingFrom = true;
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
    FleetDriverFilterKey.friOnly,
    FleetDriverFilterKey.enmannsbil,
    FleetDriverFilterKey.tomannsbil,
  ];

  _FleetRouteDriverStatsScreenState() {
    final now = DateTime.now();
    _fromDay = DateTime(now.year, now.month, 1);
    _toDay = DateTime(now.year, now.month, now.day);
    _draftFrom = _fromDay;
    _draftTo = _toDay;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _maviSearch.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _maviSearch.dispose();
    super.dispose();
  }

  void _applyPreset(FleetCalendarPeriod p) {
    final now = DateTime.now();
    setState(() {
      _periodPickerOpen = false;
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
      _draftFrom = _fromDay;
      _draftTo = _toDay;
    });
    _load();
  }

  void _togglePeriodPicker() {
    setState(() {
      if (_periodPickerOpen) {
        _periodPickerOpen = false;
      } else {
        _draftFrom = _fromDay;
        _draftTo = _toDay;
        _editingFrom = true;
        _periodPickerOpen = true;
      }
    });
  }

  void _onDraftDateChanged(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    setState(() {
      if (_editingFrom) {
        _draftFrom = day;
        if (_draftTo.isBefore(_draftFrom)) _draftTo = _draftFrom;
      } else {
        _draftTo = day;
        if (_draftTo.isBefore(_draftFrom)) _draftFrom = _draftTo;
      }
    });
  }

  Future<void> _applyDraftPeriod() async {
    setState(() {
      _fromDay = _draftFrom;
      _toDay = _draftTo;
      _period = FleetCalendarPeriod.month;
      _periodPickerOpen = false;
      _initialLoading = false;
      _refreshing = true;
      _error = null;
    });
    await _load();
  }

  /// Etter første lasting: aldri fullskjerm-grå — kun tynn topp-indikator.
  Future<void> _load() async {
    if (!mounted) return;
    final isFirst = _fleet.isEmpty && _shares.isEmpty && _initialLoading;
    setState(() {
      if (isFirst) {
        _initialLoading = true;
      } else {
        // Kritisk: aldri gå tilbake til fullskjerm-loader.
        _initialLoading = false;
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final fleet =
          await PartnerService.fetchCompanyFleet(cid, forPlanning: false);
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
      if (!mounted) return;
      setState(() {
        _fleet = PartnerService.filterMaviFleetOnly(fleet);
        _shares = shares;
        _snaps = snaps;
        _shifts = shifts;
        _dayAssignments = assignments;
        _initialLoading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _initialLoading = false;
        _refreshing = false;
      });
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
    var list = _bundle.filtered(
      filter: _filter,
      partnerName: _partnerFilter,
      maviQuery: _maviSearch.text,
      activeVehicleIds: _activeVehicleIds,
    );
    if (_regionFilter != null) {
      list = list
          .where((d) => (d.routesByRegion[_regionFilter!] ?? 0) > 0)
          .toList();
    }
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
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _refreshing ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _initialLoading
          ? const DriftProLoadingCenter()
          : _error != null && _fleet.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!),
                  ),
                )
              : Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      color: _accent,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          _periodCard(df),
                          if (_refreshing) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Oppdaterer tall for perioden…',
                              style: TextStyle(
                                fontSize: 12,
                                color: PartnerModernUi.muted(context),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: _refreshing ? 0.92 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _kpiRow(),
                                const SizedBox(height: 12),
                                _chartsSection(),
                                const SizedBox(height: 12),
                                _topLists(),
                                const SizedBox(height: 12),
                                _filterRow(),
                                const SizedBox(height: 14),
                                _sectionTitle(
                                  'Sjåfører',
                                  '${_visibleDrivers.length} i utvalget · trykk for FO og PDF',
                                ),
                                const SizedBox(height: 8),
                                if (_visibleDrivers.isEmpty)
                                  _emptyBox(
                                    _refreshing
                                        ? 'Oppdaterer tall…'
                                        : 'Ingen sjåfører i perioden.',
                                  )
                                else
                                  ..._visibleDrivers.asMap().entries.map(
                                        (e) => _driverCard(e.key + 1, e.value),
                                      ),
                                const SizedBox(height: 16),
                                _regionsSection(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_refreshing)
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: _accent,
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _periodCard(DateFormat df) {
    final longDf = DateFormat('d. MMM yyyy', 'nb_NO');
    final first = DateTime(2024, 1, 1);
    final last = DateTime.now().add(const Duration(days: 1));
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
            children: [
              for (final p in [
                FleetCalendarPeriod.week,
                FleetCalendarPeriod.month,
                FleetCalendarPeriod.year,
              ])
                ChoiceChip(
                  label: Text(p.label),
                  selected: !_periodPickerOpen && _period == p,
                  onSelected: _refreshing ? null : (_) => _applyPreset(p),
                  selectedColor: _accent.withValues(alpha: 0.2),
                  visualDensity: VisualDensity.compact,
                ),
              FilledButton.tonalIcon(
                onPressed: _refreshing ? null : _togglePeriodPicker,
                icon: Icon(
                  _periodPickerOpen
                      ? Icons.close
                      : Icons.date_range,
                  size: 18,
                ),
                label: Text(
                  _periodPickerOpen ? 'Lukk' : 'Velg periode',
                ),
              ),
            ],
          ),
          if (_periodPickerOpen) ...[
            const SizedBox(height: 12),
            Text(
              'Trykk Fra eller Til, velg dato, deretter Bruk.',
              style: TextStyle(
                fontSize: 12,
                color: PartnerModernUi.muted(context),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _inlinePeriodTile(
                    label: 'Fra',
                    value: longDf.format(_draftFrom),
                    selected: _editingFrom,
                    onTap: () => setState(() => _editingFrom = true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _inlinePeriodTile(
                    label: 'Til',
                    value: longDf.format(_draftTo),
                    selected: !_editingFrom,
                    onTap: () => setState(() => _editingFrom = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Material(
              color: PartnerModernUi.surface(context),
              borderRadius: BorderRadius.circular(12),
              child: CalendarDatePicker(
                // Key tvinger ny kalender når man bytter Fra/Til.
                key: ValueKey(
                  '${_editingFrom ? 'from' : 'to'}-${_editingFrom ? _draftFrom : _draftTo}',
                ),
                initialDate: _editingFrom ? _draftFrom : _draftTo,
                firstDate: first,
                lastDate: last,
                currentDate: DateTime.now(),
                onDateChanged: _onDraftDateChanged,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _refreshing ? null : _applyDraftPeriod,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Bruk ${longDf.format(_draftFrom)} – ${longDf.format(_draftTo)}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inlinePeriodTile({
    required String label,
    required String value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? _accent.withValues(alpha: 0.12)
          : PartnerModernUi.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _accent : PartnerModernUi.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: PartnerModernUi.muted(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiRow() {
    final v = _visibleDrivers;
    final routes = v.fold<int>(0, (a, d) => a + d.routeCount);
    final cust = v.fold<int>(0, (a, d) => a + d.customerCount);
    final km = v.fold<double>(0, (a, d) => a + d.totalKm);
    final b = _bundle;

    return Row(
      children: [
        Expanded(
          child: _kpi(
            'Ruter',
            '$routes',
            _accent,
            onTap: () => _showMetricSheet(
              title: 'Ruter',
              body:
                  '$routes ruter i utvalget.\nSnitt ${b.avgRoutesPerMavi.toStringAsFixed(1)} per MAVI.',
              drivers: [...v]..sort((a, c) => c.routeCount.compareTo(a.routeCount)),
              valueOf: (d) => '${d.routeCount}',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi(
            'Kunder',
            '$cust',
            _blue,
            onTap: () => _showMetricSheet(
              title: 'Kunder',
              body:
                  '$cust kunder fra rute-PDF.\nSnitt ${b.avgCustomersPerMavi.toStringAsFixed(1)} per MAVI.',
              drivers: [...v]
                ..sort((a, c) => c.customerCount.compareTo(a.customerCount)),
              valueOf: (d) => '${d.customerCount}',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi(
            'Km',
            km >= 1000
                ? '${(km / 1000).toStringAsFixed(1)}k'
                : km.toStringAsFixed(0),
            _orange,
            onTap: () => _showMetricSheet(
              title: 'Kilometer',
              body: '${km.toStringAsFixed(0)} km fra PDF (Total distance).',
              drivers: [...v]..sort((a, c) => c.totalKm.compareTo(a.totalKm)),
              valueOf: (d) => d.totalKm.toStringAsFixed(0),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpi(
            'Sjåfører',
            '${v.length}',
            _purple,
            onTap: () => _showMetricSheet(
              title: 'Sjåfører',
              body: '${v.length} MAVI i filteret.',
              drivers: v,
              valueOf: (d) =>
                  '${d.routeCount} r · ${d.customerCount} k',
            ),
          ),
        ),
      ],
    );
  }

  Widget _kpi(String label, String value, Color color, {VoidCallback? onTap}) {
    return Material(
      color: PartnerModernUi.surface(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PartnerModernUi.border(context)),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: PartnerModernUi.muted(context),
                ),
              ),
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
        ),
      ),
    );
  }

  Widget _chartsSection() {
    final v = _visibleDrivers;
    final withRoute = v.where((d) => d.routeCount > 0).length;
    final total = v.isEmpty ? 1 : v.length;
    final topKm = [...v.where((d) => d.totalKm > 0)]
      ..sort((a, b) => b.totalKm.compareTo(a.totalKm));
    final top8 = topKm.take(8).toList();
    final trend = _bundle.dailyTrend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Grafikk', 'Trykk på tall over eller sjåfør under'),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            final donut = _donutCard(
              title: 'Med rute',
              center: '${((withRoute / total) * 100).round()}%',
              subtitle: '$withRoute av ${v.length}',
              value: withRoute.toDouble(),
              rest: (total - withRoute).toDouble().clamp(0, 1e9),
              color: _accent,
            );
            final bars = _kmBarCard(top8);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: donut),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: bars),
                ],
              );
            }
            return Column(
              children: [
                donut,
                const SizedBox(height: 10),
                bars,
              ],
            );
          },
        ),
        if (trend.isNotEmpty) ...[
          const SizedBox(height: 10),
          _trendCard(trend),
        ],
      ],
    );
  }

  Widget _donutCard({
    required String title,
    required String center,
    required String subtitle,
    required double value,
    required double rest,
    required Color color,
  }) {
    final sum = value + rest;
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
          SizedBox(
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 34,
                    sections: sum <= 0
                        ? [
                            PieChartSectionData(
                              value: 1,
                              color: Colors.blueGrey.shade100,
                              title: '',
                              radius: 38,
                            ),
                          ]
                        : [
                            if (value > 0)
                              PieChartSectionData(
                                value: value,
                                color: color,
                                title: '',
                                radius: 40,
                              ),
                            if (rest > 0)
                              PieChartSectionData(
                                value: rest,
                                color: Colors.blueGrey.shade200,
                                title: '',
                                radius: 40,
                              ),
                          ],
                  ),
                ),
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
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _kmBarCard(List<FleetDriverStat> rows) {
    if (rows.isEmpty) {
      return _card(
        child: Text(
          'Ingen km i PDF for perioden.',
          style: TextStyle(color: PartnerModernUi.muted(context)),
        ),
      );
    }
    final maxY = rows.first.totalKm.clamp(1, 1e9);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Topp km',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.15,
                barTouchData: BarTouchData(
                  // Kun ekte trykk — hover på web åpnet ellers sjåfør-sheet «av seg selv».
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (i == null || i < 0 || i >= rows.length) return;
                    _showDriverDetail(rows[i]);
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _shortMavi(rows[i].displayMavi),
                            style: TextStyle(
                              fontSize: 9,
                              color: PartnerModernUi.muted(context),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: rows[i].totalKm,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
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

  Widget _trendCard(List<FleetDailyTrendPoint> trend) {
    final maxY = trend
        .map((p) => p.routesSent > p.fri ? p.routesSent : p.fri)
        .fold<int>(1, (a, b) => a > b ? a : b)
        .toDouble();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trend per dag',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: PartnerModernUi.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _dot(_accent, 'Ruter'),
              const SizedBox(width: 12),
              _dot(_purple, 'Fri'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
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
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 9,
                          color: PartnerModernUi.muted(context),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (trend.length / 5).clamp(1, 30).toDouble(),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= trend.length) {
                          return const SizedBox.shrink();
                        }
                        final d = trend[i].day;
                        return Text(
                          '${d.day}.${d.month}',
                          style: TextStyle(
                            fontSize: 9,
                            color: PartnerModernUi.muted(context),
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
        ],
      ),
    );
  }

  Widget _dot(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
        ),
      ],
    );
  }

  Widget _topLists() {
    final v = _visibleDrivers;
    final byCust = FleetDriverStatsBundle.sorted(
      v.where((d) => d.customerCount > 0).toList(),
      FleetDriverSortKey.customersDesc,
    ).take(5).toList();
    final byKm = FleetDriverStatsBundle.sorted(
      v.where((d) => d.totalKm > 0).toList(),
      FleetDriverSortKey.kmDesc,
    ).take(5).toList();

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 700;
        final left = _miniBoard('Flest kunder', byCust, (d) => '${d.customerCount}', _blue);
        final right = _miniBoard('Lengst km', byKm, (d) => d.totalKm.toStringAsFixed(0), _orange);
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

  Widget _miniBoard(
    String title,
    List<FleetDriverStat> rows,
    String Function(FleetDriverStat) metric,
    Color color,
  ) {
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
          if (rows.isEmpty)
            Text(
              'Ingen data',
              style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
            )
          else
            ...rows.asMap().entries.map((e) {
              final d = e.value;
              return InkWell(
                onTap: () => _showDriverDetail(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
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
                        child: Text(
                          _shortMavi(d.displayMavi),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: PartnerModernUi.textPrimary(context),
                          ),
                        ),
                      ),
                      Text(
                        metric(d),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return _card(
      child: Column(
        children: [
          TextField(
            controller: _maviSearch,
            decoration: InputDecoration(
              hintText: 'Søk MAVI, sjåfør eller partner…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdown<FleetDriverFilterKey>(
                  label: 'Vis',
                  value: _filter,
                  items: _filterOptions
                      .map(
                        (f) => DropdownMenuItem(value: f, child: Text(f.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _filter = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown<FleetDriverSortKey>(
                  label: 'Sorter',
                  value: _driverSort,
                  items: _sortOptions
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _driverSort = v);
                  },
                ),
              ),
            ],
          ),
          if (_partnerNames.length > 1) ...[
            const SizedBox(height: 8),
            _dropdown<String?>(
              label: 'Partner',
              value: _partnerFilter,
              items: [
                const DropdownMenuItem(value: null, child: Text('Alle')),
                ..._partnerNames.map(
                  (n) => DropdownMenuItem(value: n, child: Text(n)),
                ),
              ],
              onChanged: (v) => setState(() => _partnerFilter = v),
            ),
          ],
          if (_regionFilter != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text('Område: $_regionFilter'),
                onDeleted: () => setState(() => _regionFilter = null),
              ),
            ),
          ],
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

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: PartnerModernUi.textPrimary(context),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
        ),
      ],
    );
  }

  Widget _driverCard(int rank, FleetDriverStat d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDriverDetail(d),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PartnerModernUi.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
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
                              fontSize: 17,
                              color: PartnerModernUi.textPrimary(context),
                            ),
                          ),
                          Text(
                            [
                              if (d.displayDriver != null) d.displayDriver!,
                              d.partnerName,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 12,
                              color: PartnerModernUi.muted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _num('Ruter', '${d.routeCount}', _accent)),
                    Expanded(
                      child: _num('Kunder', '${d.customerCount}', _blue),
                    ),
                    Expanded(
                      child: _num('Km', d.totalKm.toStringAsFixed(0), _orange),
                    ),
                    Expanded(
                      child: _num(
                        'Fri',
                        '${d.friDays}',
                        d.friDays > 0 ? _purple : PartnerModernUi.muted(context),
                      ),
                    ),
                  ],
                ),
                if (d.topRegion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Område: ${d.topRegion}',
                    style: TextStyle(
                      fontSize: 11,
                      color: PartnerModernUi.muted(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _num(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
        ),
      ],
    );
  }

  Widget _regionsSection() {
    final regions = FleetDriverStatsBundle.sortedRegions(
      _bundle.regions,
      FleetRegionSortKey.routesDesc,
    ).take(8).toList();
    if (regions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Områder', 'Trykk for å filtrere listen'),
        const SizedBox(height: 8),
        ...regions.map((r) {
          final pct =
              _bundle.totalRoutes > 0 ? r.routeCount / _bundle.totalRoutes * 100 : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: PartnerModernUi.surface(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _regionFilter = r.region),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
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
                                color: PartnerModernUi.textPrimary(context),
                              ),
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
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
                          minHeight: 5,
                          backgroundColor: PartnerModernUi.border(context),
                          color: _accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${r.routeCount} ruter · ${r.customerCount} kunder · ${r.driverCount} sjåfører',
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

  List<_DriverFoRow> _foRowsForDriver(FleetDriverStat d) {
    final start = DateTime(_fromDay.year, _fromDay.month, _fromDay.day);
    final end = DateTime(_toDay.year, _toDay.month, _toDay.day);
    final rows = <_DriverFoRow>[];
    for (final s in _shares) {
      if (s.partnerVehicleId != d.vehicleId) continue;
      if (s.isStaged) continue;
      final day = DateTime(s.shareDate.year, s.shareDate.month, s.shareDate.day);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      final text = s.pdfSearchText ?? '';
      final ids = RoutePdfTextService.parseTrackingIds(text);
      final km = text.isEmpty
          ? null
          : RoutePdfTextService.parseTotalDistanceKm(text);
      final weight = text.isEmpty
          ? null
          : RoutePdfTextService.parseConsumedWeightKg(text);
      final customers = s.customerCount != null && s.customerCount! > 0
          ? s.customerCount!
          : (text.isEmpty
              ? 0
              : RoutePdfTextService.parseCustomers(text).length);
      final fo = ids.fo ??
          RegExp(r'FO[:\s]*(\d{6,14})', caseSensitive: false)
              .firstMatch(s.notes ?? '')
              ?.group(1) ??
          RegExp(r'FO[:\s]*(\d{6,14})', caseSensitive: false)
              .firstMatch(s.title ?? '')
              ?.group(1);
      rows.add(
        _DriverFoRow(
          share: s,
          fo: fo,
          customers: customers,
          km: km,
          weightKg: weight,
          bilags: ids.bilags,
          fus: ids.fus,
          driverFromPdf: ids.driver,
        ),
      );
    }
    rows.sort((a, b) => b.share.shareDate.compareTo(a.share.shareDate));
    return rows;
  }

  void _showDriverDetail(FleetDriverStat d) {
    final b = _bundle;
    final df = DateFormat('d. MMM yyyy', 'nb_NO');
    final dayDf = DateFormat('EEE d.M.y', 'nb_NO');
    final regions = d.routesByRegion.entries.toList()
      ..sort((a, c) => c.value.compareTo(a.value));
    final foRows = _foRowsForDriver(d);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.45,
          maxChildSize: 0.96,
          builder: (ctx, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                Text(
                  _shortMavi(d.displayMavi),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (d.displayDriver != null)
                  Text(
                    d.displayDriver!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                Text(
                  d.partnerName,
                  style: TextStyle(color: PartnerModernUi.muted(ctx)),
                ),
                Text(
                  '${df.format(_fromDay)} – ${df.format(_toDay)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: PartnerModernUi.muted(ctx),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('${d.routeCount} ruter', _accent),
                    _pill('${d.customerCount} kunder', _blue),
                    _pill('${d.totalKm.toStringAsFixed(0)} km', _orange),
                    if (d.friDays > 0) _pill('${d.friDays} fri', _purple),
                    _pill(
                      '${d.customersPerRoute.toStringAsFixed(1)} kunder/rute',
                      _blue,
                    ),
                    if (d.fleetRoles.isNotEmpty)
                      _pill(d.fleetRolesLabel, Colors.blueGrey),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    'Sammenligning: '
                    '${d.routeVsAvg >= 0 ? '+' : ''}${d.routeVsAvg.toStringAsFixed(1)} ruter · '
                    '${d.customerVsAvg >= 0 ? '+' : ''}${d.customerVsAvg.toStringAsFixed(1)} kunder '
                    'mot snitt (${b.avgRoutesPerMavi.toStringAsFixed(1)} / ${b.avgCustomersPerMavi.toStringAsFixed(1)}).',
                    style: const TextStyle(height: 1.35, fontSize: 13),
                  ),
                ),
                if (regions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Områder',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
                const SizedBox(height: 18),
                Text(
                  'Freight Orders (${foRows.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trykk en FO for detaljer og PDF.',
                  style: TextStyle(
                    fontSize: 12,
                    color: PartnerModernUi.muted(ctx),
                  ),
                ),
                const SizedBox(height: 10),
                if (foRows.isEmpty)
                  Text(
                    'Ingen ruter med PDF-data i perioden for denne MAVI.',
                    style: TextStyle(color: PartnerModernUi.muted(ctx)),
                  )
                else
                  ...foRows.map((row) {
                    final foLabel = row.fo ?? 'Uten FO';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: PartnerModernUi.surface(ctx),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showFoDetail(d, row),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: PartnerModernUi.border(ctx),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        foLabel.startsWith('Uten')
                                            ? foLabel
                                            : 'FO $foLabel',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 18,
                                      color: PartnerModernUi.muted(ctx),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dayDf.format(row.share.shareDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: PartnerModernUi.muted(ctx),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _pill('${row.customers} kunder', _blue),
                                    if (row.km != null)
                                      _pill(
                                        '${row.km!.toStringAsFixed(0)} km',
                                        _orange,
                                      ),
                                    if (row.weightKg != null &&
                                        row.weightKg! > 0)
                                      _pill(
                                        '${(row.weightKg! / 1000).toStringAsFixed(1)} t',
                                        Colors.teal.shade700,
                                      ),
                                    if (row.bilags.isNotEmpty)
                                      _pill(
                                        'Bilag ${row.bilags.first}',
                                        Colors.blueGrey,
                                      ),
                                  ],
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
          },
        );
      },
    );
  }

  void _showFoDetail(FleetDriverStat driver, _DriverFoRow row) {
    final df = DateFormat('EEEE d. MMMM yyyy', 'nb_NO');
    final customers = (row.share.pdfSearchText ?? '').isEmpty
        ? const <RoutePdfCustomer>[]
        : RoutePdfTextService.parseCustomers(row.share.pdfSearchText!);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.4,
          maxChildSize: 0.96,
          builder: (ctx, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: [
                Text(
                  row.fo != null ? 'FO ${row.fo}' : 'Rute uten FO',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '${_shortMavi(driver.displayMavi)}'
                  '${driver.displayDriver != null ? ' · ${driver.displayDriver}' : ''}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  df.format(row.share.shareDate),
                  style: TextStyle(
                    fontSize: 13,
                    color: PartnerModernUi.muted(ctx),
                  ),
                ),
                if ((row.driverFromPdf ?? '').isNotEmpty)
                  Text(
                    'Sjåfør i PDF: ${row.driverFromPdf}',
                    style: TextStyle(
                      fontSize: 12,
                      color: PartnerModernUi.muted(ctx),
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _foStatCell(
                          'Kunder',
                          '${row.customers}',
                          _blue,
                        ),
                      ),
                      Expanded(
                        child: _foStatCell(
                          'Km',
                          row.km != null
                              ? row.km!.toStringAsFixed(0)
                              : '–',
                          _orange,
                        ),
                      ),
                      Expanded(
                        child: _foStatCell(
                          'Vekt',
                          row.weightKg != null && row.weightKg! > 0
                              ? '${(row.weightKg! / 1000).toStringAsFixed(1)} t'
                              : '–',
                          Colors.teal.shade700,
                        ),
                      ),
                      Expanded(
                        child: _foStatCell(
                          'Stopp',
                          '${customers.length}',
                          _purple,
                        ),
                      ),
                    ],
                  ),
                ),
                if (row.fus.isNotEmpty || row.bilags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final fu in row.fus.take(6)) _pill('FU $fu', _purple),
                      for (final b in row.bilags.take(8))
                        _pill('Bilag $b', Colors.blueGrey),
                    ],
                  ),
                ],
                if ((row.share.title ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    row.share.title!,
                    style: TextStyle(
                      fontSize: 12,
                      color: PartnerModernUi.muted(ctx),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      PartnerRoutePdfActions.openPdf(ctx, row.share),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Åpne PDF for denne FO'),
                ),
                if (customers.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Kunder på ruta (${customers.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stopp i rekkefølge fra PDF, med bilag og FU der det finnes.',
                    style: TextStyle(
                      fontSize: 12,
                      color: PartnerModernUi.muted(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...customers.map((c) {
                    final meta = <String>[
                      if ((c.postalCode ?? '').isNotEmpty) c.postalCode!,
                      if ((c.deliveryWindow ?? '').isNotEmpty)
                        c.deliveryWindow!,
                      if (c.phoneDisplay.isNotEmpty) c.phoneDisplay,
                    ];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: PartnerModernUi.border(ctx),
                          ),
                        ),
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
                                    color: _blue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${c.sequence}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      color: _blue,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    c.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if ((c.addressHint ?? '').isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                c.addressHint!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: PartnerModernUi.muted(ctx),
                                ),
                              ),
                            ],
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                meta.join(' · '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: PartnerModernUi.muted(ctx),
                                ),
                              ),
                            ],
                            if (c.salesOrder != null ||
                                c.freightUnit != null) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (c.salesOrder != null)
                                    _pill('Bilag ${c.salesOrder}', Colors.blueGrey),
                                  if (c.freightUnit != null)
                                    _pill('FU ${c.freightUnit}', _purple),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            );
          },
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
              height: MediaQuery.sizeOf(ctx).height * 0.65,
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
                  Expanded(
                    child: ListView.separated(
                      itemCount: drivers.length.clamp(0, 60),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = drivers[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            _shortMavi(d.displayMavi),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(d.partnerName),
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

  Widget _foStatCell(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: PartnerModernUi.muted(context),
          ),
        ),
      ],
    );
  }

  Widget _pill(String t, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PartnerModernUi.border(context)),
      ),
      child: child,
    );
  }

  Widget _emptyBox(String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: PartnerModernUi.muted(context)),
      ),
    );
  }
}

class _DriverFoRow {
  const _DriverFoRow({
    required this.share,
    required this.fo,
    required this.customers,
    required this.km,
    required this.weightKg,
    required this.bilags,
    required this.fus,
    required this.driverFromPdf,
  });

  final PartnerRouteShare share;
  final String? fo;
  final int customers;
  final double? km;
  final double? weightKg;
  final List<String> bilags;
  final List<String> fus;
  final String? driverFromPdf;
}
