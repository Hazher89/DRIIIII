import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_single_assign_sheet.dart';
import 'partner_route_auto_mass_sheet.dart';
import 'partner_sap_routes_sheet.dart';

DateTime _monday(DateTime d) {
  final n = DateTime(d.year, d.month, d.day);
  return n.subtract(Duration(days: n.weekday - DateTime.monday));
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

enum _PlannerViewMode { week, month }

/// Løsemiddel-visning inspirert av arbeidsplan: MAVI-navigasjon til venstre, kalender til høyre.
class PartnerRouteMasterScheduler extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final VoidCallback? onChanged;

  const PartnerRouteMasterScheduler({
    super.key,
    required this.fleet,
    this.onChanged,
  });

  @override
  State<PartnerRouteMasterScheduler> createState() => _PartnerRouteMasterSchedulerState();
}

class _PartnerRouteMasterSchedulerState extends State<PartnerRouteMasterScheduler> {
  bool _busy = false;
  _PlannerViewMode _mode = _PlannerViewMode.week;
  DateTime _weekStart = _monday(DateTime.now());
  DateTime _focusDay = _dayOnly(DateTime.now());
  String? _visibilityShiftId; // null = alle
  late final TextEditingController _searchCtrl;
  final ScrollController _leftVert = ScrollController();
  final ScrollController _rightVert = ScrollController();
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  bool _syncVertical = false;
  bool _syncHorizontal = false;

