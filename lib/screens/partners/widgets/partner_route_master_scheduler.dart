import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/layout/mobile_layout.dart';
import '../../../core/constants/route_dispatch_status.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/sap_route_inbox_live.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/partner/route_shift_resolver.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/route_notify_prefs.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/route_ack_nudge_result.dart';
import '../../../models/partner/route_reminder_flag.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_partner_status.dart';
import 'route_calendar_chip.dart';
import 'route_publish_notify_buttons.dart';
import 'route_reminder_badge.dart';
import 'partner_route_planner_ui.dart';
import 'partner_route_single_assign_sheet.dart';
import 'partner_route_auto_mass_sheet.dart';
import 'partner_sap_routes_sheet.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

DateTime _monday(DateTime d) {
  final n = DateTime(d.year, d.month, d.day);
  return n.subtract(Duration(days: n.weekday - DateTime.monday));
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Løsemiddel-visning inspirert av arbeidsplan: MAVI-navigasjon til venstre, kalender til høyre.
class PartnerRouteMasterScheduler extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final VoidCallback? onChanged;
  final List<Widget> leadingSlivers;
  final bool nestedScroll;

  const PartnerRouteMasterScheduler({
    super.key,
    required this.fleet,
    this.onChanged,
    this.leadingSlivers = const [],
    this.nestedScroll = false,
  });

  @override
  State<PartnerRouteMasterScheduler> createState() => _PartnerRouteMasterSchedulerState();
}

