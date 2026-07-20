import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/mobile_layout.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

DateTime _weekStartMonday(DateTime d) {
  final n = DateTime(d.year, d.month, d.day);
  return n.subtract(Duration(days: n.weekday - DateTime.monday));
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _snapLabel(String status) {
  switch (status) {
    case 'har_rute':
      return 'Har rute';
    case 'ledig':
      return 'Ledig';
    case 'fri':
      return 'Fri';
    case 'gitt_bort':
      return 'Gitt bort';
    default:
      return status;
  }
}

String _ackLong(String ack) {
  switch (ack) {
    case 'accepted':
      return 'Akseptert';
    case 'rejected':
      return 'Avslått';
    default:
      return 'Venter';
  }
}

String _dispatchLong(String d) {
  switch (d) {
    case 'staged':
      return 'Kladd (ikke sendt)';
    case 'registered':
      return 'Registrert uten varsel';
    case 'sent':
      return 'Varslet (SMS + portal)';
    default:
      return d;
  }
}

/// Data for dra-og-slipp av rute mellom celler (samme dag).
class _RouteDragPayload {
  final PartnerRouteShare share;
  final FleetPartnerVehicleRow fromRow;
  final DateTime day;

  const _RouteDragPayload({
    required this.share,
    required this.fromRow,
    required this.day,
  });
}

/// Uke-/kalender-/flåteoversikt: alle MAVI, rute, aksept, fri-søknad, flåtestatus.
class PartnerRouteWeekCommandPanel extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final VoidCallback? onChanged;

  const PartnerRouteWeekCommandPanel({
    super.key,
    required this.fleet,
    this.onChanged,
  });

  @override
  State<PartnerRouteWeekCommandPanel> createState() => _PartnerRouteWeekCommandPanelState();
}