  List<FleetShiftDefinition> _shifts = [];
  List<PartnerRouteShare> _shares = [];
  int _sapPending = 0;
  Timer? _sapPollTimer;

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));
  List<DateTime> get _days =>
      List.generate(7, (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i));

  static const double _rowHeight = 100;
  static const double _sidebarW = 232;
  static const double _dayColW = 128;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController()..addListener(() => setState(() {}));
    _leftVert.addListener(_mirrorLeftVert);
    _rightVert.addListener(_mirrorRightVert);
    _headerH.addListener(_mirrorHeaderHoriz);
    _bodyH.addListener(_mirrorBodyHoriz);
    _reload();
    _sapPollTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      _refreshSapPendingCount();
    });
  }

  @override
  void dispose() {
    _sapPollTimer?.cancel();
    _searchCtrl.dispose();
    _leftVert.removeListener(_mirrorLeftVert);
    _rightVert.removeListener(_mirrorRightVert);
    _headerH.removeListener(_mirrorHeaderHoriz);
    _bodyH.removeListener(_mirrorBodyHoriz);
    _leftVert.dispose();
    _rightVert.dispose();
    _headerH.dispose();
    _bodyH.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PartnerRouteMasterScheduler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fleet != oldWidget.fleet) _reload();
  }

  void _mirrorLeftVert() {
    if (_syncVertical || !_rightVert.hasClients || !_leftVert.hasClients) return;
    final d = (_leftVert.offset - _rightVert.offset).abs();
    if (d < 1) return;
    _syncVertical = true;
    _rightVert.jumpTo(_leftVert.offset);
    _syncVertical = false;
  }

  void _mirrorRightVert() {
    if (_syncVertical || !_rightVert.hasClients || !_leftVert.hasClients) return;
    final d = (_leftVert.offset - _rightVert.offset).abs();
    if (d < 1) return;
    _syncVertical = true;
    _leftVert.jumpTo(_rightVert.offset);
    _syncVertical = false;
  }

  void _mirrorHeaderHoriz() {
    if (_syncHorizontal || !_bodyH.hasClients || !_headerH.hasClients) return;
    if ((_headerH.offset - _bodyH.offset).abs() < 1) return;
    _syncHorizontal = true;
    _bodyH.jumpTo(_headerH.offset);
    _syncHorizontal = false;
  }

  void _mirrorBodyHoriz() {
    if (_syncHorizontal || !_bodyH.hasClients || !_headerH.hasClients) return;
    if ((_bodyH.offset - _headerH.offset).abs() < 1) return;
    _syncHorizontal = true;
    _headerH.jumpTo(_bodyH.offset);
    _syncHorizontal = false;
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final shares = await PartnerService.fetchRouteSharesForCalendarWindow(
        companyId: cid,
        fromDay: _weekStart,
        toDay: _weekEnd,
      );
      final sapPending = await PartnerService.countSapRouteInboxPending(cid);
      if (mounted) setState(() {
        _shifts = shifts;
        _shares = shares;
        _sapPending = sapPending;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshSapPendingCount() async {
    if (!mounted) return;
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final n = await PartnerService.countSapRouteInboxPending(cid);
      if (mounted && n != _sapPending) {
        setState(() => _sapPending = n);
      }
    } catch (_) {}
  }

  List<FleetPartnerVehicleRow> get _maviFleet => PartnerService.filterMaviFleetOnly(widget.fleet);

  List<FleetPartnerVehicleRow> get _filteredFleet {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _maviFleet;
    return _maviFleet
        .where((r) =>
            r.vehicle.unitCode.toLowerCase().contains(q) ||
            r.partner.name.toLowerCase().contains(q))
        .toList();
  }

  List<PartnerRouteShare> _sharesCell(String vehicleId, DateTime day) {
    final dn = _dayOnly(day);
    final out = <PartnerRouteShare>[];
    for (final s in _shares) {
      if (s.partnerVehicleId != vehicleId) continue;
      if (s.dispatchStatus == 'staged' && !_showStaged) continue;
      final sd = _dayOnly(s.shareDate);
      final rs = s.routeStartAt != null ? _dayOnly(s.routeStartAt!.toLocal()) : null;
      if (sd != dn && (rs == null || rs != dn)) continue;
      if (_visibilityShiftId != null && s.shiftId != null && s.shiftId != _visibilityShiftId) continue;
      out.add(s);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  bool get _showStaged => true;

  int _weekRouteCount(DateTime day) {
    final dn = _dayOnly(day);
    return _shares.where((s) {
      final sd = _dayOnly(s.shareDate);
      final rs = s.routeStartAt != null ? _dayOnly(s.routeStartAt!.toLocal()) : null;
      return sd == dn || rs == dn;
    }).length;
  }

  Color _shiftColor(String? shiftId) {
    try {
      return _shifts.firstWhere((x) => x.id == shiftId).color;
    } catch (_) {
      return Colors.blueGrey.shade400;
    }
  }

  String _dispatchShort(String x) =>
      x == 'staged' ? 'Kladd' : x == 'sent' ? 'Sendt' : x;

  String _ackShort(String x) =>
      x == 'accepted' ? 'OK' : x == 'rejected' ? 'Nei' : 'Vent';

  Color? _vehicleAckDotColor(String vehicleId) {
    final routes = _shares.where((s) => s.partnerVehicleId == vehicleId).toList();
    if (routes.isEmpty) return null;
    if (routes.any((s) => !s.isStaged && s.ackStatus != 'accepted')) return Colors.red;
    if (routes.every((s) => s.isStaged)) return Colors.orange;
    return Colors.green;
  }

  Future<void> _openSapRoutes() async {
    final today = DateTime.now();
    final routeDay = (_weekEnd.isBefore(_dayOnly(today)) || _weekStart.isAfter(_dayOnly(today)))
        ? _focusDay
        : _focusDay;
    final ok = await PartnerSapRoutesSheet.show(
      context,
      fleet: widget.fleet,
      routeDate: routeDay,
    );
    if (mounted) {
      await _refreshSapPendingCount();
      if (ok == true) {
        widget.onChanged?.call();
        await _reload();
      }
    }
  }

  Widget _sapInboxButton() {
    final active = _sapPending > 0;
    return Badge(
      isLabelVisible: active,
      label: Text(
        '$_sapPending',
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
      ),
      backgroundColor: const Color(0xFFFFC107),
      textColor: Colors.black87,
      largeSize: 26,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      offset: const Offset(10, -6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        decoration: active
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFC107).withValues(alpha: 0.75),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.45),
                    blurRadius: 8,
                  ),
                ],
              )
            : null,
        child: FilledButton.icon(
          onPressed: _busy || _maviFleet.isEmpty ? null : _openSapRoutes,
          style: FilledButton.styleFrom(
            backgroundColor: active ? const Color(0xFF0D47A1) : const Color(0xFF1565C0),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          icon: Icon(
            active ? Icons.notifications_active_rounded : Icons.mark_email_read_outlined,
            size: 20,
          ),
          label: Text(
            active ? 'Mottatt fra SAP' : 'Mottatt ruter fra SAP',
            style: TextStyle(
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAutoMass() async {
    final today = DateTime.now();
    final routeDay = (_weekEnd.isBefore(_dayOnly(today)) || _weekStart.isAfter(_dayOnly(today)))
        ? _focusDay
        : _focusDay;
    final ok = await PartnerRouteAutoMassSheet.show(
      context,
      fleet: widget.fleet,
      routeDate: routeDay,
    );
    if (ok == true && mounted) {
      widget.onChanged?.call();
      await _reload();
    }
  }

  int get _pendingStaged => _shares.where((s) => s.isStaged).length;

  void _jumpWeek(DateTime anyDay) => setState(() => _weekStart = _monday(anyDay));

  Future<void> _openSingleAssign({FleetPartnerVehicleRow? row}) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (!mounted || cid == null) return;
    if (_filteredFleet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen MAVI-biler i listen — registrer bil under partner først.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => PartnerRouteSingleAssignSheet(
        companyId: cid,
        fleet: _filteredFleet,
        shifts: _shifts,
        initialDay: _focusDay,
        initialRow: row,
        onDone: () {
          widget.onChanged?.call();
          _reload();
        },
      ),
    );
  }

  Future<void> _openRouteEditor(FleetPartnerVehicleRow row, DateTime day) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (!mounted || cid == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _RouteEditorSheet(
        companyId: cid,
        fleetRow: row,
        day: day,
        shifts: _shifts,
        shares: List.from(_sharesCell(row.vehicle.id, day)),
        onSaved: () {
          widget.onChanged?.call();
          _reload();
        },
        onRoutePlacedOnDate: (routeDay) {
          _jumpWeek(routeDay);
          widget.onChanged?.call();
          _reload();
        },
        allFleet: _maviFleet,
      ),
    );
  }

  /// Synlig meny når kalendercelle har rute(r) — flytt, slett, varsle.
  Future<void> _openRouteManageMenu(
    FleetPartnerVehicleRow row,
    DateTime day,
    List<PartnerRouteShare> shares,
  ) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (!mounted || cid == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _RouteManageSheet(
        companyId: cid,
        fleetRow: row,
        day: day,
        shares: shares,
        shifts: _shifts,
        allFleet: _maviFleet,
        onChanged: () {
          widget.onChanged?.call();
          _reload();
        },
        onOpenFullEditor: () {
          Navigator.pop(ctx);
          _openRouteEditor(row, day);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hdrBg = isDark ? DriftProTheme.cardDark : Colors.white;
    final borderCol = Colors.grey.withValues(alpha: isDark ? 0.35 : 0.22);

    final routeOps = _shifts.where((s) => !s.isAvailability && s.shiftKind == 'route_ops').toList();
    final shiftChoices = routeOps.isNotEmpty ? routeOps : _shifts.where((s) => !s.isAvailability).toList();

    final gridWidth = _days.length * _dayColW;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: borderCol)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top toolbar
          Material(
            color: hdrBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.grid_view_rounded, color: DriftProTheme.primaryGreen, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Rute-planlegger',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                            Text(
                              'Velg dag → «Ny rute» eller trykk tom celle. Sjåfør-rad åpner også opplasting for valgt dag.',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                      if (_busy) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_sapPending > 0)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFC107), width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_read_rounded, color: Color(0xFFF57F17)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$_sapPending rute(r) mottatt fra SAP — klar til import',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF5D4037),
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _openSapRoutes,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Åpne'),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<_PlannerViewMode>(
                        segments: const [
                          ButtonSegment(value: _PlannerViewMode.week, label: Text('Uke'), icon: Icon(Icons.date_range)),
                          ButtonSegment(value: _PlannerViewMode.month, label: Text('Måned'), icon: Icon(Icons.calendar_month)),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) => setState(() => _mode = s.first),
                      ),
                      IconButton.outlined(
                        tooltip: 'Forrige uke',
                        onPressed: () {
                          setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                          _reload();
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '${DateFormat.MMMd('nb_NO').format(_weekStart)} – ${DateFormat.MMMd('nb_NO').format(_weekEnd)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      IconButton.outlined(
                        tooltip: 'Neste uke',
                        onPressed: () {
                          setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                          _reload();
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          final now = _dayOnly(DateTime.now());
                          _focusDay = now;
                          _jumpWeek(now);
                          _reload();
                        },
                        icon: const Icon(Icons.today_outlined),
                        label: const Text('I dag'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: _focusDay,
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (d != null) {
                                  setState(() {
                                    _focusDay = _dayOnly(d);
                                    _jumpWeek(d);
                                  });
                                  await _reload();
                                }
                              },
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text('Dag: ${DateFormat('d.M.y', 'nb').format(_focusDay)}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy || _filteredFleet.isEmpty ? null : () => _openSingleAssign(),
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.accentBlue,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Ny rute'),
                      ),
                      _sapInboxButton(),
                      FilledButton.icon(
                        onPressed: _busy || _maviFleet.isEmpty ? null : _openAutoMass,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(
                          _pendingStaged > 0 ? 'AUTO MASS ($_pendingStaged)' : 'AUTO MASS',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Oppdater'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_mode == _PlannerViewMode.month) ...[
                    SizedBox(
                      height: 300,
                      child: CalendarDatePicker(
                        initialDate: _weekStart,
                        firstDate: DateTime(2023),
                        lastDate: DateTime.now().add(const Duration(days: 540)),
                        onDateChanged: (d) {
                          setState(() {
                            _focusDay = _dayOnly(d);
                            _weekStart = _monday(d);
                            _mode = _PlannerViewMode.week;
                          });
                          _reload();
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Vis skift i rutenett (tom = alle)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('Alle skift')),
                            ...shiftChoices.map(
                              (s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          value: _visibilityShiftId,
                          onChanged: (v) => setState(() => _visibilityShiftId = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Divider(height: 1, thickness: 1, color: borderCol),

          // Master grid row
          SizedBox(
            height: 560,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sidebar (MAVI)
                Container(
                  width: _sidebarW,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: borderCol)),
                    color: (isDark ? DriftProTheme.surfaceDark : const Color(0xFFF9FAFB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Søk MAVI / partner',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: Text(
                          'Sjåfører · MAVI',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _leftVert,
                          itemExtent: _rowHeight,
                          itemCount: _filteredFleet.length,
                          itemBuilder: (_, i) {
                            final row = _filteredFleet[i];
                            final initials =
                                '${row.partner.name.isNotEmpty ? row.partner.name[0] : '?'}{row.vehicle.unitCode.hashCode.abs() % 9}';
                            final shiftsThisWeek =
                                _shares.where((s) => s.partnerVehicleId == row.vehicle.id).length;
                            final ackDot = _vehicleAckDotColor(row.vehicle.id);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _busy ? null : () => _openSingleAssign(row: row),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: Colors.teal.withValues(alpha: 0.3),
                                            child: Text(
                                              initials.substring(0, initials.length.clamp(0, 2)),
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                                            ),
                                          ),
                                          if (ackDot != null)
                                            Positioned(
                                              right: -1,
                                              top: -1,
                                              child: Container(
                                                width: 11,
                                                height: 11,
                                                decoration: BoxDecoration(
                                                  color: ackDot,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 2),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${MaviUnitCodes.normalize(row.vehicle.unitCode)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                            ),
                                            Text(
                                              row.partner.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                            ),
                                            Text(
                                              '$shiftsThisWeek rute(r) i hentet sett',
                                              style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Calendar body
                Expanded(
                  child: Column(
                    children: [
                      // Day headers (horizontal scroll)
                      SizedBox(
                        height: 56,
                        child: SingleChildScrollView(
                          controller: _headerH,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: gridWidth,
                            child: Row(
                              children: _days.map((d) {
                                final now = _dayOnly(DateTime.now());
                                final isToday = _dayOnly(d) == now;
                                final n = _weekRouteCount(d);
                                return Container(
                                  width: _dayColW,
                                  decoration: BoxDecoration(
                                    color: isToday ? Colors.lightBlue.withValues(alpha: 0.12) : null,
                                    border: Border(right: BorderSide(color: borderCol)),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat.E('nb_NO').format(d),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                          color: isToday ? DriftProTheme.accentBlue : null,
                                        ),
                                      ),
                                      Text(DateFormat('d/M', 'nb_NO').format(d), style: const TextStyle(fontSize: 11)),
                                      Text('$n ruter', style: TextStyle(fontSize: 9, color: Colors.grey[700])),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                      Divider(height: 1, color: borderCol),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _bodyH,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: gridWidth,
                            child: ListView.builder(
                              controller: _rightVert,
                              itemExtent: _rowHeight,
                              itemCount: _filteredFleet.length,
                              itemBuilder: (_, i) {
                                final row = _filteredFleet[i];
                                return Row(
                                  children: _days.map((day) {
                                    final list = _sharesCell(row.vehicle.id, day);
                                    final isFocusDay = _dayOnly(day) == _dayOnly(_focusDay);
                                    return InkWell(
                                      onTap: () {
                                        setState(() => _focusDay = _dayOnly(day));
                                        if (list.isEmpty) {
                                          _openRouteEditor(row, day);
                                        } else {
                                          _openRouteManageMenu(row, day, list);
                                        }
                                      },
                                      child: Container(
                                        width: _dayColW,
                                        height: _rowHeight,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(color: borderCol),
                                            bottom: BorderSide(color: borderCol),
                                          ),
                                          color: isFocusDay
                                              ? DriftProTheme.primaryGreen.withValues(alpha: isDark ? 0.08 : 0.04)
                                              : Colors.transparent,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: list.isEmpty
                                                  ? Align(
                                                      alignment: Alignment.topLeft,
                                                      child: Icon(
                                                        Icons.add_circle_outline,
                                                        size: 20,
                                                        color: Colors.grey[400],
                                                      ),
                                                    )
                                                  : ListView(
                                                      padding: EdgeInsets.zero,
                                                      children: [
                                                        for (final s in list.take(2))
                                                          Padding(
                                                            padding: const EdgeInsets.only(bottom: 4),
                                                            child: ClipRRect(
                                                              borderRadius: BorderRadius.circular(6),
                                                              child: Material(
                                                                color: _shiftColor(s.shiftId)
                                                                    .withValues(alpha: isDark ? 0.28 : 0.45),
                                                                child: Padding(
                                                                  padding: const EdgeInsets.symmetric(
                                                                    horizontal: 6,
                                                                    vertical: 5,
                                                                  ),
                                                                  child: Column(
                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          PartnerRoutePdfActions.ackDot(s, size: 8),
                                                                          const SizedBox(width: 4),
                                                                          Expanded(
                                                                            child: Text(
                                                                              TimeOfDay.fromDateTime(s.routeStartAt?.toLocal() ??
                                                                                      DateTime(day.year, day.month, day.day, 6))
                                                                                  .format(context),
                                                                              style: const TextStyle(
                                                                                fontWeight: FontWeight.w900,
                                                                                fontSize: 10,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      Text(
                                                                        s.title?.split('—').first ?? 'Rute',
                                                                        maxLines: 1,
                                                                        overflow: TextOverflow.ellipsis,
                                                                        style: const TextStyle(fontSize: 10),
                                                                      ),
                                                                      Text(
                                                                        '${_dispatchShort(s.dispatchStatus)} · ${_ackShort(s.ackStatus)}',
                                                                        style: TextStyle(
                                                                          fontSize: 8,
                                                                          color: Colors.grey[850],
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        if (list.length > 2)
                                                          Text('+${list.length - 2}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                                      ],
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakt meny: flytt rute, slett, varsle sjåfør på nytt (åpnes fra kalendercelle).
class _RouteManageSheet extends StatefulWidget {
  final String companyId;
  final FleetPartnerVehicleRow fleetRow;
  final DateTime day;
  final List<PartnerRouteShare> shares;
  final List<FleetShiftDefinition> shifts;
  final List<FleetPartnerVehicleRow> allFleet;
  final VoidCallback onChanged;
  final VoidCallback onOpenFullEditor;

  const _RouteManageSheet({
    required this.companyId,
    required this.fleetRow,
    required this.day,
    required this.shares,
    required this.shifts,
    required this.allFleet,
    required this.onChanged,
    required this.onOpenFullEditor,
  });

  @override
  State<_RouteManageSheet> createState() => _RouteManageSheetState();
}

class _RouteManageSheetState extends State<_RouteManageSheet> {
  bool _busy = false;

  String _dispatchLabel(PartnerRouteShare s) =>
      s.isStaged ? 'Kladd' : 'Sendt · aksept ${s.ackStatus == 'accepted' ? 'OK' : s.ackStatus == 'rejected' ? 'Nei' : 'venter'}';

  Future<void> _reassign(PartnerRouteShare s) async {
    final shiftId = s.shiftId ?? widget.shifts.where((x) => !x.isAvailability).firstOrNull?.id;
    if (shiftId == null) return;
    FleetPartnerVehicleRow? chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Flytt rute til annen sjåfør / bil'),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<FleetPartnerVehicleRow>(
              decoration: const InputDecoration(labelText: 'Ny MAVI-bil', border: OutlineInputBorder()),
              isExpanded: true,
              value: chosen,
              items: widget.allFleet
                  .where((r) => r.vehicle.id != widget.fleetRow.vehicle.id)
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r.vehicle.unitCode} · ${r.partner.name}', overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setSt(() => chosen = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: chosen == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Flytt og send SMS'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok != true || chosen == null) return;

    final routeDay = PartnerService.routeDayForShare(s);
    TimeOfDay start = const TimeOfDay(hour: 6, minute: 0);
    if (s.routeStartAt != null) {
      start = TimeOfDay.fromDateTime(s.routeStartAt!.toLocal());
    }
    final at = DateTime(routeDay.year, routeDay.month, routeDay.day, start.hour, start.minute);

    setState(() => _busy = true);
    try {
      await PartnerService.reassignRouteShareToVehicle(
        share: s,
        newTarget: chosen!,
        routeDate: routeDay,
        shiftId: shiftId,
        routeStartAt: at,
      );
      widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rute flyttet til ${chosen!.vehicle.unitCode} — ny sjåfør får SMS')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PartnerRouteShare s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett rute?'),
        content: Text(
          'Fjerner «${s.title ?? 'ruten'}» fra ${widget.fleetRow.vehicle.unitCode}. '
          'Sjåføren ser den ikke lenger.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett rute'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    setState(() => _busy = true);
    try {
      await PartnerService.deleteRouteShare(s);
      widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rute slettet')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _republish(PartnerRouteShare s) async {
    final shiftId = s.shiftId ?? widget.shifts.where((x) => !x.isAvailability).firstOrNull?.id;
    if (shiftId == null) return;
    final routeDay = PartnerService.routeDayForShare(s);
    TimeOfDay start = const TimeOfDay(hour: 6, minute: 0);
    if (s.routeStartAt != null) {
      start = TimeOfDay.fromDateTime(s.routeStartAt!.toLocal());
    }
    final at = DateTime(routeDay.year, routeDay.month, routeDay.day, start.hour, start.minute);

    setState(() => _busy = true);
    try {
      await PartnerService.updateRouteShareFields(s.id, {
        'shift_id': shiftId,
        'route_start_at': at.toUtc().toIso8601String(),
        'share_date': routeDay.toIso8601String().split('T').first,
        if (!s.isStaged) ...{
          'ack_status': 'pending',
          'ack_at': null,
          'ack_by': null,
          'ack_comment': null,
        },
      });
      await PartnerService.dispatchRouteShares(
        companyId: widget.companyId,
        shareIdToShiftId: {s.id: shiftId},
        date: routeDay,
        shareIdToStartAt: {s.id: at},
      );
      widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sjåfør varslet på SMS — må akseptere ruten på nytt')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${MaviUnitCodes.normalize(widget.fleetRow.vehicle.unitCode)} · ${DateFormat.yMMMMEEEEd('nb_NO').format(widget.day)}',
              style: DriftProTheme.headingMd,
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.shares.length} rute${widget.shares.length == 1 ? '' : 'r'} — velg handling',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            ...widget.shares.map((s) {
              final start = s.routeStartAt != null
                  ? TimeOfDay.fromDateTime(s.routeStartAt!.toLocal()).format(context)
                  : '06:00';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          PartnerRoutePdfActions.ackDot(s, size: 10),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.title ?? 'Rute',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      Text('Start $start · ${_dispatchLabel(s)}', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => PartnerRoutePdfActions.openPdf(context, s),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('Vis PDF'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _reassign(s),
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.accentBlue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Flytt til annen sjåfør / bil'),
                      ),
                      const SizedBox(height: 8),
                      if (s.isStaged)
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _republish(s),
                          style: FilledButton.styleFrom(
                            backgroundColor: DriftProTheme.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.rocket_launch_outlined),
                          label: const Text('Publiser & send SMS'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _republish(s),
                          style: FilledButton.styleFrom(
                            backgroundColor: DriftProTheme.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.sms_outlined),
                          label: const Text('Send på nytt (SMS + aksept)'),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _delete(s),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Slett rute'),
                      ),
                    ],
                  ),
                ),
              );
            }),
            TextButton.icon(
              onPressed: _busy ? null : widget.onOpenFullEditor,
              icon: const Icon(Icons.tune),
              label: const Text('Avansert redigering (skift, start, notat)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteEditorSheet extends StatefulWidget {
  final String companyId;
  final FleetPartnerVehicleRow fleetRow;
  final DateTime day;
  final List<FleetShiftDefinition> shifts;
  final List<PartnerRouteShare> shares;
  final VoidCallback onSaved;
  final void Function(DateTime routeDay)? onRoutePlacedOnDate;
  final List<FleetPartnerVehicleRow> allFleet;

  const _RouteEditorSheet({
    required this.companyId,
    required this.fleetRow,
    required this.day,
    required this.shifts,
    required this.shares,
    required this.onSaved,
    this.onRoutePlacedOnDate,
    required this.allFleet,
  });

  @override
  State<_RouteEditorSheet> createState() => _RouteEditorSheetState();
}

class _RouteEditorSheetState extends State<_RouteEditorSheet> {
  bool _busy = false;
  String? _draftShiftId;
  TimeOfDay _draftStart = const TimeOfDay(hour: 6, minute: 0);
  late List<PartnerRouteShare> _live;
  final Map<String, TextEditingController> _noteCtrls = {};
  final Map<String, TimeOfDay> _startByShare = {};
  final Map<String, String?> _shiftByShare = {};

  @override
  void initState() {
    super.initState();
    _live = List.from(widget.shares);
    final routeOps =
        widget.shifts.where((s) => !s.isAvailability && s.shiftKind == 'route_ops').toList();
    final pick = routeOps.isNotEmpty ? routeOps.first : widget.shifts.where((x) => !x.isAvailability).firstOrNull;
    _draftShiftId = pick?.id;
    for (final s in _live) {
      _noteCtrls[s.id] = TextEditingController(text: s.notes ?? '');
      _startByShare[s.id] = s.routeStartAt != null
          ? TimeOfDay.fromDateTime(s.routeStartAt!.toLocal())
          : const TimeOfDay(hour: 6, minute: 0);
      _shiftByShare[s.id] = s.shiftId ?? _draftShiftId;
    }
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) return;

    setState(() => _busy = true);
    try {
      final cid = widget.companyId;
      final row = widget.fleetRow;
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = 'company_$cid/partner_routes/'
          '${DateTime.now().millisecondsSinceEpoch}_${row.vehicle.unitCode}_$safeName';
      final storedPath =
          await PartnerService.uploadPartnerRoutePdf(storagePath: path, bytes: bytes);
      String? pdfExtract;
      try {
        pdfExtract = RoutePdfTextService.extractFullText(bytes);
      } catch (_) {
        pdfExtract = _extractViaSyncfusion(bytes);
      }
      final schedule = RoutePdfTextService.resolveSchedule(
        pdfExtract ?? '',
        fallbackDate: widget.day,
      );
      final routeDay = schedule.routeDate;
      final startAt = schedule.routeStartAt ??
          DateTime(routeDay.year, routeDay.month, routeDay.day, _draftStart.hour, _draftStart.minute);
      final created = await PartnerService.addRouteShare(
        PartnerRouteShare(
          id: '',
          partnerId: row.partner.id,
          companyId: cid,
          title: 'Rute ${row.vehicle.unitCode} — ${file.name}',
          pdfStoragePath: storedPath,
          shareDate: routeDay,
          isDailyShare: true,
          dispatchStatus: 'staged',
          shiftId: _draftShiftId,
          partnerVehicleId: row.vehicle.id,
          notes: _noteCtrls['_new']?.text,
          createdAt: DateTime.now(),
          pdfSearchText: pdfExtract?.isEmpty ?? true ? null : pdfExtract,
        ),
      );
      if ((pdfExtract ?? '').isNotEmpty) await PartnerService.saveRoutePdfSearchText(created.id, pdfExtract!.trim());

      await PartnerService.updateRouteShareFields(
        created.id,
        {
          'shift_id': _draftShiftId,
          'notes': created.notes ?? '',
          'route_start_at': startAt.toUtc().toIso8601String(),
        },
      );
      final placedOnPdfDay = _dayOnly(routeDay) == _dayOnly(widget.day);
      if (placedOnPdfDay) {
        setState(() {
          _live.add(created.copyWithMerged(shiftId: _draftShiftId, notes: created.notes, routeStartAt: startAt.toUtc()));
          _noteCtrls[created.id] = TextEditingController(text: '');
          if (schedule.routeStartAt != null) {
            _startByShare[created.id] = TimeOfDay.fromDateTime(startAt);
          }
        });
        widget.onSaved();
      } else {
        widget.onRoutePlacedOnDate?.call(routeDay);
      }

      if (mounted) {
        final dayLabel = DateFormat('d.M.y').format(routeDay);
        final timeLabel = schedule.routeStartAt != null
            ? DateFormat('HH:mm').format(startAt.toLocal())
            : null;
        final msg = placedOnPdfDay
            ? 'PDF lagt i kladd for ${row.vehicle.unitCode} — $dayLabel${timeLabel != null ? ' kl. $timeLabel' : ''} fra PDF'
            : 'Rute lagt på $dayLabel${timeLabel != null ? ' kl. $timeLabel' : ''} fra PDF (kalenderen hoppet til riktig uke)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Klarte ikke laste opp: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _extractViaSyncfusion(Uint8List bytes) {
    try {
      final doc = PdfDocument(inputBytes: bytes);
      final ex = PdfTextExtractor(doc);
      final t = ex.extractText();
      doc.dispose();
      return t.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _saveDraft(PartnerRouteShare s) async {
    final shiftId = _shiftByShare[s.id];
    final start = _startByShare[s.id] ?? const TimeOfDay(hour: 6, minute: 0);
    final routeDay = PartnerService.routeDayForShare(s);
    final at = DateTime(routeDay.year, routeDay.month, routeDay.day, start.hour, start.minute);
    setState(() => _busy = true);
    try {
      await PartnerService.updateRouteShareFields(s.id, {
        'notes': _noteCtrls[s.id]?.text,
        if (shiftId != null) 'shift_id': shiftId,
        'route_start_at': at.toUtc().toIso8601String(),
        'share_date': routeDay.toIso8601String().split('T').first,
      });
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isStaged ? 'Kladd lagret' : 'Endringer lagret')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reassignRoute(PartnerRouteShare s) async {
    final shiftId = _shiftByShare[s.id] ?? s.shiftId ?? _draftShiftId;
    if (shiftId == null) return;
    FleetPartnerVehicleRow? chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Flytt rute til annen bil / sjåfør'),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<FleetPartnerVehicleRow>(
              decoration: const InputDecoration(
                labelText: 'Ny MAVI-bil',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              value: chosen,
              items: widget.allFleet
                  .where((r) => r.vehicle.id != widget.fleetRow.vehicle.id)
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r.vehicle.unitCode} · ${r.partner.name}', overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setSt(() => chosen = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: chosen == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Flytt og send SMS'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok != true || chosen == null) return;

    final start = _startByShare[s.id] ?? const TimeOfDay(hour: 6, minute: 0);
    final routeDay = PartnerService.routeDayForShare(s);
    final at = DateTime(routeDay.year, routeDay.month, routeDay.day, start.hour, start.minute);
    setState(() => _busy = true);
    try {
      await PartnerService.reassignRouteShareToVehicle(
        share: s,
        newTarget: chosen!,
        routeDate: routeDay,
        shiftId: shiftId,
        routeStartAt: at,
      );
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rute flyttet til ${chosen!.vehicle.unitCode} — ny sjåfør får SMS og må akseptere',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRoute(PartnerRouteShare s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern rute?'),
        content: Text(
          'Fjerner «${s.title ?? 'ruten'}» fra ${widget.fleetRow.vehicle.unitCode}. '
          'Sjåføren ser den ikke lenger i portalen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fjern'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    setState(() => _busy = true);
    try {
      await PartnerService.deleteRouteShare(s);
      setState(() {
        _live.removeWhere((x) => x.id == s.id);
        _noteCtrls.remove(s.id)?.dispose();
        _startByShare.remove(s.id);
        _shiftByShare.remove(s.id);
      });
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rute fjernet')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishOne(PartnerRouteShare s) async {
    final shiftItems = widget.shifts.where((x) => !x.isAvailability).toList();
    final shiftId = _shiftByShare[s.id] ?? s.shiftId ?? _draftShiftId;
    final start = _startByShare[s.id] ?? const TimeOfDay(hour: 6, minute: 0);
    if (shiftItems.isEmpty || shiftId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final routeDay = PartnerService.routeDayForShare(s);
      final at = DateTime(routeDay.year, routeDay.month, routeDay.day, start.hour, start.minute);
      await PartnerService.updateRouteShareFields(s.id, {
        'shift_id': shiftId,
        'notes': _noteCtrls[s.id]?.text,
        'route_start_at': at.toUtc().toIso8601String(),
        'share_date': routeDay.toIso8601String().split('T').first,
        if (!s.isStaged) ...{
          'ack_status': 'pending',
          'ack_at': null,
          'ack_by': null,
          'ack_comment': null,
        },
      });
      await PartnerService.dispatchRouteShares(
        companyId: widget.companyId,
        shareIdToShiftId: {s.id: shiftId},
        date: routeDay,
        shareIdToStartAt: {s.id: at},
      );
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.isStaged
                  ? 'Rute publisert — sjåfør får SMS og må akseptere'
                  : 'Rute oppdatert — sjåfør får ny SMS og må akseptere på nytt',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _ackShortStatic(String x) =>
      x == 'accepted' ? 'OK' : x == 'rejected' ? 'Nei' : 'Venter';

  @override
  Widget build(BuildContext context) {
    final shiftItems = widget.shifts.where((s) => !s.isAvailability).toList();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${MaviUnitCodes.normalize(widget.fleetRow.vehicle.unitCode)} • ${widget.fleetRow.partner.name}',
              style: DriftProTheme.headingMd,
            ),
            Text(DateFormat.yMMMMEEEEd('nb_NO').format(widget.day)),
            const SizedBox(height: 14),
            if (_live.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  'Administrer ruter: flytt til annen sjåfør, slett, eller send SMS på nytt.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ruter på denne dagen',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ..._live.map((s) {
                final shiftId = _shiftByShare[s.id] ?? s.shiftId ?? _draftShiftId ?? (shiftItems.isNotEmpty ? shiftItems.first.id : null);
                final start = _startByShare[s.id] ?? const TimeOfDay(hour: 6, minute: 0);
                if (shiftId == null) {
                  return Card(child: ListTile(title: Text(s.title ?? 'Rute'), subtitle: const Text('Mangler skift')));
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            PartnerRoutePdfActions.ackDot(s, size: 11),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.title ?? s.pdfStoragePath.split('/').last,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${s.isStaged ? 'Kladd' : 'Sendt'} · Aksept: ${_ackShortStatic(s.ackStatus)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => PartnerRoutePdfActions.openPdf(context, s),
                              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                              label: const Text('Vis PDF'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => PartnerRoutePdfActions.openPdf(context, s),
                              icon: const Icon(Icons.download_outlined, size: 18),
                              label: const Text('Last ned'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Skift', border: OutlineInputBorder(), isDense: true),
                          isExpanded: true,
                          value: shiftId,
                          items: shiftItems.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(),
                          onChanged: (v) => setState(() => _shiftByShare[s.id] = v),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Planlagt start'),
                          subtitle: Text(
                            '${DateFormat('d.M.y').format(PartnerService.routeDayForShare(s))} kl. ${start.format(context)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          trailing: const Icon(Icons.schedule),
                          onTap: () async {
                            final t = await showTimePicker(context: context, initialTime: start);
                            if (t != null) setState(() => _startByShare[s.id] = t);
                          },
                        ),
                        TextField(
                          controller: _noteCtrls[s.id],
                          decoration: const InputDecoration(
                            labelText: 'Notat til sjåfør / intern kommentar',
                            border: OutlineInputBorder(),
                          ),
                          minLines: 2,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _busy ? null : () => _saveDraft(s),
                              child: Text(s.isStaged ? 'Lagre kladd' : 'Lagre endringer'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _reassignRoute(s),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text('Flytt til annen bil'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _deleteRoute(s),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Slett rute'),
                            ),
                            FilledButton(
                              onPressed: _busy ? null : () => _publishOne(s),
                              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                              child: Text(s.isStaged ? 'Publiser & send SMS' : 'Oppdater & varsle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const Divider(height: 28),
            ],
            const Text(
              'Legg til ny rute-PDF',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Skift for ny PDF', border: OutlineInputBorder(), isDense: true),
              isExpanded: true,
              value: _draftShiftId,
              items: shiftItems.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              onChanged: (v) => setState(() => _draftShiftId = v),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Planlagt start (ny pdf)'),
              subtitle: Text(
                _draftStart.format(context),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _draftStart);
                if (t != null) setState(() => _draftStart = t);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickPdf,
                    style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.upload_file),
                    label: const Text('Last opp PDF (kladd)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_live.isEmpty && shiftItems.isNotEmpty && _draftShiftId != null)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _pickPdf();
                        if (!mounted || _live.isEmpty) return;
                        await _publishOne(_live.last);
                      },
                icon: const Icon(Icons.rocket_launch_outlined),
                label: const Text('Last opp PDF og publiser med én gang'),
              ),
            if (_live.isEmpty) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Ingen ruter på denne dagen ennå — last opp PDF eller vent på import.', style: TextStyle(color: Colors.grey[700])),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on PartnerRouteShare {
  PartnerRouteShare copyWithMerged({
    String? shiftId,
    String? notes,
    DateTime? routeStartAt,
  }) {
    return PartnerRouteShare(
      id: id,
      partnerId: partnerId,
      companyId: companyId,
      title: title,
      pdfStoragePath: pdfStoragePath,
      shareDate: shareDate,
      isDailyShare: isDailyShare,
      notes: notes ?? this.notes,
      ackStatus: ackStatus,
      ackAt: ackAt,
      ackBy: ackBy,
      ackComment: ackComment,
      shiftId: shiftId ?? this.shiftId,
      partnerVehicleId: partnerVehicleId,
      routeStartAt: routeStartAt ?? this.routeStartAt,
      dispatchStatus: dispatchStatus,
      pdfSearchText: pdfSearchText,
      createdAt: createdAt,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
