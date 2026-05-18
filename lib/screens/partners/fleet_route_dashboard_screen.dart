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

/// Avansert oversikt: skift (område/dag/kveld), hvem som har rute vs ledig/fri, statistikk.
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

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
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

      final shares = await PartnerService.fetchRouteSharesForCompany(cid, limit: 2000);
      final from = _statsPeriod.cutoff(DateTime.now()) ?? DateTime(2020);
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
          _fleet = fleet;
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
        return 'Ledig bil';
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

  FleetAnalyticsSummary get _analytics => FleetAnalyticsService.build(
        period: _statsPeriod,
        shares: _recentShares,
        snapshots: _rangeSnaps,
        vehicleLabels: _vehicleLabels,
        partnerNames: _partnerNames,
      );

  String _vehicleLabel(String vehicleId) => _vehicleLabels[vehicleId] ?? vehicleId.substring(0, 8);

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

  Future<void> _addCustomShift() async {
    final cid = _companyId;
    if (cid == null) return;
    final name = TextEditingController();
    final region = TextEditingController();
    final desc = TextEditingController();
    var band = 'dag';
    var color = '#2E7D32';
    final colors = const [
      '#2E7D32',
      '#1565C0',
      '#6A1B9A',
      '#00897B',
      '#F9A825',
      '#C62828',
      '#5D4037',
      '#455A64',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Nytt ruteskift'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Navn / tittel',
                    hintText: 'F.eks. «Asker — dagrute»',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: region,
                  decoration: const InputDecoration(
                    labelText: 'Område / gruppe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: band,
                  decoration: const InputDecoration(labelText: 'Tid', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'dag', child: Text('Dag')),
                    DropdownMenuItem(value: 'kveld', child: Text('Kveld')),
                  ],
                  onChanged: (v) => setSt(() => band = v ?? 'dag'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: desc,
                  decoration: const InputDecoration(labelText: 'Beskrivelse (valgfritt)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: colors
                      .map(
                        (c) => GestureDetector(
                          onTap: () => setSt(() => color = c),
                          child: CircleAvatar(
                            backgroundColor: _hexColor(c),
                            child: color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Opprett'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await PartnerService.createFleetShift(
        companyId: cid,
        name: name.text.trim(),
        description: desc.text.trim().isEmpty ? null : desc.text.trim(),
        colorHex: color,
        regionGroup: region.text.trim().isEmpty ? null : region.text.trim(),
        timeBand: band,
        shiftKind: 'route_ops',
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      name.dispose();
      region.dispose();
      desc.dispose();
    }
  }

  Color _hexColor(String hex) {
    try {
      var h = hex.replaceFirst('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  Widget _summaryStrip() {
    if (_routeShiftId == null) return const SizedBox.shrink();
    var har = 0, led = 0, fri = 0, gitt = 0;
    for (final r in _fleet) {
      final s = _snapByVehicle[r.vehicle.id]?.status ?? 'ledig';
      switch (s) {
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
    Widget chip(String label, int n, Color c) {
      return Expanded(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          chip('Har rute', har, _statusColor('har_rute')),
          chip('Ledig', led, _statusColor('ledig')),
          chip('Fri', fri, _statusColor('fri')),
          chip('Gitt bort', gitt, _statusColor('gitt_bort')),
        ],
      ),
    );
  }

  Widget _overviewTab() {
    final shift = _selectedRouteShift;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
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
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(DateFormat.yMMMd('nb_NO').format(_focusDate)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            value: _routeShiftId,
            decoration: const InputDecoration(
              labelText: 'Ruteskift (område / dag eller kveld)',
              border: OutlineInputBorder(),
            ),
            items: _shifts
                .where((s) => !s.isAvailability)
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
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
          ),
        ),
        if (shift != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Valgt skift: ${shift.name} · ${shift.description ?? ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Tilgjengelighet (Fri / Gitt bort / Ledig) gjelder valgt ruteskift og dato. '
            'Etter massefordeling markeres biler uten PDF som ledige.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        _summaryStrip(),
        Expanded(
          child: _fleet.isEmpty
              ? const Center(child: Text('Ingen registrerte kjøretøy. Legg til biler under hver partner.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: _fleet.length,
                  itemBuilder: (_, i) {
                    final row = _fleet[i];
                    final st = _snapByVehicle[row.vehicle.id]?.status ?? 'ledig';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(st),
                          child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 20),
                        ),
                        title: Text(row.vehicle.unitCode, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${row.partner.name} · reg ${row.vehicle.registrationNumber}\n${_statusLabel(st)}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => _setStatus(row, v),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'har_rute', enabled: false, child: Text('Har rute (via PDF-utsendelse)')),
                            const PopupMenuItem(value: 'ledig', child: Text('Sett ledig bil')),
                            const PopupMenuItem(value: 'fri', child: Text('Sett fri')),
                            const PopupMenuItem(value: 'gitt_bort', child: Text('Gitt bort rute')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _barChart(String title, Map<String, int> counts, Color barColor) {
    final entries = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(10).toList();
    if (top.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }
    final maxY = top.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble() + 1;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            SizedBox(
              height: 220,
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
                        reservedSize: 32,
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              label.length > 8 ? '${label.substring(0, 8)}…' : label,
                              style: const TextStyle(fontSize: 9),
                            ),
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

  Widget _kpiOverviewCard() {
    final a = _analytics;
    Widget cell(String label, int n, Color c) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Text('$n', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Periode: ${_statsPeriod.label}', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          Row(
            children: [
              cell('Ruter mottatt', a.routesReceived, DriftProTheme.primaryGreen),
              cell('Har rute (dager)', a.harRuteDays, _statusColor('har_rute')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              cell('Fri / søkt fri', a.friDays, _statusColor('fri')),
              cell('Ledig bil', a.ledigDays, _statusColor('ledig')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              cell('Gitt bort', a.gittBortDays, _statusColor('gitt_bort')),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
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
                trailing: Text('${r.count}', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _statsTab() {
    final a = _analytics;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
        ),
        _kpiOverviewCard(),
        _barChart(
          'Flest mottatte ruter (PDF)',
          {for (final r in a.topRoutes) r.vehicleId: r.count},
          DriftProTheme.primaryGreen,
        ),
        _barChart(
          'Mest «fri» / søkt fri',
          {for (final r in a.topFri) r.vehicleId: r.count},
          _statusColor('fri'),
        ),
        _barChart(
          'Mest ledig bil',
          {for (final r in a.topLedig) r.vehicleId: r.count},
          _statusColor('ledig'),
        ),
        _barChart(
          'Mest gitt bort rute',
          {for (final r in a.topGittBort) r.vehicleId: r.count},
          _statusColor('gitt_bort'),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Full oversikt per bil, dag og skift. Data fra rute-PDF (sendt) og flåte-snapshot.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _rankingTab() {
    final a = _analytics;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Rangering — ${_statsPeriod.label}', style: DriftProTheme.headingMd),
        ),
        _rankingSection('🏆 Flest ruter mottatt', a.topRoutes, DriftProTheme.primaryGreen),
        _rankingSection('🕊️ Mest fri / søkt fri', a.topFri, _statusColor('fri')),
        _rankingSection('🚛 Mest ledig', a.topLedig, _statusColor('ledig')),
        _rankingSection('↗️ Mest gitt bort', a.topGittBort, _statusColor('gitt_bort')),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _shiftsTab() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            const Text(
              'Alle skift (inkl. tilgjengelighet for fargekoder). Ruteskift brukes ved massefordeling.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ..._shifts.map(
              (s) => Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: s.color, radius: 10),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.isAvailability ? 'Tilgjengelighet' : 'Rute'} · ${s.regionGroup ?? '—'} · ${s.timeBand ?? '—'}',
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const FleetShiftAdminScreen()),
              );
              await _load();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Administrer skift'),
            backgroundColor: DriftProTheme.primaryGreen,
          ),
        ),
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
          tabs: const [
            Tab(text: 'Live oversikt'),
            Tab(text: 'Statistikk'),
            Tab(text: 'Rangering'),
            Tab(text: 'Skift'),
          ],
        ),
        actions: [
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
