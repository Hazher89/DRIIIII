import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/partner/fleet_route_overview_service.dart';
import '../../core/services/partner/mavi_unit_codes.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/fleet_shift.dart';
import '../../models/partner/mavi_driver_day_assignment.dart';
import 'widgets/partner_modern_ui.dart';
import '../../widgets/driftpro_loading_indicator.dart';

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _weekStartMonday(DateTime d) {
  final n = _dayOnly(d);
  return n.subtract(Duration(days: n.weekday - DateTime.monday));
}

enum _VehicleSort { maviAsc, fillDesc, fillAsc, driverAz, partnerAz }

enum _DaySort { chronological, weekendsFirst, fillDesc, fillAsc }

enum _CellFilter { all, empty, fri, routes }

/// Ruteoversikt — Excel-lignende plan: MAVI × dato × skift.
class FleetRouteOverviewTab extends StatefulWidget {
  const FleetRouteOverviewTab({super.key, this.onDataChanged});

  final VoidCallback? onDataChanged;

  @override
  State<FleetRouteOverviewTab> createState() => _FleetRouteOverviewTabState();
}

class _FleetRouteOverviewTabState extends State<FleetRouteOverviewTab> {
  bool _loading = true;
  bool _anchoredToData = false;
  String? _error;
  String? _companyId;
  DateTime _weekStart = _weekStartMonday(DateTime.now());
  int _weekCount = 4;
  final _search = TextEditingController();

  _VehicleSort _vehicleSort = _VehicleSort.maviAsc;
  _DaySort _daySort = _DaySort.chronological;
  _CellFilter _filter = _CellFilter.all;
  bool _compact = false;

  List<FleetPartnerVehicleRow> _fleet = [];
  List<FleetShiftDefinition> _shifts = [];
  Map<String, MaviDriverDayAssignment> _assignByKey = {};