class _PartnerRouteMasterSchedulerState extends State<PartnerRouteMasterScheduler>
    with WidgetsBindingObserver {
  bool _busy = false;
  RoutePlannerViewMode _mode = RoutePlannerViewMode.week;
  DateTime _weekStart = _monday(DateTime.now());
  DateTime _focusDay = _dayOnly(DateTime.now());
  late final TextEditingController _searchCtrl;

  List<FleetShiftDefinition> _shifts = [];
  List<PartnerRouteShare> _shares = [];
  Map<String, RouteReminderFlag> _reminderFlags = {};
  int _sapInboxPending = 0;
  int _manualStagedCount = 0;
  int _sapStagedCount = 0;
  Timer? _sapPollTimer;
  RealtimeChannel? _sapLiveChannel;

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));
  List<DateTime> get _days =>
      List.generate(7, (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i));

  static const double _rowHeight = 96;
  static const double _dayHeaderHeight = 88;
  static const double _sidebarW = 220;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchCtrl = TextEditingController()..addListener(() => setState(() {}));
    _reload();
    _sapPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshSapPendingCount();
    });
    _bindSapLive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSapPendingCount();
    }
  }

  Future<void> _bindSapLive() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (!mounted || cid == null) return;
    SapRouteInboxLive.unsubscribe(_sapLiveChannel);
    _sapLiveChannel = SapRouteInboxLive.subscribe(
      companyId: cid,
      onChanged: () => _refreshSapPendingCount(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sapPollTimer?.cancel();
    SapRouteInboxLive.unsubscribe(_sapLiveChannel);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PartnerRouteMasterScheduler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fleet != oldWidget.fleet) _reload();
  }

  Future<void> _reload({bool light = false}) async {
    if (!light) setState(() => _busy = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      if (!light) await PartnerService.ensureCanonicalFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final shares = await PartnerService.fetchRouteSharesForCalendarWindow(
        companyId: cid,
        fromDay: _weekStart,
        toDay: _weekEnd,
      );
      if (!light) await PartnerService.reconcileSapInboxWithStagedQueue(cid);
      final sapInbox = await PartnerService.countSapRouteInboxPending(cid);
      final manualStaged = await PartnerService.countStagedRouteShares(
        cid,
        importSource: PartnerService.stagedImportManual,
      );
      final sapStaged = await PartnerService.countStagedRouteShares(
        cid,
        importSource: PartnerService.stagedImportSap,
      );
      final reminders = await PartnerService.fetchRouteReminderFlags(
        shares.map((s) => s.id),
      );
      if (mounted) setState(() {
        _shifts = shifts;
        _shares = shares;
        _reminderFlags = reminders;
        _sapInboxPending = sapInbox;
        _manualStagedCount = manualStaged;
        _sapStagedCount = sapStaged;
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
      await PartnerService.reconcileSapInboxWithStagedQueue(cid);
      final inbox = await PartnerService.countSapRouteInboxPending(cid);
      final manualStaged = await PartnerService.countStagedRouteShares(
        cid,
        importSource: PartnerService.stagedImportManual,
      );
      final sapStaged = await PartnerService.countStagedRouteShares(
        cid,
        importSource: PartnerService.stagedImportSap,
      );
      if (mounted &&
          (inbox != _sapInboxPending ||
              manualStaged != _manualStagedCount ||
              sapStaged != _sapStagedCount)) {
        setState(() {
          _sapInboxPending = inbox;
          _manualStagedCount = manualStaged;
          _sapStagedCount = sapStaged;
        });
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

  bool _shareOnDay(PartnerRouteShare s, DateTime day) {
    final dn = _dayOnly(day);
    final sd = _dayOnly(s.shareDate);
    final rs = s.routeStartAt != null ? _dayOnly(s.routeStartAt!.toLocal()) : null;
    return sd == dn || rs == dn;
  }

  bool _needsAck(PartnerRouteShare s) => s.requiresAck;

  int _pendingAckCountForDay(DateTime day) =>
      _shares.where((s) => _shareOnDay(s, day) && _needsAck(s)).length;

  void _showNudgeSnack(RouteAckNudgeResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.ok ? null : Colors.red.shade700,
      ),
    );
  }

  Future<void> _nudgePendingForDay(DateTime day) async {
    final n = _pendingAckCountForDay(day);
    if (n == 0) {
      _showNudgeSnack(const RouteAckNudgeResult(
        ok: false,
        message: 'Ingen ruter venter på aksept denne dagen.',
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send purring?'),
        content: Text(
          'Sender SMS/e-post til $n partner(e) som ikke har akseptert ruten '
          'på ${DateFormat('EEEE d. MMMM', 'nb').format(day)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Purr ($n)'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await PartnerService.nudgePendingRouteAcksForDay(day);
      _showNudgeSnack(result);
      if (result.ok) await _reload(light: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<void> nudgeOneRoute(
    BuildContext context, {
    required PartnerRouteShare share,
    required VoidCallback onDone,
    required void Function(bool) setBusy,
  }) async {
    if (!share.requiresAck) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ruten er publisert uten varsel — purring gjelder ikke.'),
          ),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send purring?'),
        content: Text(
          'Partner får SMS/e-post om å akseptere «${share.title ?? 'ruten'}».',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Purr'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setBusy(true);
    try {
      final result = await PartnerService.nudgeRouteAck(share.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.ok ? null : Colors.red.shade700,
          ),
        );
        if (result.ok) onDone();
      }
    } finally {
      if (context.mounted) setBusy(false);
    }
  }

  Future<void> _clearAllRoutesForDay(DateTime day) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null || !mounted) return;
    final n = _weekRouteCount(day);
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tøm hele dagen?'),
        content: Text(
          'Fjerner alle $n rute(r) fra alle sjåfører på '
          '${DateFormat('EEEE d. MMMM yyyy', 'nb').format(day)}.\n\n'
          'Kladd og publiserte ruter slettes. Dette kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Tøm dag'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final removed = await PartnerService.clearRouteSharesForCompanyDay(
        companyId: cid,
        day: day,
      );
      widget.onChanged?.call();
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fjernet $removed rute(r) fra ${DateFormat('d.M.y', 'nb').format(day)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke tømme dag: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _shiftColor(String? shiftId) {
    try {
      return _shifts.firstWhere((x) => x.id == shiftId).color;
    } catch (_) {
      return Colors.blueGrey.shade400;
    }
  }

  String _dispatchShort(String x) => RouteDispatchStatus.shortLabel(x);

  String _ackShort(String x) =>
      x == 'accepted' ? 'OK' : x == 'rejected' ? 'Nei' : 'Vent';

  Color? _vehicleAckDotColor(String vehicleId) {
    final routes = _shares.where((s) => s.partnerVehicleId == vehicleId).toList();
    if (routes.isEmpty) return null;
    routes.sort((a, b) => _shareDotPriority(a).compareTo(_shareDotPriority(b)));
    return RouteDispatchStatus.cellColorForShare(routes.first);
  }

  int _shareDotPriority(PartnerRouteShare s) {
    if (s.isStaged) return 0;
    if (s.isRegistered) return 1;
    if (s.ackStatus == 'rejected') return 2;
    if (s.requiresAck) return 3;
    if (s.isSentWithNotify && !s.pdfWasOpened) return 4;
    if (s.pdfWasOpened && s.requiresAck) return 5;
    if (s.ackStatus == 'accepted') return 6;
    return 7;
  }

  String? _shiftName(String? shiftId) => shiftNameFor(_shifts, shiftId);

  List<RoutePlannerAction> _plannerActions() {
    final hasQueue = _sapStagedCount > 0;
    final hasInbox = _sapInboxPending > 0;
    final sapActive = hasQueue || hasInbox;
    String? sapBadge;
    if (hasQueue && hasInbox) {
      sapBadge = '$_sapStagedCount · $_sapInboxPending nye';
    } else if (hasQueue) {
      sapBadge = '$_sapStagedCount i kø';
    } else if (hasInbox) {
      sapBadge = '$_sapInboxPending nye';
    }

    return [
      RoutePlannerAction(
        icon: Icons.add_circle_outline,
        title: 'Ny rute',
        subtitle: 'Last opp PDF og tildel én sjåfør',
        color: DriftProTheme.accentBlue,
        onPressed: _busy || _filteredFleet.isEmpty ? null : _openSingleAssign,
      ),
      RoutePlannerAction(
        icon: Icons.auto_awesome,
        title: 'Auto masse',
        subtitle: 'Mange PDF-er — smart tildeling',
        color: const Color(0xFF6A1B9A),
        badge: _manualStagedCount > 0 ? '$_manualStagedCount' : null,
        onPressed: _busy || _maviFleet.isEmpty ? null : _openAutoMass,
      ),
      RoutePlannerAction(
        icon: sapActive ? Icons.notifications_active_rounded : Icons.inbox_outlined,
        title: 'SAP-innboks',
        subtitle: hasInbox ? 'Nye ruter fra SAP' : 'Importer og send SAP-ruter',
        color: const Color(0xFF1565C0),
        badge: sapBadge,
        badgeColor: const Color(0xFFFFC107),
        glow: sapActive,
        onPressed: _busy || _maviFleet.isEmpty ? null : _openSapRoutes,
      ),
    ];
  }

  Future<void> _pickFocusDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _focusDay,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() {
        _focusDay = _dayOnly(d);
        _refreshSapPendingCount();
        _jumpWeek(d);
      });
      await _reload();
    }
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
        await _reload(light: true);
      }
    }
  }

  Future<void> _openAutoMass() async {
    final today = DateTime.now();
    final routeDay = (_weekEnd.isBefore(_dayOnly(today)) || _weekStart.isAfter(_dayOnly(today)))
        ? _focusDay
        : _focusDay;
    final ok = await PartnerRouteMassDispatchSheet.show(
      context,
      fleet: widget.fleet,
      routeDate: routeDay,
      source: PartnerRouteMassSource.manual,
    );
    if (ok == true && mounted) {
      widget.onChanged?.call();
      await _reload(light: true);
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
    await PartnerRouteSingleAssignSheet.show(
      context,
      companyId: cid,
      fleet: _filteredFleet,
      shifts: _shifts,
      initialDay: _focusDay,
      initialRow: row,
      onDone: () {
        widget.onChanged?.call();
        _reload(light: true);
      },
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
        reminderFlags: _reminderFlags,
        onSaved: () {
          widget.onChanged?.call();
          _reload(light: true);
        },
        onRoutePlacedOnDate: (routeDay) {
          _jumpWeek(routeDay);
          widget.onChanged?.call();
          _reload(light: true);
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
        reminderFlags: _reminderFlags,
        onChanged: () {
          widget.onChanged?.call();
          _reload(light: true);
        },
        onOpenFullEditor: () {
          Navigator.pop(ctx);
          _openRouteEditor(row, day);
        },
      ),
    );
  }

  Widget _buildToolbarContent(bool isDark, Color hdrBg, Color borderCol) {
    return Material(
      color: hdrBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RoutePlannerUi.header(context: context, busy: _busy),
            const SizedBox(height: 14),
            RoutePlannerUi.dateNavigator(
              weekStart: _weekStart,
              weekEnd: _weekEnd,
              focusDay: _focusDay,
              mode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
              onPrevWeek: () {
                setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                _reload();
              },
              onNextWeek: () {
                setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                _reload();
              },
              onToday: () {
                final now = _dayOnly(DateTime.now());
                setState(() {
                  _focusDay = now;
                  _jumpWeek(now);
                });
                _reload();
              },
              onPickDay: _busy ? null : _pickFocusDay,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 720;
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: RoutePlannerUi.searchField(controller: _searchCtrl),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: RoutePlannerUi.focusDayActions(
                          context: context,
                          focusDay: _focusDay,
                          pendingAck: _pendingAckCountForDay(_focusDay),
                          routeCount: _weekRouteCount(_focusDay),
                          onNudge: _busy ? null : () => _nudgePendingForDay(_focusDay),
                          onClear: _busy ? null : () => _clearAllRoutesForDay(_focusDay),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RoutePlannerUi.searchField(controller: _searchCtrl),
                    const SizedBox(height: 10),
                    RoutePlannerUi.focusDayActions(
                      context: context,
                      focusDay: _focusDay,
                      pendingAck: _pendingAckCountForDay(_focusDay),
                      routeCount: _weekRouteCount(_focusDay),
                      onNudge: _busy ? null : () => _nudgePendingForDay(_focusDay),
                      onClear: _busy ? null : () => _clearAllRoutesForDay(_focusDay),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            RoutePlannerUi.actionGrid(
              context: context,
              actions: _plannerActions(),
              trailing: RoutePlannerUi.refreshButton(
                onPressed: _busy ? null : _reload,
              ),
            ),
            const SizedBox(height: 10),
            RoutePlannerUi.statusLegend(),
            if (_mode == RoutePlannerViewMode.month) ...[
              const SizedBox(height: 10),
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
                      _mode = RoutePlannerViewMode.week;
                    });
                    _reload();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedWeekHeader(Color borderCol, bool isDark) {
    final hdrBg = isDark ? DriftProTheme.cardDark : Colors.white;
    return Material(
      color: hdrBg,
      elevation: 2,
      child: SizedBox(
        height: _dayHeaderHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: _sidebarW,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: borderCol),
                  bottom: BorderSide(color: borderCol),
                ),
                color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF8FAFC),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              alignment: Alignment.bottomLeft,
              child: const Text(
                'Sjåfører · MAVI',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
              ),
            ),
            Expanded(child: _buildDayHeaderRow(borderCol)),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedDriverRow(
    BuildContext context,
    FleetPartnerVehicleRow row,
    bool isDark,
    Color borderCol,
  ) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _sidebarW,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: borderCol),
                bottom: BorderSide(color: borderCol),
              ),
              color: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF8FAFC),
            ),
            child: _buildSidebarRow(row, borderCol),
          ),
          Expanded(child: _buildFleetGridRow(context, row, isDark, borderCol)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (DriftProClient.isMobile) {
      return _buildMobilePlanner(context);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hdrBg = isDark ? DriftProTheme.cardDark : Colors.white;
    final borderCol = Colors.grey.withValues(alpha: isDark ? 0.35 : 0.22);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (widget.nestedScroll)
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
        ...widget.leadingSlivers,
        SliverToBoxAdapter(
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              side: BorderSide(color: borderCol),
            ),
            child: _buildToolbarContent(isDark, hdrBg, borderCol),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _PlannerPinnedHeaderDelegate(
            height: _dayHeaderHeight,
            child: _buildPinnedWeekHeader(borderCol, isDark),
          ),
        ),
        if (_filteredFleet.isEmpty)
          SliverToBoxAdapter(
            child: Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                side: BorderSide(color: borderCol),
              ),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Ingen MAVI-biler i listen.')),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _buildCombinedDriverRow(
                context,
                _filteredFleet[i],
                isDark,
                borderCol,
              ),
              childCount: _filteredFleet.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  Widget _buildMobilePlanner(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderCol = Colors.grey.withValues(alpha: isDark ? 0.35 : 0.22);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (widget.nestedScroll)
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
        ...widget.leadingSlivers,
        SliverToBoxAdapter(child: _buildMobileToolbar(isDark, borderCol)),
        SliverToBoxAdapter(child: _buildMobileDayStrip(isDark, borderCol)),
        SliverToBoxAdapter(child: _buildMobileDayActions(isDark)),
        if (_filteredFleet.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Ingen MAVI-biler i listen.')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildMobileDriverCard(
                  context,
                  _filteredFleet[i],
                  isDark,
                  borderCol,
                ),
                childCount: _filteredFleet.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: MobileLayout.shellBottomInset(context) + 96),
        ),
      ],
    );
  }

  Widget _buildMobileToolbar(bool isDark, Color borderCol) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderCol),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RoutePlannerUi.header(
              context: context,
              busy: _busy,
              subtitle: 'Trykk på en sjåfør for å legge til eller administrere ruter.',
            ),
            const SizedBox(height: 12),
            RoutePlannerUi.dateNavigator(
              weekStart: _weekStart,
              weekEnd: _weekEnd,
              focusDay: _focusDay,
              mode: _mode,
              compact: true,
              onModeChanged: (m) => setState(() => _mode = m),
              onPrevWeek: () {
                setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
                _reload();
              },
              onNextWeek: () {
                setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));
                _reload();
              },
              onToday: () {
                final now = _dayOnly(DateTime.now());
                setState(() {
                  _focusDay = now;
                  _jumpWeek(now);
                });
                _reload();
              },
              onPickDay: _busy ? null : _pickFocusDay,
            ),
            const SizedBox(height: 12),
            RoutePlannerUi.searchField(controller: _searchCtrl),
            const SizedBox(height: 12),
            RoutePlannerUi.actionGrid(
              context: context,
              actions: _plannerActions(),
              trailing: RoutePlannerUi.refreshButton(
                onPressed: _busy ? null : _reload,
              ),
            ),
            if (_mode == RoutePlannerViewMode.month) ...[
              const SizedBox(height: 10),
              CalendarDatePicker(
                initialDate: _weekStart,
                firstDate: DateTime(2023),
                lastDate: DateTime.now().add(const Duration(days: 540)),
                onDateChanged: (d) {
                  setState(() {
                    _focusDay = _dayOnly(d);
                    _weekStart = _monday(d);
                    _mode = RoutePlannerViewMode.week;
                  });
                  _reload();
                },
              ),
            ],
            const SizedBox(height: 8),
            RoutePlannerUi.statusLegend(scrollable: true),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDayStrip(bool isDark, Color borderCol) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final d = _days[i];
            final now = _dayOnly(DateTime.now());
            final isToday = _dayOnly(d) == now;
            final isFocus = _dayOnly(d) == _dayOnly(_focusDay);
            final n = _weekRouteCount(d);
            return Material(
              color: isFocus
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.14)
                  : isDark
                      ? DriftProTheme.cardDark
                      : Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _focusDay = _dayOnly(d));
                  _refreshSapPendingCount();
                },
                child: Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isFocus
                          ? DriftProTheme.primaryGreen
                          : isToday
                              ? DriftProTheme.accentBlue.withValues(alpha: 0.5)
                              : borderCol,
                      width: isFocus ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat.E('nb_NO').format(d),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: isFocus ? DriftProTheme.primaryGreenDark : null,
                        ),
                      ),
                      Text(
                        DateFormat('d/M', 'nb_NO').format(d),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '$n ruter',
                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMobileDayActions(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: RoutePlannerUi.focusDayActions(
        context: context,
        focusDay: _focusDay,
        pendingAck: _pendingAckCountForDay(_focusDay),
        routeCount: _weekRouteCount(_focusDay),
        compact: true,
        onNudge: _busy ? null : () => _nudgePendingForDay(_focusDay),
        onClear: _busy ? null : () => _clearAllRoutesForDay(_focusDay),
      ),
    );
  }

  Widget _buildMobileDriverCard(
    BuildContext context,
    FleetPartnerVehicleRow row,
    bool isDark,
    Color borderCol,
  ) {
    final day = _focusDay;
    final list = _sharesCell(row.vehicle.id, day);
    final mavi = MaviUnitCodes.compactLabel(row.vehicle.unitCode);
    final ackDot = _vehicleAckDotColor(row.vehicle.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderCol),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy
            ? null
            : () {
                if (list.isEmpty) {
                  _openRouteEditor(row, day);
                } else {
                  _openRouteManageMenu(row, day, list);
                }
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.teal.withValues(alpha: 0.25),
                        child: Text(
                          mavi.length >= 2 ? mavi.substring(0, 2) : mavi,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      if (ackDot != null)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: ackDot,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mavi,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        Text(
                          row.partner.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                        Text(
                          row.vehicle.fleetRolesLabel,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    list.isEmpty ? Icons.add_circle_outline : Icons.chevron_right,
                    color: list.isEmpty ? Colors.grey : DriftProTheme.primaryGreen,
                  ),
                ],
              ),
              if (list.isEmpty) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openRouteEditor(row, day),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Legg til rute'),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in list)
                      _buildMobileRouteChip(context, s, day, isDark),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileRouteChip(
    BuildContext context,
    PartnerRouteShare s,
    DateTime day,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RouteCalendarChip(
          share: s,
          day: day,
          isDark: isDark,
          shiftColor: _shiftColor(s.shiftId),
          shiftName: _shiftName(s.shiftId),
        ),
        if (s.isSentWithNotify) ...[
          const SizedBox(height: 6),
          PartnerRoutePartnerStatus(share: s, compact: true),
        ],
      ],
    );
  }

  Widget _buildSidebarRow(FleetPartnerVehicleRow row, Color borderCol) {
    final initials =
        '${row.partner.name.isNotEmpty ? row.partner.name[0] : '?'}${row.vehicle.unitCode.hashCode.abs() % 9}';
    final ackDot = _vehicleAckDotColor(row.vehicle.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => _openSingleAssign(row: row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      MaviUnitCodes.normalize(row.vehicle.unitCode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    Text(
                      row.partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, height: 1.1, color: Colors.grey[700]),
                    ),
                    Text(
                      row.vehicle.fleetRolesLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, height: 1.1, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayHeaderRow(Color borderCol) {
    return SizedBox(
      height: _dayHeaderHeight,
      child: Row(
        children: _days.map((d) {
          final now = _dayOnly(DateTime.now());
          final isToday = _dayOnly(d) == now;
          final isFocus = _dayOnly(d) == _dayOnly(_focusDay);
          final n = _weekRouteCount(d);
          final pendingAck = _pendingAckCountForDay(d);
          return Expanded(
            child: Container(
            decoration: BoxDecoration(
              color: isFocus
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.1)
                  : isToday
                      ? Colors.lightBlue.withValues(alpha: 0.1)
                      : null,
              border: Border(right: BorderSide(color: borderCol)),
            ),
            padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.E('nb_NO').format(d),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: isFocus
                        ? DriftProTheme.primaryGreen
                        : isToday
                            ? DriftProTheme.accentBlue
                            : null,
                  ),
                ),
                Text(
                  DateFormat('d/M', 'nb_NO').format(d),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 10, height: 1.1),
                ),
                Text(
                  '$n ruter${pendingAck > 0 ? ' · $pendingAck venter' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, height: 1.2, color: Colors.grey[700]),
                ),
                if (n > 0) ...[
                  const SizedBox(height: 3),
                  RoutePlannerUi.dayColumnActions(
                    pendingAck: pendingAck,
                    onNudge: _busy ? null : () => _nudgePendingForDay(d),
                    onClear: _busy ? null : () => _clearAllRoutesForDay(d),
                  ),
                ],
              ],
            ),
          ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFleetGridRow(
    BuildContext context,
    FleetPartnerVehicleRow row,
    bool isDark,
    Color borderCol,
  ) {
    return Row(
      children: _days.map((day) {
        final list = _sharesCell(row.vehicle.id, day);
        final isFocusDay = _dayOnly(day) == _dayOnly(_focusDay);
        return Expanded(
          child: InkWell(
          onTap: () {
            setState(() => _focusDay = _dayOnly(day));
            _refreshSapPendingCount();
            if (list.isEmpty) {
              _openRouteEditor(row, day);
            } else {
              _openRouteManageMenu(row, day, list);
            }
          },
          child: Container(
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
            child: _buildDayCell(context, row, day, list, isDark),
          ),
        ),
        );
      }).toList(),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    FleetPartnerVehicleRow row,
    DateTime day,
    List<PartnerRouteShare> list,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: list.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Icon(Icons.add_circle_outline, size: 20, color: Colors.grey[400]),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  children: [
                    for (final s in list.take(2))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: RouteCalendarChip(
                          share: s,
                          day: day,
                          isDark: isDark,
                          shiftColor: _shiftColor(s.shiftId),
                          shiftName: _shiftName(s.shiftId),
                          compact: true,
                        ),
                      ),
                    if (list.length > 2)
                      Text('+${list.length - 2}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                  ],
                ),
        ),
      ],
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
  final Map<String, RouteReminderFlag> reminderFlags;
  final VoidCallback onChanged;
  final VoidCallback onOpenFullEditor;

  const _RouteManageSheet({
    required this.companyId,
    required this.fleetRow,
    required this.day,
    required this.shares,
    required this.shifts,
    required this.allFleet,
    required this.reminderFlags,
    required this.onChanged,
    required this.onOpenFullEditor,
  });

  @override
  State<_RouteManageSheet> createState() => _RouteManageSheetState();
}

class _RouteManageSheetState extends State<_RouteManageSheet> {
  bool _busy = false;

  String _dispatchLabel(PartnerRouteShare s) {
    if (s.isStaged) return 'Kladd';
    if (s.isRegistered) return 'Registrert uten varsel';
    return 'Varslet · aksept ${s.ackStatus == 'accepted' ? 'OK' : s.ackStatus == 'rejected' ? 'Nei' : 'venter'}';
  }

  Future<void> _reassign(PartnerRouteShare s) async {
    final shiftId = s.shiftId ?? widget.shifts.where((x) => !x.isAvailability).firstOrNull?.id;
    if (shiftId == null) return;
    FleetPartnerVehicleRow? chosen;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Flytt rute til annen sjåfør / bil'),
          content: MobileDialogBody(
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

  Future<void> _nudge(PartnerRouteShare s) async {
    await _PartnerRouteMasterSchedulerState.nudgeOneRoute(
      context,
      share: s,
      onDone: widget.onChanged,
      setBusy: (v) => setState(() => _busy = v),
    );
  }

  Future<void> _dispatchShare(PartnerRouteShare s, {RouteNotifyPrefs? notifyPrefs}) async {
    final prefs = notifyPrefs ?? RouteNotifyPrefs.none;
    final notifyDriver = prefs.anyEnabled;
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
        if (notifyDriver && !s.isStaged) ...{
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
        notifyDriver: notifyDriver,
        notifyPrefs: prefs,
      );
      widget.onChanged();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notifyDriver
                  ? 'Sjåfør varslet (${prefs.shortLabel})'
                  : 'Rute registrert i kalender — ingen varsel sendt',
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
                      if (s.isSentWithNotify) ...[
                        const SizedBox(height: 8),
                        PartnerRoutePartnerStatus(share: s, compact: false),
                      ],
                      RouteReminderBadge(
                        share: s,
                        flag: widget.reminderFlags[s.id],
                      ),
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
                        label: const Text('Flytt rute'),
                      ),
                      const SizedBox(height: 8),
                      if (s.isStaged || s.isRegistered || s.isSentWithNotify) ...[
                        const SizedBox(height: 8),
                        RoutePublishNotifyButtons(
                          busy: _busy,
                          showWithoutNotify: s.isStaged || s.isRegistered,
                          onPublish: (prefs) => _dispatchShare(
                            s,
                            notifyPrefs: prefs ?? RouteNotifyPrefs.none,
                          ),
                        ),
                      ],
                      if (s.requiresAck) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _nudge(s),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade50,
                            foregroundColor: Colors.orange.shade900,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Purr'),
                        ),
                      ],
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
  final Map<String, RouteReminderFlag> reminderFlags;

  const _RouteEditorSheet({
    required this.companyId,
    required this.fleetRow,
    required this.day,
    required this.shifts,
    required this.shares,
    required this.reminderFlags,
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
  final Map<String, String> _pdfSuggestedShiftByShare = {};
  String? _pendingNotifyShareId;

  PartnerRouteShare? get _pendingNotifyShare {
    final id = _pendingNotifyShareId;
    if (id == null) return null;
    for (final s in _live) {
      if (s.id == id) return s;
    }
    return null;
  }

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
    unawaited(_bootstrapShiftsFromPdf());
  }

  Future<void> _bootstrapShiftsFromPdf() async {
    for (final s in _live) {
      try {
        final pdfText = await RouteShiftResolver.loadPdfTextForShare(s);
        final resolved = await RouteShiftResolver.resolveShiftIdForStagedShare(
          share: s,
          allShifts: widget.shifts,
          pdfText: pdfText,
        );
        if (resolved == null || resolved.isEmpty || !mounted) continue;
        setState(() {
          _pdfSuggestedShiftByShare[s.id] = resolved;
          _shiftByShare[s.id] = resolved;
        });
      } catch (_) {}
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
      final routeOps = widget.shifts
          .where((s) => !s.isAvailability && s.shiftKind == 'route_ops')
          .toList();
      final shiftPool = routeOps.isNotEmpty
          ? routeOps
          : widget.shifts.where((x) => !x.isAvailability).toList();
      final autoShift = await RouteShiftResolver.resolveBestFromPdfText(
        pdfText: pdfExtract,
        shifts: shiftPool,
        routeStartAt: startAt,
        routeDate: routeDay,
      );
      final shiftId = autoShift?.id ?? _draftShiftId;
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
          shiftId: shiftId,
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
          'shift_id': shiftId,
          'notes': created.notes ?? '',
          'route_start_at': startAt.toUtc().toIso8601String(),
        },
      );
      final placedOnPdfDay = _dayOnly(routeDay) == _dayOnly(widget.day);
      if (placedOnPdfDay) {
        setState(() {
          _live.add(created.copyWithMerged(shiftId: shiftId, notes: created.notes, routeStartAt: startAt.toUtc()));
          _noteCtrls[created.id] = TextEditingController(text: '');
          if (schedule.routeStartAt != null) {
            _startByShare[created.id] = TimeOfDay.fromDateTime(startAt);
          }
          _shiftByShare[created.id] = shiftId;
          if (shiftId != null) _pdfSuggestedShiftByShare[created.id] = shiftId;
          _pendingNotifyShareId = created.id;
        });
        widget.onSaved();
      } else {
        widget.onRoutePlacedOnDate?.call(routeDay);
      }

      if (mounted && !placedOnPdfDay) {
        final dayLabel = DateFormat('d.M.y').format(routeDay);
        final timeLabel = schedule.routeStartAt != null
            ? DateFormat('HH:mm').format(startAt.toLocal())
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rute lagt på $dayLabel${timeLabel != null ? ' kl. $timeLabel' : ''} fra PDF (kalenderen hoppet til riktig uke)',
            ),
          ),
        );
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
          content: MobileDialogBody(
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

  Future<void> _publishOne(
    PartnerRouteShare s, {
    required bool notifyDriver,
    RouteNotifyPrefs notifyPrefs = RouteNotifyPrefs.all,
    bool closeSheet = true,
  }) async {
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
        if (notifyDriver && !s.isStaged) ...{
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
        notifyDriver: notifyDriver,
        notifyPrefs: notifyPrefs,
      );
      widget.onSaved();
      if (mounted) {
        if (closeSheet) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notifyDriver && notifyPrefs.anyEnabled
                  ? (s.isStaged
                      ? 'Rute publisert — varsling: ${notifyPrefs.shortLabel}'
                      : 'Rute oppdatert — varsling: ${notifyPrefs.shortLabel}')
                  : 'Rute registrert i kalender — ingen varsel sendt',
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

  Future<void> _finishPendingNotify({RouteNotifyPrefs? prefs}) async {
    final share = _pendingNotifyShare;
    if (share == null) return;

    if (prefs == null || !prefs.anyEnabled) {
      setState(() => _pendingNotifyShareId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF lagret som kladd — ingen varsel sendt')),
        );
      }
      return;
    }

    await _publishOne(
      share,
      notifyDriver: true,
      notifyPrefs: prefs,
      closeSheet: false,
    );
    if (mounted) {
      setState(() {
        _pendingNotifyShareId = null;
        final i = _live.indexWhere((s) => s.id == share.id);
        if (i >= 0) {
          _live[i] = _live[i].copyWithMerged(dispatchStatus: 'sent');
        }
      });
    }
  }

  Widget _buildPostUploadNotifyPanel() {
    final share = _pendingNotifyShare;
    if (share == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: DriftProTheme.primaryGreen, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PDF lastet opp — velg varsel',
                  style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            share.title ?? 'Ny rute',
            style: DriftProTheme.bodySm.copyWith(color: Colors.grey.shade700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _finishPendingNotify(prefs: RouteNotifyPrefs.smsOnly),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            icon: const Icon(Icons.sms_outlined),
            label: const Text('Varsle med SMS'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : () => _finishPendingNotify(prefs: RouteNotifyPrefs.pushOnly),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Varsle med push (app)'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : () => _finishPendingNotify(prefs: RouteNotifyPrefs.smsAndPush),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Varsle med SMS + push'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _finishPendingNotify(),
            child: const Text('Gå videre uten å varsle'),
          ),
        ],
      ),
    );
  }

  String _ackShortStatic(String x) => switch (x) {
        'accepted' => 'OK',
        'rejected' => 'Nei',
        'not_required' => 'Ikke påkrevd',
        _ => 'Venter',
      };

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
                          s.isRegistered
                              ? 'Registrert uten varsel — ingen aksept eller purring'
                              : '${s.isStaged ? 'Kladd' : 'Sendt'} · Aksept: ${_ackShortStatic(s.ackStatus)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (s.isSentWithNotify) ...[
                          const SizedBox(height: 8),
                          PartnerRoutePartnerStatus(share: s),
                        ],
                        RouteReminderBadge(
                          share: s,
                          flag: widget.reminderFlags[s.id],
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
                          decoration: const InputDecoration(
                            labelText: 'Skift (endres før send)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          isExpanded: true,
                          value: shiftId,
                          items: shiftItems.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(),
                          onChanged: (v) => setState(() => _shiftByShare[s.id] = v),
                        ),
                        RoutePdfShiftSuggestionButton(
                          shifts: widget.shifts,
                          suggestedShiftId: _pdfSuggestedShiftByShare[s.id],
                          selectedShiftId: shiftId,
                          onApply: () => setState(() => _shiftByShare[s.id] = _pdfSuggestedShiftByShare[s.id]),
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
                        if (s.isStaged || s.isRegistered || s.isSentWithNotify)
                          RoutePublishNotifyButtons(
                            busy: _busy,
                            compact: true,
                            showWithoutNotify: s.isStaged || s.isRegistered,
                            onPublish: (prefs) {
                              if (prefs == null || !prefs.anyEnabled) {
                                return _publishOne(s, notifyDriver: false);
                              }
                              return _publishOne(
                                s,
                                notifyDriver: true,
                                notifyPrefs: prefs,
                              );
                            },
                          ),
                        if (s.isStaged || s.isRegistered || s.isSentWithNotify)
                          const SizedBox(height: 8),
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
                            if (s.requiresAck)
                              FilledButton.tonal(
                                onPressed: _busy
                                    ? null
                                    : () => _PartnerRouteMasterSchedulerState.nudgeOneRoute(
                                          context,
                                          share: s,
                                          onDone: widget.onSaved,
                                          setBusy: (v) => setState(() => _busy = v),
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.orange.shade50,
                                  foregroundColor: Colors.orange.shade900,
                                ),
                                child: const Text('Purr'),
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
                    onPressed: (_busy || _pendingNotifyShareId != null) ? null : _pickPdf,
                    style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                    icon: _busy
                        ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                        : const Icon(Icons.upload_file),
                    label: const Text('Last opp PDF (kladd)'),
                  ),
                ),
              ],
            ),
            if (_pendingNotifyShareId != null) _buildPostUploadNotifyPanel(),
            const SizedBox(height: 8),
            if (_live.isEmpty && shiftItems.isNotEmpty && _draftShiftId != null)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        await _pickPdf();
                        if (!mounted || _live.isEmpty) return;
                        await _publishOne(_live.last, notifyDriver: true);
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

class _PlannerPinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _PlannerPinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PlannerPinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

extension on PartnerRouteShare {
  PartnerRouteShare copyWithMerged({
    String? shiftId,
    String? notes,
    DateTime? routeStartAt,
    String? dispatchStatus,
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
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
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
