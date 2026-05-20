import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/fleet_analytics_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/partner_links.dart';
import 'fleet_shift_admin_screen.dart';
import 'widgets/fleet_dashboard_ui.dart';

/// Flåte & rutesporing — live oversikt, avansert statistikk, rangering og skift.
class FleetRouteDashboardScreen extends StatefulWidget {
  const FleetRouteDashboardScreen({super.key});

  @override
  State<FleetRouteDashboardScreen> createState() => _FleetRouteDashboardScreenState();
}

class _FleetRouteDashboardScreenState extends State<FleetRouteDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String? _companyId;
  bool _loading = true;
  String? _error;

  DateTime _focusDate = DateTime.now();
  List<FleetShiftDefinition> _shifts = [];
  String? _routeShiftId;
  List<FleetPartnerVehicleRow> _fleet = [];
  Map<String, PartnerVehicleFleetSnapshot> _snapByVehicle = {};
  List<PartnerRouteShare> _recentShares = [];
  List<PartnerVehicleFleetSnapshot> _rangeSnaps = [];
  FleetStatsPeriod _statsPeriod = FleetStatsPeriod.days30;

  final _searchCtrl = TextEditingController();
  FleetStatusFilter _statusFilter = FleetStatusFilter.all;
  FleetSortMode _sortMode = FleetSortMode.unitCode;
  FleetListDensity _density = FleetListDensity.comfortable;
  bool _showHelp = true;
  bool _groupByPartner = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
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
      await PartnerService.ensureDefaultFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final routeShifts = shifts.where((s) => !s.isAvailability).toList();
      final rid = _routeShiftId != null && routeShifts.any((s) => s.id == _routeShiftId)
          ? _routeShiftId
          : (routeShifts.isNotEmpty ? routeShifts.first.id : null);

      final fleet = await PartnerService.fetchCompanyFleet(cid);
      Map<String, PartnerVehicleFleetSnapshot> snaps = {};
      if (rid != null) {
        final list = await PartnerService.fetchFleetSnapshots(
          companyId: cid,
          date: _focusDate,
          shiftId: rid,
        );
        snaps = {for (final s in list) s.partnerVehicleId: s};
      }

      final fromCut = _statsPeriod.cutoff(DateTime.now());
      final shares = fromCut == null
          ? await PartnerService.fetchRouteSharesForCompany(cid, limit: 5000)
          : await PartnerService.fetchRouteSharesForCalendarWindow(
              companyId: cid,
              fromDay: fromCut,
              toDay: DateTime.now(),
            );
      final from = fromCut ?? DateTime(2020);
      final rangeSnaps = await PartnerService.fetchFleetSnapshotsRange(
        companyId: cid,
        from: from,
        to: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _companyId = cid;
          _shifts = shifts;
          _routeShiftId = rid;
          _fleet = PartnerService.filterMaviFleetOnly(fleet);
          _snapByVehicle = snaps;
          _recentShares = shares;
          _rangeSnaps = rangeSnaps;
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

  String _statusLabel(String s) {
    switch (s) {
      case 'har_rute':
        return 'Har rute';
      case 'ledig':
        return 'Ledig';
      case 'fri':
        return 'Fri';
      case 'gitt_bort':
        return 'Gitt bort';
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'har_rute':
        return const Color(0xFF2E7D32);
      case 'ledig':
        return const Color(0xFF546E7A);
      case 'fri':
        return const Color(0xFF1565C0);
      case 'gitt_bort':
        return const Color(0xFFEF6C00);
      default:
        return Colors.grey;
    }
  }

  FleetShiftDefinition? get _selectedRouteShift {
    try {
      return _shifts.firstWhere((s) => s.id == _routeShiftId);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get _vehicleLabels {
    return {for (final r in _fleet) r.vehicle.id: r.vehicle.unitCode};
  }

  Map<String, String> get _partnerNames {
    return {for (final r in _fleet) r.vehicle.id: r.partner.name};
  }

  Map<String, String> get _vehicleToPartnerId {
    return {for (final r in _fleet) r.vehicle.id: r.partner.id};
  }

  Map<String, int> get _vehiclesPerPartner {
    final m = <String, int>{};
    for (final r in _fleet) {
      m[r.partner.id] = (m[r.partner.id] ?? 0) + 1;
    }
    return m;
  }

  Map<String, String> get _partnerIdToName {
    return {for (final r in _fleet) r.partner.id: r.partner.name};
  }

  FleetAnalyticsSummary get _analytics => FleetAnalyticsService.build(
        period: _statsPeriod,
        shares: _recentShares,
        snapshots: _rangeSnaps,
        vehicleLabels: _vehicleLabels,
        partnerNames: _partnerNames,
        vehicleToPartnerId: _vehicleToPartnerId,
        vehiclesPerPartner: _vehiclesPerPartner,
      );

  String _vehicleLabel(String vehicleId) => _vehicleLabels[vehicleId] ?? vehicleId.substring(0, 8);

  List<FleetPartnerVehicleRow> get _filteredFleet {
    final q = _searchCtrl.text.trim().toLowerCase();
    final want = _statusFilter.statusValue;
    var rows = _fleet.where((r) {
      final st = _snapByVehicle[r.vehicle.id]?.status ?? 'ledig';
      if (want != null && st != want) return false;
      if (q.isEmpty) return true;
      return r.vehicle.unitCode.toLowerCase().contains(q) ||
          r.partner.name.toLowerCase().contains(q) ||
          r.vehicle.registrationNumber.toLowerCase().contains(q);
    }).toList();

    rows.sort((a, b) {
      switch (_sortMode) {
        case FleetSortMode.partner:
          final c = a.partner.name.compareTo(b.partner.name);
          return c != 0 ? c : a.vehicle.unitCode.compareTo(b.vehicle.unitCode);
        case FleetSortMode.status:
          final sa = _snapByVehicle[a.vehicle.id]?.status ?? 'ledig';
          final sb = _snapByVehicle[b.vehicle.id]?.status ?? 'ledig';
          final c = sa.compareTo(sb);
          return c != 0 ? c : a.vehicle.unitCode.compareTo(b.vehicle.unitCode);
        case FleetSortMode.unitCode:
          return a.vehicle.unitCode.compareTo(b.vehicle.unitCode);
      }
    });
    return rows;
  }

  Map<String, int> get _liveCounts {
    var har = 0, led = 0, fri = 0, gitt = 0;
    for (final r in _fleet) {
      switch (_snapByVehicle[r.vehicle.id]?.status ?? 'ledig') {
        case 'har_rute':
          har++;
          break;
        case 'ledig':
          led++;
          break;
        case 'fri':
          fri++;
          break;
        case 'gitt_bort':
          gitt++;
          break;
      }
    }
    return {'har_rute': har, 'ledig': led, 'fri': fri, 'gitt_bort': gitt};
  }

  Future<void> _setStatus(FleetPartnerVehicleRow row, String status) async {
    final cid = _companyId;
    final sid = _routeShiftId;
    if (cid == null || sid == null) return;
    final d = DateTime(_focusDate.year, _focusDate.month, _focusDate.day);
    final snap = PartnerVehicleFleetSnapshot(
      id: '',
      companyId: cid,
      partnerVehicleId: row.vehicle.id,
      snapshotDate: d,
      shiftId: sid,
      status: status,
      partnerRouteShareId: status == 'har_rute' ? _snapByVehicle[row.vehicle.id]?.partnerRouteShareId : null,
      notes: null,
      createdAt: DateTime.now(),
    );
    try {
      await PartnerService.upsertFleetSnapshot(snap);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row.vehicle.unitCode}: ${_statusLabel(status)}')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke lagre: $e')));
      }
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _focusDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() => _focusDate = d);
      await _load();
    }
  }

  Future<void> _openViewOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Visningsvalg', style: DriftProTheme.headingMd),
                  const SizedBox(height: 16),
                  Text('Sortering', style: DriftProTheme.headingSm),
                  const SizedBox(height: 8),
                  SegmentedButton<FleetSortMode>(
                    segments: const [
                      ButtonSegment(value: FleetSortMode.unitCode, label: Text('Bil')),
                      ButtonSegment(value: FleetSortMode.partner, label: Text('Partner')),
                      ButtonSegment(value: FleetSortMode.status, label: Text('Status')),
                    ],
                    selected: {_sortMode},
                    onSelectionChanged: (s) => setSt(() => _sortMode = s.first),
                  ),
                  const SizedBox(height: 16),
                  Text('Listevisning', style: DriftProTheme.headingSm),
                  const SizedBox(height: 8),
                  SegmentedButton<FleetListDensity>(
                    segments: const [
                      ButtonSegment(value: FleetListDensity.compact, label: Text('Kompakt')),
                      ButtonSegment(value: FleetListDensity.comfortable, label: Text('Romslig')),
                    ],
                    selected: {_density},
                    onSelectionChanged: (s) => setSt(() => _density = s.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Grupper etter partner'),
                    value: _groupByPartner,
                    onChanged: (v) => setSt(() => _groupByPartner = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Vis hjelpetekst'),
                    value: _showHelp,
                    onChanged: (v) => setSt(() => _showHelp = v),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    child: const Text('Bruk'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _shiftDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: _routeShiftId,
      decoration: const InputDecoration(
        labelText: 'Ruteskift',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: _shifts
          .where((s) => !s.isAvailability)
          .map(
            (s) => DropdownMenuItem(
              value: s.id,
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        setState(() => _routeShiftId = v);
        _load();
      },
    );
  }

  Widget _liveKpiStrip() {
    if (_routeShiftId == null) return const SizedBox.shrink();
    final c = _liveCounts;
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          FleetKpiTile(
            label: 'Har rute',
            value: '${c['har_rute']}',
            color: _statusColor('har_rute'),
            icon: Icons.route,
            onTap: () => setState(() => _statusFilter = FleetStatusFilter.harRute),
          ),
          FleetKpiTile(
            label: 'Ledig',
            value: '${c['ledig']}',
            color: _statusColor('ledig'),
            icon: Icons.local_shipping_outlined,
            onTap: () => setState(() => _statusFilter = FleetStatusFilter.ledig),
          ),
          FleetKpiTile(
            label: 'Fri',
            value: '${c['fri']}',
            color: _statusColor('fri'),
            icon: Icons.beach_access,
            onTap: () => setState(() => _statusFilter = FleetStatusFilter.fri),
          ),
          FleetKpiTile(
            label: 'Gitt bort',
            value: '${c['gitt_bort']}',
            color: _statusColor('gitt_bort'),
            icon: Icons.swap_horiz,
            onTap: () => setState(() => _statusFilter = FleetStatusFilter.gittBort),
          ),
          FleetKpiTile(
            label: 'Totalt',
            value: '${_fleet.length}',
            color: DriftProTheme.primaryGreen,
            icon: Icons.directions_bus,
            onTap: () => setState(() => _statusFilter = FleetStatusFilter.all),
          ),
        ],
      ),
    );
  }

  Widget _statusChipsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: FleetStatusFilter.values.map((f) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(f.label),
              selected: _statusFilter == f,
              onSelected: (_) => setState(() => _statusFilter = f),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _vehicleCard(FleetPartnerVehicleRow row) {
    final st = _snapByVehicle[row.vehicle.id]?.status ?? 'ledig';
    final dense = _density == FleetListDensity.compact;
    final reg = row.vehicle.registrationNumber.trim();
    final regLabel = reg.isEmpty ? '—' : reg;

    Widget statusChip(String value, String label) {
      final selected = st == value;
      return FilterChip(
        label: Text(label, style: TextStyle(fontSize: dense ? 10 : 11)),
        selected: selected,
        showCheckmark: false,
        selectedColor: _statusColor(value).withValues(alpha: 0.2),
        onSelected: value == 'har_rute'
            ? null
            : (_) {
                if (!selected) _setStatus(row, value);
              },
      );
    }

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 3 : 5),
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: dense ? 18 : 22,
                  backgroundColor: _statusColor(st),
                  child: Icon(Icons.local_shipping_outlined, color: Colors.white, size: dense ? 18 : 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.vehicle.unitCode, style: TextStyle(fontWeight: FontWeight.w800, fontSize: dense ? 14 : 16)),
                      Text(
                        '${row.partner.name} · $regLabel',
                        style: TextStyle(fontSize: dense ? 11 : 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(st).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(st),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(st)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                statusChip('har_rute', 'Har rute'),
                statusChip('ledig', 'Ledig'),
                statusChip('fri', 'Fri'),
                statusChip('gitt_bort', 'Gitt bort'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTab() {
    final shift = _selectedRouteShift;
    final rows = _filteredFleet;

    final listChildren = <Widget>[];
    if (_groupByPartner) {
      final byPartner = <String, List<FleetPartnerVehicleRow>>{};
      for (final r in rows) {
        byPartner.putIfAbsent(r.partner.id, () => []).add(r);
      }
      for (final entry in byPartner.entries) {
        listChildren.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              _partnerIdToName[entry.key] ?? 'Partner',
              style: DriftProTheme.headingSm,
            ),
          ),
        );
        for (final r in entry.value) {
          listChildren.add(_vehicleCard(r));
        }
      }
    } else {
      for (final r in rows) {
        listChildren.add(_vehicleCard(r));
      }
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FleetFilterCard(
            focusDateLabel: DateFormat.yMMMd('nb_NO').format(_focusDate),
            onPickDate: _pickDate,
            shiftDropdown: _shiftDropdown(),
            shiftHint: shift != null ? '${shift.name} · ${shift.regionGroup ?? shift.timeBand ?? ''}' : null,
            actions: [
              IconButton(
                tooltip: 'Visningsvalg',
                onPressed: _openViewOptions,
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
        if (_showHelp)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Material(
                color: DriftProTheme.primaryGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: DriftProTheme.primaryGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Status gjelder valgt dato og skift. «Har rute» settes ved PDF-utsendelse. '
                          'Trykk på status under bilen for å endre.',
                          style: TextStyle(fontSize: 11, color: Colors.grey[800]),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _showHelp = false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: _liveKpiStrip()),
        SliverToBoxAdapter(child: _statusChipsRow()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Søk bil, partner eller reg.nr…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        if (rows.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Ingen biler matcher filteret.')),
          )
        else
          SliverList(delegate: SliverChildListDelegate(listChildren)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _pieChartCard() {
    final a = _analytics;
    final entries = a.statusBreakdown.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(16),
        child: Padding(padding: EdgeInsets.all(24), child: Text('Ingen statusdata i perioden')),
      );
    }
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statusfordeling (${a.totalSnapshotDays} registreringer)', style: DriftProTheme.headingSm),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: entries.map((e) {
                          final pct = (e.value / total * 100).toStringAsFixed(0);
                          return PieChartSectionData(
                            value: e.value.toDouble(),
                            color: _statusColor(e.key),
                            title: '$pct%',
                            radius: 52,
                            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: _statusColor(e.key), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Expanded(child: Text('${_statusLabel(e.key)} (${e.value})', style: const TextStyle(fontSize: 11))),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendChartCard() {
    final trend = _analytics.dailyTrend;
    if (trend.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxY = trend
        .map((p) => [p.harRute, p.fri, p.ledig, p.gittBort, p.routesSent].reduce((a, b) => a > b ? a : b))
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();
    final spotsHar = <FlSpot>[];
    final spotsRoutes = <FlSpot>[];
    for (var i = 0; i < trend.length; i++) {
      spotsHar.add(FlSpot(i.toDouble(), trend[i].harRute.toDouble()));
      spotsRoutes.add(FlSpot(i.toDouble(), trend[i].routesSent.toDouble()));
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Utvikling per dag', style: DriftProTheme.headingSm),
            const SizedBox(height: 4),
            Text('Grønn: har rute · Blå stiplet: PDF sendt', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY + 2,
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: trend.length > 14 ? 3 : 1,
                        getTitlesWidget: (v, m) {
                          final i = v.toInt();
                          if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                          return Text(DateFormat.Md('nb_NO').format(trend[i].day), style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spotsHar,
                      isCurved: true,
                      color: _statusColor('har_rute'),
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: spotsRoutes,
                      isCurved: true,
                      color: DriftProTheme.accentBlue,
                      barWidth: 2,
                      dashArray: [6, 4],
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedKpiRow() {
    final a = _analytics;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FleetKpiTile(
            label: 'Utnyttelse',
            value: '${a.utilizationPercent.toStringAsFixed(0)}%',
            color: DriftProTheme.primaryGreen,
            subtitle: 'andel «har rute»',
            icon: Icons.speed,
          ),
          FleetKpiTile(
            label: 'PDF sendt',
            value: '${a.routesReceived}',
            color: DriftProTheme.accentBlue,
            icon: Icons.picture_as_pdf,
          ),
          FleetKpiTile(
            label: 'Har rute',
            value: '${a.harRuteDays}',
            color: _statusColor('har_rute'),
          ),
          FleetKpiTile(
            label: 'Fri',
            value: '${a.friDays}',
            color: _statusColor('fri'),
          ),
          FleetKpiTile(
            label: 'Ledig',
            value: '${a.ledigDays}',
            color: _statusColor('ledig'),
          ),
          FleetKpiTile(
            label: 'Gitt bort',
            value: '${a.gittBortDays}',
            color: _statusColor('gitt_bort'),
          ),
        ],
      ),
    );
  }

  Widget _partnerStatsTable() {
    final stats = _analytics.partnerStats.take(15).toList();
    if (stats.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FleetSectionHeader(title: 'Per partner', subtitle: 'Ruter, status og utnyttelse'),
            ...stats.map((p) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.partnerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text(
                  '${p.vehicleCount} bil · ${p.routeCount} PDF · fri ${p.friDays} · ledig ${p.ledigDays}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  '${p.utilizationPercent.toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.w900, color: DriftProTheme.primaryGreen),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _barChart(String title, Map<String, int> counts, Color barColor) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(10).toList();
    if (top.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: ListTile(title: Text(title), subtitle: const Text('Ingen data')),
      );
    }
    final maxY = top.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) {
                          final i = v.toInt();
                          if (i < 0 || i >= top.length) return const SizedBox.shrink();
                          final label = _vehicleLabel(top[i].key);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(label.length > 7 ? '${label.substring(0, 7)}…' : label, style: const TextStyle(fontSize: 9)),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  barGroups: List.generate(top.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: top[i].value.toDouble(),
                          width: 14,
                          color: barColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: FleetStatsPeriod.values.map((p) {
          return ChoiceChip(
            label: Text(p.label),
            selected: _statsPeriod == p,
            onSelected: (_) {
              setState(() => _statsPeriod = p);
              _load();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _statsTab() {
    final a = _analytics;
    return ListView(
      children: [
        _periodChips(),
        _advancedKpiRow(),
        _pieChartCard(),
        _trendChartCard(),
        _barChart('Flest mottatte ruter (PDF)', {for (final r in a.topRoutes) r.vehicleId: r.count}, DriftProTheme.primaryGreen),
        _barChart('Mest fri', {for (final r in a.topFri) r.vehicleId: r.count}, _statusColor('fri')),
        _barChart('Mest ledig', {for (final r in a.topLedig) r.vehicleId: r.count}, _statusColor('ledig')),
        _barChart('Mest gitt bort', {for (final r in a.topGittBort) r.vehicleId: r.count}, _statusColor('gitt_bort')),
        _partnerStatsTable(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _rankingSection(String title, List<FleetVehicleRanking> items, Color color) {
    if (items.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: ListTile(title: Text(title), subtitle: const Text('Ingen data i perioden')),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...items.asMap().entries.map((e) {
              final r = e.value;
              final pct = _analytics.routesReceived > 0 && title.contains('ruter')
                  ? (r.count / _analytics.routesReceived * 100).toStringAsFixed(0)
                  : null;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text('${e.key + 1}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
                ),
                title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text(r.partnerName, style: const TextStyle(fontSize: 11)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${r.count}', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
                    if (pct != null) Text('$pct%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _rankingTab() {
    final a = _analytics;
    return ListView(
      children: [
        _periodChips(),
        FleetSectionHeader(
          title: 'Rangering',
          subtitle: _statsPeriod.label,
          trailing: IconButton(icon: const Icon(Icons.tune), onPressed: _openViewOptions),
        ),
        _rankingSection('Flest ruter mottatt', a.topRoutes, DriftProTheme.primaryGreen),
        _rankingSection('Mest fri / søkt fri', a.topFri, _statusColor('fri')),
        _rankingSection('Mest ledig', a.topLedig, _statusColor('ledig')),
        _rankingSection('Mest gitt bort', a.topGittBort, _statusColor('gitt_bort')),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _shiftsTab() {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Ruteskift brukes ved massefordeling. Tilgjengelighetsskift er for fargekoder (fri/gitt bort).',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final s = _shifts[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: s.color, radius: 10),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.isAvailability ? 'Tilgjengelighet' : 'Rute'} · ${s.regionGroup ?? '—'} · ${s.timeBand ?? '—'}',
                  ),
                ),
              );
            },
            childCount: _shifts.length,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const FleetShiftAdminScreen()),
                );
                await _load();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Administrer alle skift'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Flåte & rutesporing'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Live'),
            Tab(text: 'Statistikk'),
            Tab(text: 'Rangering'),
            Tab(text: 'Skift'),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Visningsvalg', onPressed: _openViewOptions, icon: const Icon(Icons.tune)),
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _overviewTab(),
                    _statsTab(),
                    _rankingTab(),
                    _shiftsTab(),
                  ],
                ),
    );
  }
}