class _PartnerRouteWeekCommandPanelState extends State<PartnerRouteWeekCommandPanel> {
  bool _busy = false;
  DateTime _weekStart = _weekStartMonday(DateTime.now());
  String? _shiftId;
  List<FleetShiftDefinition> _shifts = [];
  List<PartnerRouteShare> _sharesAll = [];
  List<PartnerVehicleFleetSnapshot> _snapsWeek = [];
  List<PartnerFriRequest> _friRequests = [];
  DateTime? _listDay;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PartnerRouteWeekCommandPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fleet != oldWidget.fleet) {
      _reload();
    }
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i));

  void _ensureListDayInWeek() {
    final days = _weekDays;
    if (days.isEmpty) return;

    DateTime pickDefault() {
      final now = _dayOnly(DateTime.now());
      for (final d in days) {
        if (_dayOnly(d) == now) return d;
      }
      return days.first;
    }

    if (_listDay == null) {
      _listDay = pickDefault();
      return;
    }
    if (!days.any((d) => _dayOnly(d) == _dayOnly(_listDay!))) {
      _listDay = days.first;
    }
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final routeOps = shifts.where((s) => !s.isAvailability && s.shiftKind == 'route_ops').toList();
      final selectable = routeOps.isNotEmpty ? routeOps : shifts.where((s) => !s.isAvailability).toList();

      final weekEnd = _weekStart.add(const Duration(days: 6));
      final shares = await PartnerService.fetchRouteSharesForCalendarWindow(
        companyId: cid,
        fromDay: _weekStart,
        toDay: weekEnd,
      );
      final snaps = await PartnerService.fetchFleetSnapshotsRange(
        companyId: cid,
        from: _weekStart,
        to: weekEnd,
      );
      final fri = await PartnerService.fetchFriRequests(
        companyId: cid,
        requestDateFrom: _weekStart,
        requestDateTo: weekEnd,
      );

      String? sid = _shiftId;
      if (sid == null || !selectable.any((s) => s.id == sid)) {
        sid = selectable.isNotEmpty ? selectable.first.id : null;
      }

      if (mounted) {
        setState(() {
          _shifts = shifts;
          _shiftId = sid;
          _sharesAll = shares;
          _snapsWeek = snaps;
          _friRequests = fri;
          _ensureListDayInWeek();
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  PartnerRouteShare? _shareFor(String? vehicleId, DateTime day, String shift) {
    if (vehicleId == null) return null;
    final dn = _dayOnly(day);
    PartnerRouteShare? best;
    for (final s in _sharesAll) {
      if (s.partnerVehicleId != vehicleId) continue;
      if (s.dispatchStatus == 'staged') continue;
      if (s.shiftId != null && s.shiftId != shift) continue;

      final sd = _dayOnly(s.shareDate);
      final rs = s.routeStartAt != null ? _dayOnly(s.routeStartAt!.toLocal()) : null;
      final dayMatches = sd == dn || (rs != null && rs == dn);
      if (!dayMatches) continue;

      if (best == null || s.createdAt.isAfter(best.createdAt)) best = s;
    }
    return best;
  }

  PartnerVehicleFleetSnapshot? _snapFor(String vehicleId, DateTime day, String shift) {
    final ds = day.toIso8601String().split('T').first;
    for (final sn in _snapsWeek) {
      if (sn.partnerVehicleId != vehicleId) continue;
      if (sn.shiftId != shift) continue;
      if (sn.snapshotDate.toIso8601String().split('T').first != ds) continue;
      return sn;
    }
    return null;
  }

  PartnerFriRequest? _friFor(String? vehicleId, DateTime day) {
    if (vehicleId == null) return null;
    final ds = day.toIso8601String().split('T').first;
    PartnerFriRequest? best;
    for (final f in _friRequests) {
      if (f.partnerVehicleId != vehicleId) continue;
      if (f.requestDate.toIso8601String().split('T').first != ds) continue;
      if (best == null || f.createdAt.isAfter(best.createdAt)) best = f;
    }
    return best;
  }

  Future<void> _performReassign({
    required PartnerRouteShare share,
    required FleetPartnerVehicleRow fromRow,
    required FleetPartnerVehicleRow toRow,
    required DateTime day,
  }) async {
    final shift = _shiftId;
    if (!mounted || shift == null) return;
    if (fromRow.vehicle.id == toRow.vehicle.id) return;

    setState(() => _busy = true);
    try {
      final routeDay = PartnerService.routeDayForShare(share);
      DateTime? startAt;
      if (share.routeStartAt != null) {
        final t = TimeOfDay.fromDateTime(share.routeStartAt!.toLocal());
        startAt = DateTime(routeDay.year, routeDay.month, routeDay.day, t.hour, t.minute);
      }
      await PartnerService.reassignRouteShareToVehicle(
        share: share,
        newTarget: toRow,
        routeDate: day,
        shiftId: shift,
        routeStartAt: startAt,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rute flyttet fra ${fromRow.vehicle.unitCode} til ${toRow.vehicle.unitCode}')),
        );
      }
      widget.onChanged?.call();
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunne ikke flytte: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReassign(PartnerRouteShare share, FleetPartnerVehicleRow fromRow, DateTime day) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    final shift = _shiftId;
    if (!mounted || cid == null || shift == null) return;

    FleetPartnerVehicleRow? chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('Flytt rute til annen sjåfør / bil'),
            content: MobileDialogBody(
              child: DropdownButtonFormField<FleetPartnerVehicleRow>(
                decoration: const InputDecoration(
                  labelText: 'Ny bil (MAVI)',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                value: chosen,
                items: widget.fleet
                    .where((r) => r.vehicle.id != fromRow.vehicle.id)
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
                child: const Text('Flytt og varsle'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || ok != true || chosen == null) return;
    await _performReassign(share: share, fromRow: fromRow, toRow: chosen!, day: day);
  }

  Future<void> _onDragAccept(_RouteDragPayload payload, FleetPartnerVehicleRow targetRow, DateTime cellDay) async {
    if (!mounted || _busy) return;
    if (_dayOnly(payload.day) != _dayOnly(cellDay)) return;
    if (payload.fromRow.vehicle.id == targetRow.vehicle.id) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bekreft flytting'),
        content: Text(
          'Flytt rute-PDF fra ${payload.fromRow.vehicle.unitCode} til '
          '${targetRow.vehicle.unitCode} (${DateFormat.yMMMd('nb_NO').format(payload.day)})?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, flytt')),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    await _performReassign(
      share: payload.share,
      fromRow: payload.fromRow,
      toRow: targetRow,
      day: cellDay,
    );
  }

  void _openCellDetail({
    required FleetPartnerVehicleRow row,
    required DateTime day,
    required PartnerRouteShare? share,
    required PartnerVehicleFleetSnapshot? snap,
    required PartnerFriRequest? fri,
  }) {
    final shift = _shiftId;
    if (shift == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(row.vehicle.unitCode, style: DriftProTheme.headingMd),
              Text(row.partner.name, style: TextStyle(color: Colors.grey[700])),
              const Divider(height: 24),
              Text('Dag: ${DateFormat.yMMMd('nb_NO').format(day)}', style: DriftProTheme.headingSm),
              const SizedBox(height: 8),
              Text('Flåtestatus (snapshot): ${snap != null ? _snapLabel(snap.status) : '—'}'),
              if (share != null) ...[
                const SizedBox(height: 6),
                Text('Fordeling: ${_dispatchLong(share.dispatchStatus)}'),
                Text('Aksept i portal: ${_ackLong(share.ackStatus)}'),
                if (share.dispatchStatus != 'staged')
                  Text(
                    'SMS-varsling: forsøkt ved utsendelse (se leverandørlogg hvis aktivt)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ] else
                const Text('Ingen rute-PDF på denne dagen for filtrert skift.'),
              if (fri != null) ...[
                const SizedBox(height: 8),
                Text('Fri-søknad: ${fri.status} · ${fri.reason ?? ''}'),
              ],
              const SizedBox(height: 8),
              const Text(
                'Langt trykk på celle med rute → dra til annen bil samme dag.',
                style: TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 16),
              if (share != null && share.dispatchStatus != 'staged')
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openReassign(share, row, day);
                  },
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Flytt rute til annen bil'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouteCell({
    required FleetPartnerVehicleRow row,
    required DateTime day,
    required double dayColW,
    required String shift,
  }) {
    final share = _shareFor(row.vehicle.id, day, shift);
    final snap = _snapFor(row.vehicle.id, day, shift);
    final fri = _friFor(row.vehicle.id, day);

    Color bg = Colors.grey.withValues(alpha: 0.12);
    String mark = '';
    if (fri != null && fri.status == 'pending') {
      bg = Colors.orange.withValues(alpha: 0.2);
      mark = '!';
    } else if (fri != null && fri.status == 'approved') {
      bg = DriftProTheme.accentBlue.withValues(alpha: 0.18);
    }
    if (share != null) {
      if (share.ackStatus == 'accepted') {
        bg = Colors.green.withValues(alpha: 0.25);
        mark = mark.isEmpty ? '✓' : mark;
      } else if (share.ackStatus == 'rejected') {
        bg = Colors.red.withValues(alpha: 0.15);
        mark = '✗';
      } else {
        bg = Colors.amber.withValues(alpha: 0.2);
        mark = mark.isEmpty ? '…' : mark;
      }
    } else if (snap != null) {
      switch (snap.status) {
        case 'har_rute':
          bg = Colors.green.withValues(alpha: 0.15);
          break;
        case 'fri':
          bg = DriftProTheme.accentBlue.withValues(alpha: 0.15);
          break;
        case 'gitt_bort':
          bg = Colors.deepOrange.withValues(alpha: 0.15);
          break;
        case 'ledig':
          bg = Colors.blueGrey.withValues(alpha: 0.1);
          break;
      }
    }

    _RouteDragPayload? payload;
    if (share != null && share.dispatchStatus != 'staged') {
      payload = _RouteDragPayload(share: share, fromRow: row, day: day);
    }

    Widget core = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCellDetail(row: row, day: day, share: share, snap: snap, fri: fri),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: dayColW - 1,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Text(mark, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ),
    );

    if (payload != null) {
      core = LongPressDraggable<_RouteDragPayload>(
        data: payload,
        delay: const Duration(milliseconds: 280),
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: dayColW + 20,
            padding: const EdgeInsets.all(6),
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.9),
            child: Text(
              payload.share.title ?? '${payload.fromRow.vehicle.unitCode} · rute',
              style: const TextStyle(fontSize: 10, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: core),
        child: Tooltip(message: 'Langt trykk og dra for å flytte rute', child: core),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 1),
      child: DragTarget<_RouteDragPayload>(
        onWillAcceptWithDetails: (details) {
          final d = details.data;
          final sameDay = _dayOnly(d.day) == _dayOnly(day);
          final otherVehicle = d.fromRow.vehicle.id != row.vehicle.id;
          return sameDay && otherVehicle;
        },
        onAcceptWithDetails: (details) => _onDragAccept(details.data, row, day),
        builder: (ctx, cand, rej) {
          final highlight = cand.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(highlight ? 2 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: highlight ? Border.all(color: DriftProTheme.primaryGreen, width: 2) : null,
            ),
            child: core,
          );
        },
      ),
    );
  }

  Widget _buildDayDriverList(String shift, DateTime listDay) {
    final dn = DateFormat.yMMMd('nb_NO').format(listDay);
    final rows = <DataRow>[];
    for (final row in widget.fleet) {
      final share = _shareFor(row.vehicle.id, listDay, shift);
      final snap = _snapFor(row.vehicle.id, listDay, shift);
      final fri = _friFor(row.vehicle.id, listDay);

      rows.add(DataRow(cells: [
        DataCell(Text(row.vehicle.unitCode, style: const TextStyle(fontWeight: FontWeight.w700))),
        DataCell(Text(row.partner.name, overflow: TextOverflow.ellipsis)),
        DataCell(Text(snap != null ? _snapLabel(snap.status) : '—')),
        DataCell(Text(share != null ? 'Ja' : 'Nei')),
        DataCell(Text(share != null ? _dispatchLong(share.dispatchStatus) : '—')),
        DataCell(Text(share != null
            ? (share.dispatchStatus == 'sent'
                ? 'Forsøkt (SMS-RPC)'
                : '—')
            : '—')),
        DataCell(Text(share != null ? _ackLong(share.ackStatus) : '—')),
        DataCell(Text(fri != null ? fri.status : '—')),
      ]));
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Full liste sjåfører · $dn', style: DriftProTheme.headingSm),
            const SizedBox(height: 4),
            Text(
              'Alle MAVI-er for valgt dag og skift. PDF = ruterad i databasen. SMS-status følger utsendelse fra DriftPro.',
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (_, c) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth),
                  child: DataTable(
                    columnSpacing: 16,
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 48,
                    columns: const [
                      DataColumn(label: Text('MAVI')),
                      DataColumn(label: Text('Partner')),
                      DataColumn(label: Text('Flåte')),
                      DataColumn(label: Text('Rute PDF')),
                      DataColumn(label: Text('Fordelt')),
                      DataColumn(label: Text('SMS / varsel')),
                      DataColumn(label: Text('Aksept')),
                      DataColumn(label: Text('Fri-søknad')),
                    ],
                    rows: rows,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shift = _shiftId;
    final routeShifts = _shifts.where((s) => !s.isAvailability).toList();
    final listDay = _listDay ?? (_weekDays.isNotEmpty ? _weekDays.first : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_view_week, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Uke-kommandosentral',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                if (_busy) SizedBox(width: 20, height: 20, child: DriftProLoadingIndicator(size: 20)),
                IconButton(
                  tooltip: 'Oppdater',
                  onPressed: _busy ? null : _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Data hentes med datofilter (ukevindu + ev. kjørestart). Langt trykk på rute-celle og dra til annen kolonne '
              '(samme dag) flytter PDF-ruten til annen MAVI.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                          _reload();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${DateFormat.MMMd('nb_NO').format(_weekStart)} – '
                      '${DateFormat.MMMd('nb_NO').format(_weekStart.add(const Duration(days: 6)))}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                          _reload();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() => _weekStart = _weekStartMonday(DateTime.now()));
                          _reload();
                        },
                  child: const Text('Denne uken'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: shift,
              decoration: const InputDecoration(
                labelText: 'Ruteskift (tabell og liste filtrerer på dette skiftet der det finnes)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: routeShifts
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
                          Expanded(child: Text(s.name)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) {
                      setState(() => _shiftId = v);
                    },
            ),
            if (shift != null && widget.fleet.isNotEmpty) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final dayColW = constraints.maxWidth < 720 ? 36.0 : 44.0;
                  final labelColW = constraints.maxWidth < 720 ? 100.0 : 140.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: labelColW,
                              child: const Text('Bil', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                            ..._weekDays.map((d) {
                              return SizedBox(
                                width: dayColW,
                                child: Text(
                                  DateFormat.E('nb_NO').format(d).substring(0, 2).toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                                ),
                              );
                            }),
                          ],
                        ),
                        ...widget.fleet.map((row) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: labelColW,
                                  child: Text(
                                    row.vehicle.unitCode,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                ..._weekDays.map((day) {
                                  return _buildRouteCell(
                                    row: row,
                                    day: day,
                                    dayColW: dayColW,
                                    shift: shift,
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        const Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            _LegendChip(color: Color(0x4000C853), label: 'Rute akseptert'),
                            _LegendChip(color: Color(0x33FFC107), label: 'Venter på aksept'),
                            _LegendChip(color: Color(0x26EF5350), label: 'Avslått rute'),
                            _LegendChip(color: Color(0x33FF9800), label: 'Fri søkt (venter)'),
                            _LegendChip(color: Color(0x2E1565C0), label: 'Fri godkjent'),
                            _LegendChip(color: Color(0x1A607D8B), label: 'Ledig / annen status'),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ] else if (widget.fleet.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Ingen biler ennå — registrer kjøretøy under Samarbeidspartnere.'),
              ),
            if (shift != null && listDay != null && widget.fleet.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Dag for detaljliste', style: DriftProTheme.headingSm),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _weekDays.map((d) {
                    final sel = _dayOnly(d) == _dayOnly(listDay);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(DateFormat.E('nb_NO').format(d)),
                        selected: sel,
                        onSelected: (_) => setState(() => _listDay = d),
                      ),
                    );
                  }).toList(),
                ),
              ),
              _buildDayDriverList(shift, listDay),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
