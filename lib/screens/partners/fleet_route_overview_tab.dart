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

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _weekStartMonday(DateTime d) {
  final n = _dayOnly(d);
  return n.subtract(Duration(days: n.weekday - DateTime.monday));
}

/// Ruteoversikt 2026 — Excel-lignende plan: MAVI × dato × skift (Supabase).
class FleetRouteOverviewTab extends StatefulWidget {
  const FleetRouteOverviewTab({super.key, this.onDataChanged});

  /// Kalles når ruteoversikt lagres/importeres — oppdaterer øvrige faner.
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

  List<FleetPartnerVehicleRow> _fleet = [];
  List<FleetShiftDefinition> _shifts = [];
  List<MaviDriverDayAssignment> _assignments = [];
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

  List<DateTime> get _days {
    final total = 7 * _weekCount;
    return List.generate(
      total,
      (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
    );
  }

  DateTime get _rangeEnd => _days.last;

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
        final visibleEnd = DateTime(weekStart.year, weekStart.month, weekStart.day + 7 * _weekCount - 1);
        final map = <String, MaviDriverDayAssignment>{};
        for (final a in assignments) {
          if (a.assignmentDate.isBefore(weekStart) || a.assignmentDate.isAfter(visibleEnd)) {
            continue;
          }
          final dk = a.assignmentDate.toIso8601String().split('T').first;
          map['${a.partnerVehicleId}|$dk'] = a;
        }
        setState(() {
          _companyId = cid;
          _fleet = fleet;
          _shifts = shifts;
          _assignments = assignments;
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
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _fleet;
    return _fleet.where((r) {
      final code = MaviUnitCodes.compactLabel(r.vehicle.unitCode).toLowerCase();
      final name = r.partner.name.toLowerCase();
      final driver = (r.vehicle.driverName ?? '').toLowerCase();
      return code.contains(q) || name.contains(q) || driver.contains(q);
    }).toList();
  }

  FleetShiftDefinition? _shiftById(String id) {
    for (final s in _shifts) {
      if (s.id == id) return s;
    }
    return null;
  }

  MaviDriverDayAssignment? _cellAssignment(String vehicleId, DateTime day) {
    final dk = day.toIso8601String().split('T').first;
    return _assignByKey['$vehicleId|$dk'];
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
      if (bytes == null) return;
    }

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
                    maxLines: 2,
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
      await _load();
      _notifyDataChanged();
      return;
    }
    if (ok != true || selected == null) return;

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
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
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

    final filled = _assignments.length;
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
                  'Ruteoversikt 2026',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sjåfører M01+ · ${_shifts.length} skift · $filled registreringer i visningen',
                  style: TextStyle(fontSize: 12, color: PartnerModernUi.muted(context)),
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
              ],
            ),
          ),
        ),
        Expanded(child: _grid(drivers)),
      ],
    );
  }

  Widget _grid(int drivers) {
    const maviW = 108.0;
    const rowH = 44.0;
    const headH = 52.0;
    const dayW = 92.0;
    final gridW = maviW + _days.length * dayW;

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
                    _headerCell('MAVI', maviW, headH, sticky: true),
                    ..._days.map((d) {
                      final weekend = d.weekday >= DateTime.saturday;
                      return _headerCell(
                        '${DateFormat('E', 'nb_NO').format(d)}\n${DateFormat('d.M.', 'nb_NO').format(d)}',
                        dayW,
                        headH,
                        tint: weekend ? Colors.orange.withValues(alpha: 0.08) : null,
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
              ? const Center(child: Text('Ingen MAVI fra M01 i flåten.'))
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
                                    ..._days.map((d) => _dayCell(row, d, dayW, rowH)),
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

  Widget _headerCell(String text, double w, double h, {bool sticky = false, Color? tint}) {
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint ?? PartnerModernUi.surface(context),
        border: Border(
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: sticky ? 12 : 10,
          fontWeight: FontWeight.w800,
          color: PartnerModernUi.textPrimary(context),
          height: 1.1,
        ),
      ),
    );
  }

  Widget _maviCell(FleetPartnerVehicleRow row, double w, double h) {
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          if (row.vehicle.driverName != null && row.vehicle.driverName!.trim().isNotEmpty)
            Text(
              row.vehicle.driverName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: PartnerModernUi.muted(context)),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(FleetPartnerVehicleRow row, DateTime day, double w, double h) {
    final assign = _cellAssignment(row.vehicle.id, day);
    final shift = assign != null ? _shiftById(assign.shiftId) : null;
    final weekend = day.weekday >= DateTime.saturday;

    return Material(
      color: shift != null
          ? shift.color.withValues(alpha: 0.22)
          : (weekend ? Colors.grey.withValues(alpha: 0.04) : Colors.transparent),
      child: InkWell(
        onTap: () => _editCell(row, day),
        child: Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
              bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
            ),
          ),
          child: shift == null
              ? Icon(Icons.add, size: 16, color: Colors.grey.withValues(alpha: 0.35))
              : Text(
                  _shortShiftLabel(shift),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: shift.color.computeLuminance() > 0.55 ? Colors.black87 : Colors.white,
                    height: 1.05,
                  ),
                ),
        ),
      ),
    );
  }

  String _shortShiftLabel(FleetShiftDefinition shift) {
    if (shift.isAvailability) {
      if (shift.name.startsWith('LEDIG')) return shift.name.replaceFirst('LEDIG ', 'L. ');
      return shift.name;
    }
    final region = shift.regionGroup ?? '';
    final band = shift.timeBand == 'kveld' ? 'K' : 'D';
    if (region.isEmpty) return shift.name;
    final short = region.length > 10 ? region.substring(0, 10) : region;
    return '$band $short';
  }
}