  final _vScroll = ScrollController();
  final _hHeader = ScrollController();
  final _hBody = ScrollController();
  bool _syncingHorizontal = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _hHeader.addListener(_syncHeaderToBody);
    _hBody.addListener(_syncBodyToHeader);
    _load();
  }

  void _syncHeaderToBody() {
    if (_syncingHorizontal) return;
    if (!_hBody.hasClients) return;
    if (_hBody.offset == _hHeader.offset) return;
    _syncingHorizontal = true;
    _hBody.jumpTo(_hHeader.offset);
    _syncingHorizontal = false;
  }

  void _syncBodyToHeader() {
    if (_syncingHorizontal) return;
    if (!_hHeader.hasClients) return;
    if (_hHeader.offset == _hBody.offset) return;
    _syncingHorizontal = true;
    _hHeader.jumpTo(_hBody.offset);
    _syncingHorizontal = false;
  }

  void _notifyDataChanged() => widget.onDataChanged?.call();

  @override
  void dispose() {
    _search.dispose();
    _vScroll.dispose();
    _hHeader.dispose();
    _hBody.dispose();
    super.dispose();
  }

  List<DateTime> get _rawDays {
    final total = 7 * _weekCount;
    return List.generate(
      total,
      (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
    );
  }

  int _dayFill(DateTime day) {
    var n = 0;
    for (final row in _fleet) {
      if (_cellAssignment(row.vehicle.id, day) != null) n++;
    }
    return n;
  }

  List<DateTime> get _days {
    final list = List<DateTime>.from(_rawDays);
    switch (_daySort) {
      case _DaySort.chronological:
        break;
      case _DaySort.weekendsFirst:
        list.sort((a, b) {
          final aw = a.weekday >= DateTime.saturday ? 0 : 1;
          final bw = b.weekday >= DateTime.saturday ? 0 : 1;
          if (aw != bw) return aw.compareTo(bw);
          return a.compareTo(b);
        });
      case _DaySort.fillDesc:
        list.sort((a, b) {
          final c = _dayFill(b).compareTo(_dayFill(a));
          return c != 0 ? c : a.compareTo(b);
        });
      case _DaySort.fillAsc:
        list.sort((a, b) {
          final c = _dayFill(a).compareTo(_dayFill(b));
          return c != 0 ? c : a.compareTo(b);
        });
    }
    return list;
  }

  DateTime get _rangeEnd => _rawDays.last;

  int _vehicleFill(FleetPartnerVehicleRow row) {
    var n = 0;
    for (final d in _rawDays) {
      if (_cellAssignment(row.vehicle.id, d) != null) n++;
    }
    return n;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final fleet = FleetRouteOverviewService.sortDriversFromM01(
        PartnerService.filterMaviFleetOnly(await PartnerService.fetchCompanyFleet(cid)),
      );
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final assignments = await FleetRouteOverviewService.fetchAssignments(
        companyId: cid,
        from: DateTime(2025, 12, 1),
        to: DateTime(2026, 12, 31),
      );
      if (mounted) {
        var weekStart = _weekStart;
        if (!_anchoredToData && assignments.isNotEmpty) {
          var min = assignments.first.assignmentDate;
          for (final a in assignments) {
            if (a.assignmentDate.isBefore(min)) min = a.assignmentDate;
          }
          weekStart = _weekStartMonday(min);
          _anchoredToData = true;
        }
        final visibleEnd = DateTime(
          weekStart.year,
          weekStart.month,
          weekStart.day + 7 * _weekCount - 1,
        );
        final map = <String, MaviDriverDayAssignment>{};
        for (final a in assignments) {
          if (a.assignmentDate.isBefore(weekStart) ||
              a.assignmentDate.isAfter(visibleEnd)) {
            continue;
          }
          final dk = a.assignmentDate.toIso8601String().split('T').first;
          map['${a.partnerVehicleId}|$dk'] = a;
        }
        setState(() {
          _companyId = cid;
          _fleet = fleet;
          _shifts = shifts;
          _assignByKey = map;
          _weekStart = weekStart;
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

  List<FleetPartnerVehicleRow> get _visibleFleet {
    var list = _fleet;
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final code = MaviUnitCodes.compactLabel(r.vehicle.unitCode).toLowerCase();
        final name = r.partner.name.toLowerCase();
        final driver = (r.vehicle.driverName ?? '').toLowerCase();
        return code.contains(q) || name.contains(q) || driver.contains(q);
      }).toList();
    }

    if (_filter != _CellFilter.all) {
      list = list.where((r) {
        for (final d in _rawDays) {
          final a = _cellAssignment(r.vehicle.id, d);
          final shift = a != null ? _shiftById(a.shiftId) : null;
          switch (_filter) {
            case _CellFilter.empty:
              if (a == null) return true;
            case _CellFilter.fri:
              if (shift != null && _isFriShift(shift)) return true;
            case _CellFilter.routes:
              if (shift != null && !shift.isAvailability) return true;
            case _CellFilter.all:
              return true;
          }
        }
        return false;
      }).toList();
    }

    list = List<FleetPartnerVehicleRow>.from(list);
    switch (_vehicleSort) {
      case _VehicleSort.maviAsc:
        list.sort(
          (a, b) => MaviUnitCodes.compactLabel(a.vehicle.unitCode)
              .compareTo(MaviUnitCodes.compactLabel(b.vehicle.unitCode)),
        );
      case _VehicleSort.fillDesc:
        list.sort((a, b) {
          final c = _vehicleFill(b).compareTo(_vehicleFill(a));
          return c != 0
              ? c
              : MaviUnitCodes.compactLabel(a.vehicle.unitCode)
                  .compareTo(MaviUnitCodes.compactLabel(b.vehicle.unitCode));
        });
      case _VehicleSort.fillAsc:
        list.sort((a, b) {
          final c = _vehicleFill(a).compareTo(_vehicleFill(b));
          return c != 0
              ? c
              : MaviUnitCodes.compactLabel(a.vehicle.unitCode)
                  .compareTo(MaviUnitCodes.compactLabel(b.vehicle.unitCode));
        });
      case _VehicleSort.driverAz:
        list.sort((a, b) {
          final ad = (a.vehicle.driverName ?? '').toLowerCase();
          final bd = (b.vehicle.driverName ?? '').toLowerCase();
          final c = ad.compareTo(bd);
          return c != 0
              ? c
              : MaviUnitCodes.compactLabel(a.vehicle.unitCode)
                  .compareTo(MaviUnitCodes.compactLabel(b.vehicle.unitCode));
        });
      case _VehicleSort.partnerAz:
        list.sort((a, b) {
          final c = a.partner.name.toLowerCase().compareTo(b.partner.name.toLowerCase());
          return c != 0
              ? c
              : MaviUnitCodes.compactLabel(a.vehicle.unitCode)
                  .compareTo(MaviUnitCodes.compactLabel(b.vehicle.unitCode));
        });
    }
    return list;
  }

  FleetShiftDefinition? _shiftById(String id) {
    for (final s in _shifts) {
      if (s.id == id) return s;
    }
    return null;
  }

  bool _isFriShift(FleetShiftDefinition s) {
    final n = s.name.toLowerCase();
    return n.contains('fri') || (s.isAvailability && n.contains('fri'));
  }

  MaviDriverDayAssignment? _cellAssignment(String vehicleId, DateTime day) {
    final dk = day.toIso8601String().split('T').first;
    return _assignByKey['$vehicleId|$dk'];
  }

  ({int filled, int empty, int fri, int routes, int total}) get _stats {
    final days = _rawDays;
    final total = _fleet.length * days.length;
    var filled = 0;
    var fri = 0;
    var routes = 0;
    for (final row in _fleet) {
      for (final d in days) {
        final a = _cellAssignment(row.vehicle.id, d);
        if (a == null) continue;
        filled++;
        final s = _shiftById(a.shiftId);
        if (s == null) continue;
        if (_isFriShift(s)) {
          fri++;
        } else if (!s.isAvailability) {
          routes++;
        }
      }
    }
    return (
      filled: filled,
      empty: total - filled,
      fri: fri,
      routes: routes,
      total: total,
    );
  }

  Future<void> _jumpToFirstEmpty() async {
    final fleet = _visibleFleet;
    for (final row in fleet) {
      for (final d in _rawDays) {
        if (_cellAssignment(row.vehicle.id, d) == null) {
          setState(() {
            _weekStart = _weekStartMonday(d);
            _filter = _CellFilter.empty;
          });
          await _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Første ledige: ${MaviUnitCodes.compactLabel(row.vehicle.unitCode)} · '
                  '${DateFormat('EEE d. MMM', 'nb').format(d)}',
                ),
              ),
            );
          }
          return;
        }
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen ledige celler i perioden.')),
      );
    }
  }

  Future<void> _pickExcelImport() async {
    final cid = _companyId;
    if (cid == null) return;

    Uint8List? bytes;
    for (final path in [
      '/Users/hama/DRIFTPRO/Ruteoversikt 2026.xlsx',
      '/Users/hama/MAVI PRO/Ruteoversikt 2026.xlsx',
    ]) {
      if (!kIsWeb && await File(path).exists()) {
        bytes = await File(path).readAsBytes();
        break;
      }
    }
    if (bytes == null) {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      bytes = picked.files.first.bytes;
      if (bytes == null && picked.files.first.path != null && !kIsWeb) {
        bytes = await File(picked.files.first.path!).readAsBytes();
      }
    }
    if (bytes == null) return;

    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importer Ruteoversikt'),
        content: const Text(
          'Erstatt eksisterende plan i valgt datoperiode fra filen?\n\n'
          'Velg «Nei» for å legge til / oppdatere celler uten å slette andre dager.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Legg til')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Erstatt periode')),
        ],
      ),
    );
    if (!mounted || replace == null) return;

    setState(() => _loading = true);
    try {
      final report = await FleetRouteOverviewService.importFromExcel(
        companyId: cid,
        bytes: bytes,
        fleet: _fleet,
        shifts: _shifts,
        replaceExisting: replace,
      );
      if (!mounted) return;
      await _load();
      _notifyDataChanged();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import fullført'),
          content: SingleChildScrollView(
            child: Text(
              'Rader: ${report.rowsParsed}\n'
              'Lagret: ${report.cellsWritten}\n'
              'Hoppet over: ${report.cellsSkipped}\n'
              '${report.warnings.isEmpty ? '' : '\n${report.warnings.take(12).join('\n')}'}',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import feilet: $e'), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editCell(FleetPartnerVehicleRow row, DateTime day) async {
    final cid = _companyId;
    if (cid == null) return;

    final existing = _cellAssignment(row.vehicle.id, day);
    final routeShifts = _shifts.where((s) => !s.isAvailability).toList();
    final availShifts = _shifts.where((s) => s.isAvailability).toList();

    FleetShiftDefinition? selected = existing != null ? _shiftById(existing.shiftId) : null;
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: 20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${MaviUnitCodes.compactLabel(row.vehicle.unitCode)} · ${DateFormat.yMMMEd('nb_NO').format(day)}',
                    style: DriftProTheme.headingMd,
                  ),
                  Text(row.partner.name, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 12),
                  Text('Ruteskift', style: DriftProTheme.labelSm),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: routeShifts.map((s) {
                      final on = selected?.id == s.id;
                      return FilterChip(
                        label: Text(s.name, style: const TextStyle(fontSize: 11)),
                        selected: on,
                        onSelected: (_) => setSt(() => selected = s),
                        avatar: CircleAvatar(backgroundColor: s.color, radius: 6),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Text('Tilgjengelighet', style: DriftProTheme.labelSm),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: availShifts.map((s) {
                      final on = selected?.id == s.id;
                      return FilterChip(
                        label: Text(s.name, style: const TextStyle(fontSize: 11)),
                        selected: on,
                        onSelected: (_) => setSt(() => selected = s),
                        avatar: CircleAvatar(backgroundColor: s.color, radius: 6),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notat (valgfritt)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (existing != null)
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Slett', style: TextStyle(color: Colors.red)),
                        ),
                      const Spacer(),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: selected == null ? null : () => Navigator.pop(ctx, true),
                        child: const Text('Lagre'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    if (ok == false && existing != null) {
      await FleetRouteOverviewService.clearAssignment(
        companyId: cid,
        partnerVehicleId: row.vehicle.id,
        date: day,
      );
      notesCtrl.dispose();
      await _load();
      _notifyDataChanged();
      return;
    }
    if (ok != true || selected == null) {
      notesCtrl.dispose();
      return;
    }

    await FleetRouteOverviewService.saveAssignment(
      companyId: cid,
      partnerVehicleId: row.vehicle.id,
      date: day,
      shiftId: selected!.id,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      shiftsForSync: _shifts,
    );
    notesCtrl.dispose();
    await _load();
    _notifyDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingCenter();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Prøv igjen')),
            ],
          ),
        ),
      );
    }

    final stats = _stats;
    final pct = stats.total > 0 ? ((stats.filled / stats.total) * 100).round() : 0;
    final drivers = _visibleFleet.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: PartnerModernUi.surface(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ruteoversikt',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sjåfører M01+ · ${_shifts.length} skift · $drivers synlige biler',
                  style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _kpi('Dekning', '$pct%', DriftProTheme.primaryGreen),
                    _kpi('Fylt', '${stats.filled}', DriftProTheme.accentBlue),
                    _kpi('Ledig', '${stats.empty}', Colors.blueGrey),
                    _kpi('På rute', '${stats.routes}', const Color(0xFF6A1B9A)),
                    _kpi('Fri', '${stats.fri}', const Color(0xFF0288D1)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton.outlined(
                      tooltip: 'Forrige uke',
                      onPressed: () {
                        setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                        _load();
                      },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      '${DateFormat('d. MMM', 'nb_NO').format(_weekStart)} – ${DateFormat('d. MMM', 'nb_NO').format(_rangeEnd)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    IconButton.outlined(
                      tooltip: 'Neste uke',
                      onPressed: () {
                        setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                        _load();
                      },
                      icon: const Icon(Icons.chevron_right),
                    ),
                    FilterChip(
                      label: Text('$_weekCount uker'),
                      selected: _weekCount == 4,
                      onSelected: (_) {
                        setState(() => _weekCount = _weekCount == 4 ? 1 : 4);
                        _load();
                      },
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _weekStart = _weekStartMonday(DateTime.now()));
                        _load();
                      },
                      icon: const Icon(Icons.today_outlined, size: 18),
                      label: const Text('I dag'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _jumpToFirstEmpty,
                      icon: const Icon(Icons.playlist_add_check_outlined, size: 18),
                      label: const Text('Første ledige'),
                    ),
                    FilledButton.icon(
                      onPressed: _pickExcelImport,
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: const Text('Importer Excel'),
                      style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Søk MAVI, sjåfør, bedrift…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Vis',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: PartnerModernUi.muted(context),
                      ),
                    ),
                    for (final f in _CellFilter.values)
                      ChoiceChip(
                        label: Text(_filterLabel(f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                        visualDensity: VisualDensity.compact,
                      ),
                    const SizedBox(width: 8),
                    PopupMenuButton<_VehicleSort>(
                      tooltip: 'Sorter biler',
                      initialValue: _vehicleSort,
                      onSelected: (v) => setState(() => _vehicleSort = v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: _VehicleSort.maviAsc, child: Text('MAVI A–Å')),
                        const PopupMenuItem(value: _VehicleSort.fillDesc, child: Text('Mest fylt')),
                        const PopupMenuItem(value: _VehicleSort.fillAsc, child: Text('Mest ledig')),
                        const PopupMenuItem(value: _VehicleSort.driverAz, child: Text('Sjåfør A–Å')),
                        const PopupMenuItem(value: _VehicleSort.partnerAz, child: Text('Bedrift A–Å')),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.sort_by_alpha, size: 16),
                        label: Text(_vehicleSortLabel(_vehicleSort)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    PopupMenuButton<_DaySort>(
                      tooltip: 'Sorter dager',
                      initialValue: _daySort,
                      onSelected: (v) => setState(() => _daySort = v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: _DaySort.chronological, child: Text('Kalenderrekkefølge')),
                        const PopupMenuItem(value: _DaySort.weekendsFirst, child: Text('Helg først')),
                        const PopupMenuItem(value: _DaySort.fillDesc, child: Text('Mest fylt først')),
                        const PopupMenuItem(value: _DaySort.fillAsc, child: Text('Mest ledig først')),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.calendar_view_week_outlined, size: 16),
                        label: Text(_daySortLabel(_daySort)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    FilterChip(
                      label: Text(_compact ? 'Kompakt' : 'Normal'),
                      selected: _compact,
                      onSelected: (v) => setState(() => _compact = v),
                      avatar: Icon(_compact ? Icons.view_compact : Icons.view_agenda_outlined, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _grid()),
      ],
    );
  }

  String _filterLabel(_CellFilter f) => switch (f) {
        _CellFilter.all => 'Alle',
        _CellFilter.empty => 'Ledige',
        _CellFilter.fri => 'Fri',
        _CellFilter.routes => 'På rute',
      };

  String _vehicleSortLabel(_VehicleSort s) => switch (s) {
        _VehicleSort.maviAsc => 'Biler: MAVI',
        _VehicleSort.fillDesc => 'Biler: fylt',
        _VehicleSort.fillAsc => 'Biler: ledig',
        _VehicleSort.driverAz => 'Biler: sjåfør',
        _VehicleSort.partnerAz => 'Biler: bedrift',
      };

  String _daySortLabel(_DaySort s) => switch (s) {
        _DaySort.chronological => 'Dager: dato',
        _DaySort.weekendsFirst => 'Dager: helg',
        _DaySort.fillDesc => 'Dager: fylt',
        _DaySort.fillAsc => 'Dager: ledig',
      };

  Widget _kpi(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: color),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _grid() {
    final maviW = _compact ? 96.0 : 112.0;
    final rowH = _compact ? 40.0 : 52.0;
    final headH = _compact ? 48.0 : 58.0;
    final dayW = _compact ? 84.0 : 100.0;
    final gridW = maviW + _days.length * dayW;
    final today = _dayOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 1,
          color: PartnerModernUi.surface(context),
          child: Scrollbar(
            controller: _hHeader,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _hHeader,
              child: SizedBox(
                width: gridW,
                height: headH,
                child: Row(
                  children: [
                    _headerCell(
                      'MAVI',
                      maviW,
                      headH,
                      sticky: true,
                      onTap: () async {
                        final v = await showMenu<_VehicleSort>(
                          context: context,
                          position: const RelativeRect.fromLTRB(24, 120, 24, 0),
                          items: const [
                            PopupMenuItem(value: _VehicleSort.maviAsc, child: Text('MAVI A–Å')),
                            PopupMenuItem(value: _VehicleSort.fillDesc, child: Text('Mest fylt')),
                            PopupMenuItem(value: _VehicleSort.fillAsc, child: Text('Mest ledig')),
                            PopupMenuItem(value: _VehicleSort.driverAz, child: Text('Sjåfør')),
                            PopupMenuItem(value: _VehicleSort.partnerAz, child: Text('Bedrift')),
                          ],
                        );
                        if (v != null) setState(() => _vehicleSort = v);
                      },
                    ),
                    ..._days.map((d) {
                      final weekend = d.weekday >= DateTime.saturday;
                      final isToday = _dayOnly(d) == today;
                      final fill = _dayFill(d);
                      return _headerCell(
                        '${DateFormat('E', 'nb_NO').format(d)}\n${DateFormat('d.M.', 'nb_NO').format(d)}\n$fill/${_fleet.length}',
                        dayW,
                        headH,
                        tint: isToday
                            ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
                            : (weekend ? Colors.orange.withValues(alpha: 0.08) : null),
                        emphasize: isToday,
                        onTap: () async {
                          final v = await showMenu<_DaySort>(
                            context: context,
                            position: RelativeRect.fromLTRB(180, 120, 24, 0),
                            items: const [
                              PopupMenuItem(value: _DaySort.chronological, child: Text('Kalender')),
                              PopupMenuItem(value: _DaySort.weekendsFirst, child: Text('Helg først')),
                              PopupMenuItem(value: _DaySort.fillDesc, child: Text('Mest fylt')),
                              PopupMenuItem(value: _DaySort.fillAsc, child: Text('Mest ledig')),
                            ],
                          );
                          if (v != null) setState(() => _daySort = v);
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _visibleFleet.isEmpty
              ? const Center(child: Text('Ingen MAVI matcher filter/søk.'))
              : Scrollbar(
                  controller: _vScroll,
                  child: SingleChildScrollView(
                    controller: _vScroll,
                    child: Scrollbar(
                      controller: _hBody,
                      notificationPredicate: (_) => true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _hBody,
                        child: SizedBox(
                          width: gridW,
                          child: Column(
                            children: _visibleFleet.map((row) {
                              return SizedBox(
                                height: rowH,
                                child: Row(
                                  children: [
                                    _maviCell(row, maviW, rowH),
                                    ..._days.map((d) => _dayCell(row, d, dayW, rowH, today)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _headerCell(
    String text,
    double w,
    double h, {
    bool sticky = false,
    Color? tint,
    bool emphasize = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: tint ?? PartnerModernUi.surface(context),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              bottom: BorderSide(
                color: emphasize
                    ? DriftProTheme.primaryGreen
                    : Colors.grey.withValues(alpha: 0.25),
                width: emphasize ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: sticky ? 12 : 9,
              fontWeight: FontWeight.w800,
              color: emphasize
                  ? DriftProTheme.primaryGreenDark
                  : PartnerModernUi.textPrimary(context),
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _maviCell(FleetPartnerVehicleRow row, double w, double h) {
    final fill = _vehicleFill(row);
    final den = _rawDays.length;
    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            MaviUnitCodes.compactLabel(row.vehicle.unitCode),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          Text(
            row.vehicle.driverName?.trim().isNotEmpty == true
                ? '${row.vehicle.driverName} · $fill/$den'
                : '$fill/$den fylt',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(
    FleetPartnerVehicleRow row,
    DateTime day,
    double w,
    double h,
    DateTime today,
  ) {
    final assign = _cellAssignment(row.vehicle.id, day);
    final shift = assign != null ? _shiftById(assign.shiftId) : null;
    final weekend = day.weekday >= DateTime.saturday;
    final isToday = _dayOnly(day) == today;

    return Container(
      width: w,
      height: h,
      padding: EdgeInsets.all(_compact ? 3 : 5),
      decoration: BoxDecoration(
        color: isToday
            ? DriftProTheme.primaryGreen.withValues(alpha: 0.04)
            : (weekend ? Colors.orange.withValues(alpha: 0.03) : null),
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _editCell(row, day),
          borderRadius: BorderRadius.circular(12),
          child: shift == null
              ? Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.22),
                      style: BorderStyle.solid,
                    ),
                    color: Colors.grey.withValues(alpha: 0.04),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: _compact ? 14 : 18,
                    color: Colors.grey.withValues(alpha: 0.4),
                  ),
                )
              : _ShiftBubble(
                  shift: shift,
                  label: _shortShiftLabel(shift),
                  fri: _isFriShift(shift),
                  compact: _compact,
                ),
        ),
      ),
    );
  }

  String _shortShiftLabel(FleetShiftDefinition shift) {
    if (shift.isAvailability) {
      if (shift.name.toLowerCase().contains('fri')) return 'Fri';
      if (shift.name.startsWith('LEDIG')) return shift.name.replaceFirst('LEDIG ', 'L. ');
      return shift.name;
    }
    final region = shift.regionGroup ?? '';
    final band = shift.timeBand == 'kveld' ? 'K' : 'D';
    if (region.isEmpty) return shift.name;
    final short = region.length > 10 ? '${region.substring(0, 9)}…' : region;
    return '$band. $short';
  }
}

class _ShiftBubble extends StatelessWidget {
  const _ShiftBubble({
    required this.shift,
    required this.label,
    required this.fri,
    required this.compact,
  });

  final FleetShiftDefinition shift;
  final String label;
  final bool fri;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = fri
        ? const Color(0xFF0288D1)
        : (shift.isAvailability ? const Color(0xFF546E7A) : shift.color);
    final light = Color.lerp(base, Colors.white, 0.18)!;
    final dark = Color.lerp(base, Colors.black, 0.12)!;
    final onBubble = base.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ),
        border: Border.all(color: base.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.22),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          color: onBubble,
          height: 1.1,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
