import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';
import '../../../core/constants/sap_routes_config.dart';
import '../../../core/services/partner/fleet_shift_filters.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/postal_code_registry.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/partner/route_shift_resolver.dart';
import '../../../core/services/partner/sap_route_import_service.dart';
import '../../../core/services/partner/sap_route_inbox_live.dart';
import '../../../core/services/notification/publish_action_labels.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/notification_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/sap_route_inbox.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_publish_review_dialog.dart';
import 'partner_route_workflow_ui.dart';

class _PdfAssignmentRow {
  final String fileName;
  final String status; // ok | skipped
  final String? maviCode;
  final String? stowingLane;
  final String? driverLabel;
  final String? routeDateLabel;
  final String? reason;

  const _PdfAssignmentRow({
    required this.fileName,
    required this.status,
    this.maviCode,
    this.stowingLane,
    this.driverLabel,
    this.routeDateLabel,
    this.reason,
  });
}

class _SkippedPdf {
  final String fileName;
  final Uint8List bytes;
  final String? reason;
  final String? detectedCode;
  final String? sapInboxId;
  String? selectedVehicleId;
  String? shiftId;
  TimeOfDay startTime;
  final TextEditingController noteCtrl;

  _SkippedPdf({
    required this.fileName,
    required this.bytes,
    this.reason,
    this.detectedCode,
    this.sapInboxId,
    TimeOfDay? startTime,
  })  : startTime = startTime ?? const TimeOfDay(hour: 6, minute: 0),
        noteCtrl = TextEditingController();
}

enum PartnerRouteMassSource { manual, sap }

enum _MassTab { allRoutes, drivers, missingShift, importLog, skipped }

enum _RouteQueueFilter { all, missingShift, ready, selected }

enum _DateQueueAction { clearAll, publishNoSms, publishSms }

/// Felles popup: AUTO MASS (manuell PDF) og Ruter fra SAP (auto-import + samme UI).
class PartnerRouteMassDispatchSheet extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final DateTime initialRouteDate;
  final PartnerRouteMassSource source;

  const PartnerRouteMassDispatchSheet({
    super.key,
    required this.fleet,
    required this.initialRouteDate,
    this.source = PartnerRouteMassSource.manual,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<FleetPartnerVehicleRow> fleet,
    DateTime? routeDate,
    PartnerRouteMassSource source = PartnerRouteMassSource.manual,
  }) {
    return showPartnerRouteWorkflowDialog<bool>(
      context,
      child: PartnerRouteMassDispatchSheet(
        fleet: fleet,
        initialRouteDate: routeDate ?? DateTime.now(),
        source: source,
      ),
    );
  }

  @override
  State<PartnerRouteMassDispatchSheet> createState() => _PartnerRouteMassDispatchSheetState();
}

typedef PartnerRouteAutoMassSheet = PartnerRouteMassDispatchSheet;

class _PartnerRouteMassDispatchSheetState extends State<PartnerRouteMassDispatchSheet> {
  bool _loading = true;
  bool _busyUpload = false;
  bool _publishing = false;
  List<PartnerRouteShare> _staged = [];
  final List<_SkippedPdf> _skipped = [];
  final Set<String> _selected = {};
  final Map<String, String> _shiftByShare = {};
  final Map<String, TimeOfDay?> _startByShare = {};
  final Map<String, TextEditingController> _noteByShare = {};
  List<FleetShiftDefinition> _shifts = [];
  Map<String, PartnerPortalAccount> _portalByVehicle = {};
  List<_PdfAssignmentRow> _importLog = [];
  final Map<String, String> _stowingByShare = {};
  late DateTime _routeDate;
  final Map<String, DateTime> _dateByShare = {};
  DateTime? _filterDay;
  _MassTab _sheetTab = _MassTab.allRoutes;
  _RouteQueueFilter _queueFilter = _RouteQueueFilter.all;
  bool _sapSyncing = false;
  int _sapPendingInbox = 0;
  RealtimeChannel? _sapLiveChannel;
  bool _showAllDrivers = false;
  bool _guideExpanded = false;
  final Set<String> _expandedShareIds = {};
  bool _fillingShifts = false;
  bool _initialTabSet = false;
  String _withNotifyLabel = 'Med varsel';
  NotificationChannel _massChannel = NotificationChannel.both;

  bool get _isSap => widget.source == PartnerRouteMassSource.sap;

  _MassUi get _ui => _MassUi.of(widget.source);

  List<FleetShiftDefinition> get _routeShifts =>
      FleetShiftFilters.forRouteAssignment(_shifts);

  int get _driversWithRoutesCount => _routesByVehicle.length;

  List<PartnerRouteShare> get _routesMissingShift =>
      _staged.where((s) => _effectiveShiftId(s.id) == null).toList();

  int get _missingShiftCount => _routesMissingShift.length;

  int get _readyShiftCount => _staged.length - _missingShiftCount;

  DateTime _routeDayFor(String shareId) {
    final cached = _dateByShare[shareId];
    if (cached != null) return cached;
    final share = _staged.where((s) => s.id == shareId).firstOrNull;
    if (share == null) return _routeDate;
    return PartnerService.routeDayForShare(share);
  }

  Map<DateTime, List<PartnerRouteShare>> get _stagedByDate =>
      PartnerService.groupSharesByRouteDay(_staged);

  bool get _hasMultipleRouteDates => _stagedByDate.length > 1;

  Iterable<PartnerRouteShare> get _visibleStaged {
    if (_filterDay == null) return _staged;
    return _staged.where((s) => _routeDayFor(s.id) == _filterDay);
  }

  List<PartnerRouteShare> get _filteredQueueRoutes {
    final base = _visibleStaged.toList();
    final list = switch (_queueFilter) {
      _RouteQueueFilter.all => List<PartnerRouteShare>.from(base),
      _RouteQueueFilter.missingShift =>
        base.where((s) => _effectiveShiftId(s.id) == null).toList(),
      _RouteQueueFilter.ready =>
        base.where((s) => _effectiveShiftId(s.id) != null).toList(),
      _RouteQueueFilter.selected =>
        base.where((s) => _selected.contains(s.id)).toList(),
    };
    list.sort((a, b) {
      final am = _effectiveShiftId(a.id) == null;
      final bm = _effectiveShiftId(b.id) == null;
      if (am != bm) return am ? -1 : 1;
      final rowA = _rowForShare(a);
      final rowB = _rowForShare(b);
      final maviA = rowA != null ? MaviUnitCodes.normalize(rowA.vehicle.unitCode) : '';
      final maviB = rowB != null ? MaviUnitCodes.normalize(rowB.vehicle.unitCode) : '';
      return maviA.compareTo(maviB);
    });
    return list;
  }

  @override
  void dispose() {
    SapRouteInboxLive.unsubscribe(_sapLiveChannel);
    for (final c in _noteByShare.values) {
      c.dispose();
    }
    for (final s in _skipped) {
      s.noteCtrl.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _routeDate = DateTime(
      widget.initialRouteDate.year,
      widget.initialRouteDate.month,
      widget.initialRouteDate.day,
    );
    _reload().then((_) {
      if (_isSap) {
        _bindSapLive();
        _refreshSapInboxCounts();
      }
    });
    _loadPublishLabels();
  }

  Future<void> _loadPublishLabels() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null || !mounted) return;
    try {
      final label = await PublishActionLabels.massRoutePublishLabel(cid);
      final ch = await PublishActionLabels.massRouteChannel(cid);
      if (mounted) {
        setState(() {
          _withNotifyLabel = PublishActionLabels.publishShortLabel(ch);
          _massChannel = ch;
        });
      }
    } catch (_) {}
  }

  Future<void> _bindSapLive() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (!mounted || cid == null) return;
    SapRouteInboxLive.unsubscribe(_sapLiveChannel);
    _sapLiveChannel = SapRouteInboxLive.subscribe(
      companyId: cid,
      onChanged: () => _refreshSapInboxCounts(),
    );
  }

  Future<void> _refreshSapInboxCounts() async {
    if (!_isSap) return;
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null || !mounted) return;
      await PartnerService.reconcileSapInboxWithStagedQueue(cid);
      final n = await PartnerService.countSapRouteInboxPending(cid);
      if (mounted) setState(() => _sapPendingInbox = n);
    } catch (_) {}
  }

  Future<List<_SkippedPdf>> _collectSapManualSkipped(String companyId) async {
    final manual = await PartnerService.fetchSapRouteInboxManual(companyId);
    if (manual.isEmpty) return const [];
    final added = <_SkippedPdf>[];
    for (final item in manual) {
      if (_skipped.any((x) => x.sapInboxId == item.id)) continue;
      final bytes = await PartnerService.downloadRoutePdfBytes(item.pdfStoragePath);
      if (bytes == null || bytes.isEmpty) continue;
      final reason = (item.rejectReason ?? '')
          .replaceFirst(PartnerService.sapInboxManualReasonPrefix, '')
          .trim();
      added.add(_SkippedPdf(
        fileName: item.fileName,
        bytes: bytes,
        reason: reason.isEmpty ? 'Krever manuell tildeling' : reason,
        detectedCode: item.detectedMaviCode,
        sapInboxId: item.id,
      ));
    }
    return added;
  }

  Future<void> _syncSapInbox() async {
    if (!_isSap || _sapSyncing) return;
    setState(() => _sapSyncing = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.reconcileSapInboxWithStagedQueue(cid);
      final pending = await PartnerService.fetchSapRouteInboxPending(cid);
      if (!mounted) return;
      setState(() => _sapPendingInbox = pending.length);
      if (pending.isEmpty) {
        await _reload();
        return;
      }

      final result = await SapRouteImportService.importPendingToStaged(
        companyId: cid,
        routeDate: _routeDate,
        fleet: widget.fleet,
        rejectOnFailure: false,
      );

      final newSkipped = <_SkippedPdf>[];
      for (final s in result.skippedItems) {
        final exists = _skipped.any((x) => x.sapInboxId == s.inboxId);
        if (exists) continue;
        newSkipped.add(_SkippedPdf(
          fileName: s.fileName,
          bytes: Uint8List.fromList(s.bytes),
          reason: s.reason,
          detectedCode: s.detectedCode,
          sapInboxId: s.inboxId,
        ));
      }

      if (mounted) {
        setState(() {
          _importLog = [..._importLog, ..._mapImportLines(result.lines)];
          _skipped.addAll(newSkipped);
          if (result.skipped > 0 && _staged.isEmpty) {
            _sheetTab = _MassTab.skipped;
          } else if (result.imported > 0) {
            _sheetTab = _MassTab.drivers;
          }
        });
        if (result.imported > 0 || result.skipped > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'SAP: ${result.imported} rute(r) fordelt automatisk'
                '${result.skipped > 0 ? " · ${result.skipped} trenger manuell tildeling" : ""}.'
                '${result.imported > 0 ? " Gå gjennom «Per sjåfør» og åpne PDF-er før publisering." : ""}',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      await _reload();
      await _refreshSapInboxCounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SAP-synk feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sapSyncing = false);
    }
  }

  List<_PdfAssignmentRow> _mapImportLines(List<SapRouteImportLine> lines) {
    return lines
        .map(
          (l) => _PdfAssignmentRow(
            fileName: l.fileName,
            status: l.ok ? 'ok' : 'skipped',
            maviCode: l.maviCode,
            reason: l.message,
          ),
        )
        .toList();
  }

  List<FleetPartnerVehicleRow> get _maviFleet =>
      PartnerService.filterMaviFleetOnly(widget.fleet);

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      if (_isSap) {
        await PartnerService.reconcileSapInboxWithStagedQueue(cid);
      }
      final staged = await PartnerService.fetchStagedRouteShares(cid);
      final manualSkipped = _isSap ? await _collectSapManualSkipped(cid) : const <_SkippedPdf>[];
      final portals = <String, PartnerPortalAccount>{};
      final partnerIds = _maviFleet.map((r) => r.partner.id).toSet();
      for (final pid in partnerIds) {
        for (final a in await PartnerService.fetchPortalAccounts(pid)) {
          if (a.partnerVehicleId != null) portals[a.partnerVehicleId!] = a;
        }
      }
      await PostalCodeRegistry.ensureLoaded();
      final shiftById = <String, String>{};
      for (final s in staged) {
        final pdfText = await RouteShiftResolver.loadPdfTextForShare(s);
        final sid = await RouteShiftResolver.resolveShiftIdForStagedShare(
          share: s,
          allShifts: shifts,
          pdfText: pdfText,
        );
        if (sid != null && sid.isNotEmpty) {
          shiftById[s.id] = sid;
          if (s.shiftId != sid) {
            await PartnerService.updateRouteShareFields(s.id, {'shift_id': sid});
          }
        } else {
          shiftById[s.id] = '';
        }
      }
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _staged = staged;
        for (final s in manualSkipped) {
          if (!_skipped.any((x) => x.sapInboxId == s.sapInboxId)) {
            _skipped.add(s);
          }
        }
        _portalByVehicle = portals;
        _selected
          ..clear()
          ..addAll(staged.map((s) => s.id));
        _stowingByShare.clear();
        _shiftByShare
          ..clear()
          ..addAll(shiftById);
        _dateByShare.clear();
        for (final s in staged) {
          _dateByShare[s.id] = PartnerService.routeDayForShare(s);
          _startByShare.putIfAbsent(s.id, () {
            if (s.routeStartAt != null) {
              return TimeOfDay(hour: s.routeStartAt!.hour, minute: s.routeStartAt!.minute);
            }
            return const TimeOfDay(hour: 6, minute: 0);
          });
          _noteByShare.putIfAbsent(s.id, () => TextEditingController(text: s.notes ?? ''));
          final lane = RoutePdfTextService.parseStowingLaneFromNotes(s.notes) ??
              RoutePdfTextService.parseStowingLane(s.pdfSearchText ?? '');
          if (lane != null) _stowingByShare[s.id] = lane;
        }
        if (staged.isNotEmpty) {
          final groups = PartnerService.groupSharesByRouteDay(staged);
          _routeDate = groups.keys.first;
        }
        if (!_initialTabSet && _routesMissingShift.isNotEmpty) {
          _sheetTab = _MassTab.missingShift;
          _queueFilter = _RouteQueueFilter.missingShift;
        } else if (!_initialTabSet && _staged.isNotEmpty) {
          _sheetTab = _MassTab.drivers;
          _queueFilter = _RouteQueueFilter.all;
        }
        _initialTabSet = true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  FleetPartnerVehicleRow? _rowForShare(PartnerRouteShare share) {
    for (final row in _maviFleet) {
      if (row.vehicle.id == share.partnerVehicleId) return row;
    }
    return null;
  }

  int get _driverWithRouteCount {
    final ids = _staged.map((s) => s.partnerVehicleId).whereType<String>().toSet();
    return ids.length;
  }

  Future<void> _setShareRouteDay(PartnerRouteShare share, DateTime day) async {
    final dn = DateTime(day.year, day.month, day.day);
    final start = _startByShare[share.id];
    await PartnerService.updateShareRouteDay(
      share: share,
      day: dn,
      startHour: start?.hour,
      startMinute: start?.minute,
    );
    if (!mounted) return;
    setState(() => _dateByShare[share.id] = dn);
  }

  String _publishDatesSummary({Set<String>? routeIds}) {
    final ids = routeIds ?? _selected;
    final byDay = <DateTime, int>{};
    for (final id in ids) {
      final d = _routeDayFor(id);
      byDay[d] = (byDay[d] ?? 0) + 1;
    }
    final keys = byDay.keys.toList()..sort();
    if (keys.isEmpty) return '';
    if (keys.length == 1) {
      return 'Rutedato: ${DateFormat('EEEE d. MMM yyyy', 'nb').format(keys.first)} (${ids.length} rute(r))';
    }
    final lines = keys
        .map((d) => '• ${DateFormat('EEE d.M.y', 'nb').format(d)}: ${byDay[d]} rute(r)')
        .join('\n');
    return '${ids.length} ruter på ${keys.length} datoer:\n$lines';
  }

  Future<({int updated, int unchanged, List<String> missingDateLabels})> _syncAllDatesFromPdfs() async {
    var updated = 0;
    var unchanged = 0;
    final missingDateLabels = <String>[];

    for (final share in _staged) {
      final label = (share.title ?? share.pdfStoragePath.split('/').last).split('—').last.trim();
      final pdfText = await RouteShiftResolver.loadPdfTextForShare(share);
      if (pdfText == null || pdfText.trim().isEmpty) {
        missingDateLabels.add(label);
        continue;
      }

      final parsedDate = RoutePdfTextService.parseRouteDate(pdfText);
      if (parsedDate == null) {
        missingDateLabels.add(label);
        continue;
      }

      final schedule = RoutePdfTextService.resolveSchedule(
        pdfText,
        fallbackDate: parsedDate,
      );
      final targetDay = DateTime(
        schedule.routeDate.year,
        schedule.routeDate.month,
        schedule.routeDate.day,
      );
      final current = _routeDayFor(share.id);
      final h = schedule.routeStartAt?.hour ?? share.routeStartAt?.hour ?? 6;
      final m = schedule.routeStartAt?.minute ?? share.routeStartAt?.minute ?? 0;

      if (current.year == targetDay.year &&
          current.month == targetDay.month &&
          current.day == targetDay.day) {
        unchanged++;
      } else {
        await PartnerService.updateShareRouteDay(
          share: share,
          day: targetDay,
          startHour: h,
          startMinute: m,
        );
        updated++;
      }

      if (mounted) {
        _dateByShare[share.id] = targetDay;
        _startByShare[share.id] = TimeOfDay(hour: h, minute: m);
      }
    }

    return (updated: updated, unchanged: unchanged, missingDateLabels: missingDateLabels);
  }

  String _multiLoadNoteFor(Set<String> routeIds) {
    final byVehicle = <String, List<PartnerRouteShare>>{};
    for (final id in routeIds) {
      final share = _staged.where((s) => s.id == id).firstOrNull;
      final vid = share?.partnerVehicleId;
      if (vid == null) continue;
      byVehicle.putIfAbsent(vid, () => []).add(share!);
    }
    final multi = byVehicle.entries.where((e) => e.value.length >= 2).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (multi.isEmpty) return '';
    final lines = multi.take(6).map((e) {
      final row = _rowForVehicleId(e.key);
      final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
      return '• $mavi (${e.value.length} last)';
    }).join('\n');
    return '\n\n⚠ ${multi.length} sjåfør(er) har 2+ last:\n$lines${multi.length > 6 ? '\n…' : ''}';
  }

  Future<bool> _confirmPublish({
    required bool notifyDriver,
    required Set<String> routeIds,
    String? dateSyncSummary,
  }) async {
    final multiLoadNote = _multiLoadNoteFor(routeIds);
    final entries = <PartnerRoutePublishReviewEntry>[];
    final driverIds = <String>{};

    for (final id in routeIds) {
      final share = _staged.where((s) => s.id == id).firstOrNull;
      if (share == null) continue;
      final row = _rowForShare(share);
      final vid = share.partnerVehicleId;
      if (vid != null) driverIds.add(vid);
      final portal = vid != null ? _portalByVehicle[vid] : null;
      final phone = portal?.phone ?? row?.vehicle.phone;
      final start = _startByShare[id] ?? const TimeOfDay(hour: 6, minute: 0);
      entries.add(
        PartnerRoutePublishReviewEntry(
          share: share,
          mavi: row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?',
          partnerName: row?.partner.name ?? 'Ukjent sjåfør',
          shiftName: _shiftLabel(_effectiveShiftId(id)),
          dateLabel: DateFormat('EEE d.M.y', 'nb').format(_routeDayFor(id)),
          startLabel: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
          hasPhone: phone != null && phone.trim().length >= 8,
        ),
      );
    }

    entries.sort((a, b) {
      final m = a.mavi.compareTo(b.mavi);
      if (m != 0) return m;
      return a.fileLabel.compareTo(b.fileLabel);
    });

    return showPartnerRoutePublishReviewDialog(
      context: context,
      entries: entries,
      driverCount: driverIds.length,
      notifyDriver: notifyDriver,
      confirmLabel: notifyDriver ? _withNotifyLabel : 'Publiser uten varsel',
      dateSyncSummary: dateSyncSummary,
      multiLoadNote: multiLoadNote,
      extraSummary: [
        if (routeIds.length == _staged.length && _staged.isNotEmpty) _multiLoadSummaryLine(),
        _publishDatesSummary(routeIds: routeIds),
      ].where((s) => s.trim().isNotEmpty).join('\n\n'),
    );
  }

  int _missingPhoneCountFor(Set<String> routeIds) {
    var n = 0;
    final seen = <String>{};
    for (final id in routeIds) {
      final share = _staged.where((s) => s.id == id).firstOrNull;
      final vid = share?.partnerVehicleId;
      if (vid == null || seen.contains(vid)) continue;
      seen.add(vid);
      final acc = _portalByVehicle[vid];
      final row = share != null ? _rowForShare(share) : null;
      final phone = acc?.phone ?? row?.vehicle.phone;
      if (phone == null || phone.trim().length < 8) n++;
    }
    return n;
  }

  Future<void> _executePublish({
    required Set<String> routeIds,
    required bool notifyDriver,
  }) async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;
    setState(() => _publishing = true);
    try {
      for (final id in routeIds) {
        final note = _noteByShare[id]?.text.trim();
        if (note != null && note.isNotEmpty) {
          await PartnerService.updateRouteShareFields(id, {'notes': note});
        }
      }
      final map = {
        for (final id in routeIds)
          if (_effectiveShiftId(id) != null) id: _effectiveShiftId(id)!,
      };
      final starts = <String, DateTime?>{};
      for (final id in routeIds) {
        final t = _startByShare[id];
        if (t == null) continue;
        final day = _routeDayFor(id);
        starts[id] = DateTime(day.year, day.month, day.day, t.hour, t.minute);
      }
      final sendNotify =
          notifyDriver && _massChannel != NotificationChannel.none;
      await PartnerService.dispatchRouteShares(
        companyId: cid,
        shareIdToShiftId: map,
        date: routeIds.isNotEmpty ? _routeDayFor(routeIds.first) : _routeDate,
        shareIdToStartAt: starts,
        notifyDriver: sendNotify,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              PublishActionLabels.successMessage(
                routeCount: map.length,
                channel: _massChannel,
                notifyDriver: sendNotify,
              ),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publisering feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _smartPublishFromPdfs({required bool notifyDriver}) async {
    if (_skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Du har ${_skipped.length} PDF som ikke er tildelt sjåfør. Fordel alle før publisering.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      _setTabIndex(4);
      return;
    }
    if (_staged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen ruter i kø.')),
      );
      return;
    }

    setState(() => _busyUpload = true);
    String? dateSyncSummary;
    try {
      final sync = await _syncAllDatesFromPdfs();
      await _fillAllShiftsForStaged();
      if (!mounted) return;
      setState(() {});

      dateSyncSummary = 'PDF-datoer: ${sync.updated} oppdatert, ${sync.unchanged} uendret'
          '${sync.missingDateLabels.isNotEmpty ? "\n${sync.missingDateLabels.length} PDF uten «Start date» — bruker eksisterende dato" : ""}';

      final missingShift = _staged.where((s) => _effectiveShiftId(s.id) == null).map((s) => s.id).toList();
      if (missingShift.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${missingShift.length} rute(r) mangler skift etter PDF-lesing — se fanen «Mangler skift».',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        _setTabIndex(2);
        return;
      }

      final routeIds = _staged.map((s) => s.id).toSet();
      final confirmed = await _confirmPublish(
        notifyDriver: notifyDriver,
        routeIds: routeIds,
        dateSyncSummary: dateSyncSummary,
      );
      if (!confirmed || !mounted) return;
      await _executePublish(routeIds: routeIds, notifyDriver: notifyDriver);
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _onDateQueueMenuSelected(Object? value) async {
    if (value == _DateQueueAction.clearAll) {
      await _clearAllStaged();
    } else if (value is DateTime) {
      await _clearStagedForDay(value);
    } else if (value == _DateQueueAction.publishNoSms) {
      await _smartPublishFromPdfs(notifyDriver: false);
    } else if (value == _DateQueueAction.publishSms) {
      await _smartPublishFromPdfs(notifyDriver: true);
    }
  }

  Widget _buildDateQueueMenu(Map<DateTime, List<PartnerRouteShare>> groups) {
    final busy = _busyUpload || _publishing;
    return PopupMenuButton<Object>(
      enabled: !busy,
      tooltip: 'Dato, tøm og publiser',
      onSelected: _onDateQueueMenuSelected,
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<Object>>[
          PopupMenuItem(
            enabled: false,
            child: Text(
              'Tøm ruter',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700),
            ),
          ),
          ...groups.entries.map((e) {
            final day = e.key;
            final n = e.value.length;
            return PopupMenuItem<Object>(
              value: day,
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tøm ${DateFormat('EEE d.M.y', 'nb').format(day)} ($n)',
                      style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            value: _DateQueueAction.clearAll,
            child: Row(
              children: [
                Icon(Icons.delete_forever_outlined, size: 18, color: Colors.red.shade900),
                const SizedBox(width: 10),
                Text(
                  'Tøm alle rutene (${_staged.length})',
                  style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: false,
            child: Text(
              'Publiser til riktige dato (les PDF)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade700),
            ),
          ),
          PopupMenuItem<Object>(
            value: _DateQueueAction.publishNoSms,
            child: const Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text('Publiser alle — uten SMS')),
              ],
            ),
          ),
          PopupMenuItem<Object>(
            value: _DateQueueAction.publishSms,
            child: Row(
              children: [
                Icon(Icons.rocket_launch_outlined, size: 18, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Publiser alle — med SMS',
                    style: TextStyle(fontWeight: FontWeight.w700, color: DriftProTheme.primaryGreen),
                  ),
                ),
              ],
            ),
          ),
        ];
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.shade300),
          color: busy ? Colors.grey.shade100 : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 18, color: Colors.blueGrey.shade800),
            const SizedBox(width: 8),
            Text(
              'Dato & publisering (${groups.length} dager)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: busy ? Colors.grey : Colors.blueGrey.shade900,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.blueGrey.shade700),
          ],
        ),
      ),
    );
  }

  Future<void> _moveStagedDayToDate(DateTime from, DateTime to) async {
    final targets = _staged.where((s) => _routeDayFor(s.id) == from).toList();
    if (targets.isEmpty) return;
    for (final s in targets) {
      await _setShareRouteDay(s, to);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${targets.length} rute(r) flyttet til ${DateFormat('d.M.y', 'nb').format(to)}')),
      );
    }
  }

  Future<void> _clearStagedForDay(DateTime day) async {
    final targets = _staged.where((s) => _routeDayFor(s.id) == day).toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tøm dag fra kø?'),
        content: Text(
          'Fjerner ${targets.length} kladd-rute(r) for '
          '${DateFormat('EEEE d. MMM yyyy', 'nb').format(day)} fra alle sjåfører. '
          'Dette kan ikke angres.',
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
    if (ok != true) return;
    setState(() => _busyUpload = true);
    try {
      for (final s in targets) {
        await PartnerService.deleteRouteShare(s);
        _dateByShare.remove(s.id);
        _selected.remove(s.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fjernet ${targets.length} rute(r) fra køen')),
        );
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Map<String, List<PartnerRouteShare>> get _routesByVehicle {
    final map = <String, List<PartnerRouteShare>>{};
    for (final s in _visibleStaged) {
      final vid = s.partnerVehicleId;
      if (vid == null) continue;
      map.putIfAbsent(vid, () => []).add(s);
    }
    return map;
  }

  int get _multiLoadDriverCount =>
      _routesByVehicle.values.where((list) => list.length >= 2).length;

  List<MapEntry<String, List<PartnerRouteShare>>> get _multiLoadEntries =>
      _routesByVehicle.entries.where((e) => e.value.length >= 2).toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));

  String? _stowingForShare(PartnerRouteShare share) =>
      _stowingByShare[share.id] ??
      RoutePdfTextService.parseStowingLaneFromNotes(share.notes);

  String _multiLoadSummaryLine() {
    if (_staged.isEmpty) return '';
    final multi = _routesByVehicle.entries.where((e) => e.value.length >= 2).toList();
    if (multi.isEmpty) {
      return '${_staged.length} ruter · ${_driverWithRouteCount} sjåfører (én last per sjåfør)';
    }
    final parts = <String>[];
    for (final e in multi) {
      final row = _rowForVehicleId(e.key);
      final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
      final lanes = e.value
          .map(_stowingForShare)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort();
      final laneTxt = lanes.isEmpty ? '${e.value.length} PDF' : lanes.join(', ');
      parts.add('$mavi: $laneTxt');
    }
    return '${_staged.length} ruter · ${multi.length} sjåfør med 2+ last samme dag '
        '(${parts.take(4).join(' · ')}${parts.length > 4 ? ' …' : ''})';
  }

  FleetPartnerVehicleRow? _rowForVehicleId(String vehicleId) {
    for (final r in _maviFleet) {
      if (r.vehicle.id == vehicleId) return r;
    }
    return null;
  }

  int get _missingPhoneCount {
    var n = 0;
    final seen = <String>{};
    for (final id in _selected) {
      final share = _staged.firstWhere((s) => s.id == id);
      final vid = share.partnerVehicleId;
      if (vid == null || seen.contains(vid)) continue;
      seen.add(vid);
      final acc = _portalByVehicle[vid];
      final row = _rowForShare(share);
      final phone = acc?.phone ?? row?.vehicle.phone;
      if (phone == null || phone.trim().length < 8) n++;
    }
    return n;
  }

  Future<Uint8List?> _readPlatformFile(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) return file.bytes;
    if (!kIsWeb && file.path != null) {
      try {
        return await File(file.path!).readAsBytes();
      } catch (_) {}
    }
    if (file.readStream != null) {
      final out = <int>[];
      await for (final chunk in file.readStream!) {
        out.addAll(chunk);
      }
      if (out.isEmpty) return null;
      return Uint8List.fromList(out);
    }
    return null;
  }

  Future<Map<String, PartnerVehicle>> _loadAllVehiclesLookup(String companyId) async {
    final partners = await PartnerService.fetchPartners(companyId: companyId);
    final vehicles = <PartnerVehicle>[];
    for (final p in partners) {
      vehicles.addAll(await PartnerService.fetchVehicles(p.id));
    }
    return RoutePdfTextService.buildVehicleLookupMap<PartnerVehicle>(
      vehicles: vehicles.where(PartnerService.isMaviFleetVehicle),
      unitCodeOf: (v) => v.unitCode,
      registrationOf: (v) => v.registrationNumber,
    );
  }

  Future<({_PdfAssignmentRow row, String? shareId, String? stowing, TimeOfDay? start})> _importOnePdf({
    required String companyId,
    required PlatformFile file,
    required Map<String, PartnerVehicle> vehicleMap,
    required Map<String, Partner> partnerById,
  }) async {
    final bytes = await _readPlatformFile(file);
    if (bytes == null || bytes.isEmpty) {
      return (
        row: _PdfAssignmentRow(
          fileName: file.name,
          status: 'skipped',
          reason: 'Kunne ikke lese fil',
        ),
        shareId: null,
        stowing: null,
        start: null,
      );
    }

    final bundle = RoutePdfTextService.parseBundle(bytes, fallbackDate: _routeDate);
    final code = bundle.meta.maviCode;
    if (code == null) {
      return (
        row: _PdfAssignmentRow(
          fileName: file.name,
          status: 'skipped',
          reason: 'Fant ikke MAVI-nummer inne i PDF (Start date / Trip Overview)',
        ),
        shareId: null,
        stowing: null,
        start: null,
      );
    }

    final vehicle = RoutePdfTextService.findVehicleInLookup(vehicleMap, code);
    if (vehicle == null) {
      return (
        row: _PdfAssignmentRow(
          fileName: file.name,
          status: 'skipped',
          maviCode: code,
          reason: 'Ingen bil matcher $code i flåten',
        ),
        shareId: null,
        stowing: null,
        start: null,
      );
    }

    final partner = partnerById[vehicle.partnerId];
    if (partner == null) {
      return (
        row: _PdfAssignmentRow(
          fileName: file.name,
          status: 'skipped',
          maviCode: code,
          reason: 'Partner mangler',
        ),
        shareId: null,
        stowing: null,
        start: null,
      );
    }

    final routeDay = bundle.schedule.routeDate;
    final shareId = await PartnerService.createStagedRouteShareFromPdf(
      companyId: companyId,
      partner: partner,
      vehicle: vehicle,
      fileName: file.name,
      bytes: bytes,
      routeDate: routeDay,
      parsed: bundle,
    );

    final start = bundle.schedule.routeStartAt != null
        ? TimeOfDay(
            hour: bundle.schedule.routeStartAt!.hour,
            minute: bundle.schedule.routeStartAt!.minute,
          )
        : null;

    return (
      row: _PdfAssignmentRow(
        fileName: file.name,
        status: 'ok',
        maviCode: MaviUnitCodes.normalize(vehicle.unitCode),
        stowingLane: bundle.meta.stowingLane,
        driverLabel: partner.name,
        routeDateLabel: DateFormat('d.M.y').format(routeDay),
      ),
      shareId: shareId,
      stowing: bundle.meta.stowingLane,
      start: start,
    );
  }

  Future<void> _importPdfs(List<PlatformFile> files) async {
    if (_busyUpload || files.isEmpty) return;
    setState(() => _busyUpload = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final vehicleMap = await _loadAllVehiclesLookup(cid);
      final partnerById = {
        for (final r in _maviFleet) r.partner.id: r.partner,
      };
      for (final p in await PartnerService.fetchPartners(companyId: cid)) {
        partnerById.putIfAbsent(p.id, () => p);
      }

      const parallel = 10;
      final newSkipped = <_SkippedPdf>[];
      final log = <_PdfAssignmentRow>[];

      for (var i = 0; i < files.length; i += parallel) {
        final chunk = files.skip(i).take(parallel).toList();
        final chunkResults = await Future.wait(
          chunk.map(
            (file) => _importOnePdf(
              companyId: cid,
              file: file,
              vehicleMap: vehicleMap,
              partnerById: partnerById,
            ),
          ),
        );
        for (var j = 0; j < chunk.length; j++) {
          final result = chunkResults[j];
          final file = chunk[j];
          log.add(result.row);
          if (result.shareId != null) {
            if (result.stowing != null) {
              _stowingByShare[result.shareId!] = result.stowing!;
            }
            if (result.start != null) {
              _startByShare[result.shareId!] = result.start!;
            }
          }
          if (result.row.status != 'ok') {
            final bytes = await _readPlatformFile(file);
            if (bytes != null && bytes.isNotEmpty) {
              newSkipped.add(_SkippedPdf(
                fileName: file.name,
                bytes: bytes,
                reason: result.row.reason ?? 'Ukjent feil',
                detectedCode: result.row.maviCode,
              ));
            }
          }
        }
        if (mounted) {
          final okSoFar = log.where((r) => r.status == 'ok').length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Importerer … $okSoFar / ${files.length} PDF'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }

      final ok = log.where((r) => r.status == 'ok').length;

      if (mounted) {
        setState(() {
          _skipped.addAll(newSkipped.where((s) => s.bytes.isNotEmpty));
          _importLog = log;
          if (_skipped.isNotEmpty) _sheetTab = _MassTab.skipped;
          else _sheetTab = _MassTab.drivers;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AUTO MASS: $ok rute(r) fordelt til sjåfør. '
              '${newSkipped.length} hoppet over — tildel manuelt under «Hoppet over».'
              '${ok > 0 ? " Gå gjennom «Per sjåfør» og åpne PDF-er før publisering." : ""}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _assignSkipped(_SkippedPdf item) async {
    if (item.selectedVehicleId == null || item.bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg sjåfør / MAVI-bil først')),
      );
      return;
    }
    if ((item.shiftId ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg skiftplan før tildeling')),
      );
      return;
    }
    setState(() => _busyUpload = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final row = _maviFleet.firstWhere((r) => r.vehicle.id == item.selectedVehicleId);
      final bundle = RoutePdfTextService.parseBundle(item.bytes, fallbackDate: _routeDate);
      final shareId = await PartnerService.createStagedRouteShareFromPdf(
        companyId: cid,
        partner: row.partner,
        vehicle: row.vehicle,
        fileName: item.fileName,
        bytes: item.bytes,
        routeDate: bundle.schedule.routeDate,
        notes: item.noteCtrl.text,
        parsed: bundle,
      );
      if (item.sapInboxId != null) {
        await PartnerService.markSapRouteInboxImported(
          inboxId: item.sapInboxId!,
          routeShareId: shareId,
          detectedMaviCode: MaviUnitCodes.normalize(row.vehicle.unitCode),
        );
      }
      _shiftByShare[shareId] = item.shiftId!;
      _startByShare[shareId] = item.startTime;
      if (mounted) {
        setState(() {
          _skipped.remove(item);
          _importLog = [
            ..._importLog,
            _PdfAssignmentRow(
              fileName: item.fileName,
              status: 'ok',
              maviCode: MaviUnitCodes.normalize(row.vehicle.unitCode),
              driverLabel: row.partner.name,
            ),
          ];
          if (_skipped.isEmpty) _sheetTab = _MassTab.drivers;
        });
      }
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.fileName} tildelt ${row.vehicle.unitCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tildeling feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _clearAllStaged() async {
    if (_staged.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tøm alle tildelte ruter?'),
        content: Text(
          'Fjerner alle ${_staged.length} rute(r) fra AUTO MASS-køen. '
          'PDF-er i «Hoppet over» beholdes (${_skipped.length} stk).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Tøm alle'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyUpload = true);
    try {
      for (final s in List<PartnerRouteShare>.from(_staged)) {
        await PartnerService.deleteRouteShare(s);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alle tildelte ruter er fjernet fra køen.')),
        );
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke tømme: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _reassignShare(PartnerRouteShare share, String vehicleId) async {
    FleetPartnerVehicleRow? row;
    for (final r in _maviFleet) {
      if (r.vehicle.id == vehicleId) {
        row = r;
        break;
      }
    }
    if (row == null) return;
    setState(() => _busyUpload = true);
    try {
      final baseTitle = share.title ?? share.pdfStoragePath.split('/').last;
      final fileLabel = baseTitle.contains('—')
          ? baseTitle.split('—').last.trim()
          : baseTitle;
      await PartnerService.reassignStagedRouteShare(
        share: share,
        partnerId: row.partner.id,
        partnerVehicleId: row.vehicle.id,
        title: 'Rute ${MaviUnitCodes.normalize(row.vehicle.unitCode)} — $fileLabel',
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Flyttet til ${MaviUnitCodes.normalize(row.vehicle.unitCode)} · ${row.partner.name}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke bytte sjåfør: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _removeShare(PartnerRouteShare share) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern rute fra kø?'),
        content: Text(share.title ?? 'PDF-rute'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Fjern'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyUpload = true);
    try {
      await PartnerService.deleteRouteShare(share);
      _selected.remove(share.id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke fjerne: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  String? _effectiveShiftId(String shareId) {
    final fromMap = _shiftByShare[shareId];
    if (fromMap != null && fromMap.isNotEmpty) return fromMap;
    PartnerRouteShare? share;
    for (final s in _staged) {
      if (s.id == shareId) {
        share = s;
        break;
      }
    }
    final sid = share?.shiftId;
    if (sid != null && sid.isNotEmpty && _routeShifts.any((s) => s.id == sid)) {
      return sid;
    }
    return null;
  }

  String? _shiftLabel(String? shiftId) {
    if (shiftId == null) return null;
    for (final s in _routeShifts) {
      if (s.id == shiftId) return s.name;
    }
    return null;
  }

  Future<void> _resolveAndStoreShift(PartnerRouteShare share, {bool force = false}) async {
    if (!force && _effectiveShiftId(share.id) != null) return;
    final pdfText = await RouteShiftResolver.loadPdfTextForShare(share);
    final resolved = await RouteShiftResolver.resolveShiftIdForStagedShare(
      share: share,
      allShifts: _shifts,
      pdfText: pdfText,
    );
    if (resolved != null && resolved.isNotEmpty) {
      _shiftByShare[share.id] = resolved;
      await PartnerService.updateRouteShareFields(share.id, {'shift_id': resolved});
    }
  }

  Future<void> _fillMissingShiftsForSelected() async {
    for (final id in _selected) {
      PartnerRouteShare? share;
      for (final s in _staged) {
        if (s.id == id) {
          share = s;
          break;
        }
      }
      if (share != null) await _resolveAndStoreShift(share);
    }
  }

  Future<void> _fillAllShiftsForStaged() async {
    if (_fillingShifts || _staged.isEmpty) return;
    setState(() => _fillingShifts = true);
    try {
      for (final s in _routesMissingShift) {
        await _resolveAndStoreShift(s, force: true);
      }
    } finally {
      if (mounted) setState(() => _fillingShifts = false);
    }
  }

  Future<void> _pickPdfs() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    await _importPdfs(picked.files);
  }

  Future<void> _publish({required bool notifyDriver}) async {
    if (_skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Du har ${_skipped.length} PDF som ikke er tildelt sjåfør. Fordel alle før publisering.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      _setTabIndex(4);
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen ruter valgt for publisering.')),
      );
      return;
    }
    await _fillMissingShiftsForSelected();
    if (mounted) setState(() {});
    final missingShift = _selected.where((id) => _effectiveShiftId(id) == null).toList();
    if (missingShift.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${missingShift.length} rute(r) mangler skift — se fanen «Mangler skift».',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      _setTabIndex(2);
      return;
    }

    final routeIds = Set<String>.from(_selected);
    final confirmed = await _confirmPublish(
      notifyDriver: notifyDriver,
      routeIds: routeIds,
    );
    if (!confirmed || !mounted) return;
    await _executePublish(routeIds: routeIds, notifyDriver: notifyDriver);
  }

  int get _tabIndex => switch (_sheetTab) {
        _MassTab.allRoutes => 0,
        _MassTab.drivers => 1,
        _MassTab.missingShift => 2,
        _MassTab.importLog => 3,
        _MassTab.skipped => 4,
      };

  void _setTabIndex(int i) {
    setState(() {
      _sheetTab = switch (i) {
        0 => _MassTab.allRoutes,
        1 => _MassTab.drivers,
        2 => _MassTab.missingShift,
        3 => _MassTab.importLog,
        4 => _MassTab.skipped,
        _ => _MassTab.allRoutes,
      };
      if (_sheetTab == _MassTab.missingShift) {
        _queueFilter = _RouteQueueFilter.missingShift;
      }
    });
  }

  List<Widget> _infoChips(_MassUi ui) {
    final chips = <Widget>[];
    if (_staged.isNotEmpty) {
      chips.add(
        routeInfoChip(
          '${_selected.length}/${_staged.length} valgt',
        ),
      );
    }
    if (_multiLoadDriverCount > 0) {
      chips.add(
        routeInfoChip(
          '$_multiLoadDriverCount sjåfør med 2+ last',
          onTap: () => _showMultiLoadDetails(),
        ),
      );
    }
    if (_missingPhoneCount > 0) {
      chips.add(
        routeInfoChip(
          '$_missingPhoneCount uten telefon (ingen SMS)',
        ),
      );
    }
    if (_missingShiftCount > 0) {
      chips.add(
        routeInfoChip(
          '$_missingShiftCount mangler skift',
          color: Colors.red.shade800,
          onTap: () => _setTabIndex(2),
        ),
      );
    }
    if (_readyShiftCount > 0) {
      chips.add(
        routeInfoChip(
          '$_readyShiftCount med skift',
          color: Colors.green.shade800,
          onTap: () {
            setState(() {
              _sheetTab = _MassTab.allRoutes;
              _queueFilter = _RouteQueueFilter.ready;
            });
          },
        ),
      );
    }
    if (_staged.isNotEmpty) {
      chips.add(
        TextButton.icon(
          onPressed: _busyUpload ? null : _clearAllStaged,
          icon: Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.grey.shade700),
          label: Text(
            'Tøm kø (${_staged.length})',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      );
    }
    return chips;
  }

  Future<void> _showMultiLoadDetails() async {
    if (_multiLoadDriverCount == 0) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sjåfører med 2+ last'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Disse sjåførene har flere PDF / last samme dag. Sjekk at fordelingen er rettferdig før publisering.',
                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 12),
              ..._multiLoadEntries.map(_multiLoadDetailTile),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setTabIndex(1);
            },
            child: const Text('Se per sjåfør'),
          ),
        ],
      ),
    );
  }

  Widget _multiLoadDetailTile(MapEntry<String, List<PartnerRouteShare>> entry) {
    final row = _rowForVehicleId(entry.key);
    final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
    final partner = row?.partner.name ?? '—';
    final lanes = entry.value.map(_stowingForShare).whereType<String>().toSet().toList()..sort();
    final dates = entry.value.map((s) => _routeDayFor(s.id)).toSet().length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$mavi · $partner', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '${entry.value.length} last${dates > 1 ? " · $dates datoer" : ""}${lanes.isNotEmpty ? " · Lane ${lanes.join(", ")}" : ""}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final ui = _ui;
    final manualOnly = _skipped.isNotEmpty;
    final missingShift = _missingShiftCount;
    final ready = _skipped.isEmpty &&
        _staged.isNotEmpty &&
        _selected.isNotEmpty &&
        missingShift == 0 &&
        _selected.every((id) => _effectiveShiftId(id) != null);

    return PartnerRouteWorkflowShell(
      accent: ui.accent,
      accentDark: ui.accentDark,
      icon: ui.icon,
      title: ui.title,
      subtitle: ui.tagline,
      badge: ui.badge,
      metrics: [
        RouteWorkflowMetric(
          label: 'Ruter',
          value: '${_staged.length}',
          icon: Icons.description_outlined,
          color: ui.accentDark,
        ),
        RouteWorkflowMetric(
          label: 'Valgt',
          value: '${_selected.length}',
          icon: Icons.check_box_outlined,
          color: Colors.blueGrey.shade700,
        ),
        RouteWorkflowMetric(
          label: 'Klare',
          value: '$_readyShiftCount',
          icon: Icons.check_circle_outline,
          color: Colors.green.shade700,
        ),
        if (manualOnly || missingShift > 0)
          RouteWorkflowMetric(
            label: 'Trenger deg',
            value: '${_skipped.length + missingShift}',
            icon: Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
          )
        else if (_multiLoadDriverCount > 0)
          RouteWorkflowMetric(
            label: '2+ last',
            value: '$_multiLoadDriverCount',
            icon: Icons.layers_outlined,
            color: Colors.orange.shade900,
          ),
      ],
      sidebar: _buildSidebar(ui),
      guidePanel: _buildWorkflowGuideContent(ui),
      guideExpanded: _guideExpanded,
      onGuideToggle: () => setState(() => _guideExpanded = !_guideExpanded),
      tabLabels: const ['Ruter', 'Sjåfører', 'Mangler skift', 'Logg', 'Manuell'],
      tabBadges: [
        _staged.isNotEmpty ? _staged.length : null,
        _multiLoadDriverCount > 0 ? _multiLoadDriverCount : (_driversWithRoutesCount > 0 ? _driversWithRoutesCount : null),
        missingShift > 0 ? missingShift : null,
        _importLog.isNotEmpty ? _importLog.length : null,
        _skipped.isNotEmpty ? _skipped.length : null,
      ],
      tabBadgeColors: [
        ui.accentDark,
        _multiLoadDriverCount > 0 ? Colors.orange.shade900 : ui.accentDark,
        Colors.red.shade700,
        Colors.grey.shade700,
        Colors.orange.shade800,
      ],
      selectedTabIndex: _tabIndex,
      onTabSelected: _setTabIndex,
      tabCaption: _tabHint(),
      tabBody: _buildTabContent(ui),
      footer: _buildPublishBar(ui),
    );
  }

  Widget _buildSidebar(_MassUi ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildActionsRow(ui),
        if (_staged.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _busyUpload ? null : _clearAllStaged,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text('Tøm kø (${_staged.length})'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkflowGuideContent(_MassUi ui) {
    return Material(
      color: ui.surfaceTint,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: ui.steps.asMap().entries.map((e) => _workflowStep(e.key + 1, e.value, ui)).toList(),
        ),
      ),
    );
  }

  Widget _workflowStep(int n, String text, _MassUi ui) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: ui.accent,
            child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35))),
        ],
      ),
    );
  }

  Widget _buildMultiDatePanel(_MassUi ui) {
    if (_staged.isEmpty) {
      return OutlinedButton.icon(
        onPressed: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _routeDate,
            firstDate: DateTime.now().subtract(const Duration(days: 30)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (d != null) setState(() => _routeDate = DateTime(d.year, d.month, d.day));
        },
        icon: const Icon(Icons.event_outlined, size: 20),
        label: Text(
          'Standarddato nye PDF: ${DateFormat('d. MMM yyyy', 'nb').format(_routeDate)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_staged.length} ruter i kø${_filterDay != null ? ' · filtrert' : ''}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ui.accentDark),
        ),
        const SizedBox(height: 6),
        Text(
          'Datofilter og massehandlinger ligger i stripen over rute-listen.',
          style: TextStyle(fontSize: 11, height: 1.35, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildActionsRow(_MassUi ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMultiDatePanel(ui),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _isSap
              ? (_sapSyncing ? null : _syncSapInbox)
              : (_busyUpload ? null : _pickPdfs),
          style: FilledButton.styleFrom(
            backgroundColor: ui.accentDark,
            minimumSize: const Size(double.infinity, 50),
          ),
          icon: _isSap
              ? (_sapSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_download_outlined))
              : (_busyUpload
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file)),
          label: Text(
            _isSap
                ? (_sapPendingInbox > 0
                    ? 'Importer $_sapPendingInbox SAP-PDF'
                    : 'Ingen nye SAP-PDF')
                : 'Last opp PDF-er',
          ),
        ),
        if (_staged.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _fillingShifts ? null : _fillAllShiftsForStaged,
            icon: _fillingShifts
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high_outlined),
            label: Text(_fillingShifts ? 'Fyller skift…' : 'Fyll skift fra PDF (alle)'),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactAlert({
    required IconData icon,
    required Color color,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
              Icon(Icons.chevron_right, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollListHeader(_MassUi ui, {bool showFilters = true, bool forceMissingOnly = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_multiLoadDriverCount > 0)
          _buildCompactAlert(
            icon: Icons.layers_outlined,
            color: Colors.orange.shade900,
            text: '$_multiLoadDriverCount sjåfør(er) har 2+ last — trykk for liste',
            onTap: _showMultiLoadDetails,
          ),
        if (_skipped.isNotEmpty && _sheetTab != _MassTab.skipped)
          _buildCompactAlert(
            icon: Icons.pan_tool_alt_outlined,
            color: Colors.orange.shade900,
            text: '$_skipped PDF krever manuell tildeling',
            onTap: () => _setTabIndex(4),
          ),
        if (_missingShiftCount > 0 && _sheetTab != _MassTab.missingShift)
          _buildCompactAlert(
            icon: Icons.warning_amber_rounded,
            color: Colors.red.shade800,
            text: '$_missingShiftCount rute(r) mangler skift',
            onTap: () => _setTabIndex(2),
          ),
        if (_staged.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: Text('Alle (${_staged.length})'),
                  selected: _filterDay == null,
                  onSelected: (_) => setState(() => _filterDay = null),
                ),
                ..._stagedByDate.entries.map((e) {
                  final day = e.key;
                  return FilterChip(
                    label: Text('${DateFormat('EEE d.M', 'nb').format(day)} (${e.value.length})'),
                    selected: _filterDay == day,
                    onSelected: (_) => setState(() => _filterDay = _filterDay == day ? null : day),
                  );
                }),
                _buildDateQueueMenu(_stagedByDate),
              ],
            ),
          ),
        if (showFilters && !forceMissingOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: _buildQueueFilterBar(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              TextButton(onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))), child: const Text('Velg alle')),
              TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Fjern valg')),
              const Spacer(),
              Text(
                '${_filteredQueueRoutes.length}/${_staged.length} · Vis PDF',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _tabHint() {
    return switch (_sheetTab) {
      _MassTab.allRoutes =>
        'Flat liste over alle ruter i kø. Bruk filter for å finne ruter uten skift.',
      _MassTab.drivers =>
        _multiLoadDriverCount > 0
            ? '$_multiLoadDriverCount sjåfører har 2+ last — markert med oransje. Sjekk rettferdig fordeling før publisering.'
            : 'Ruter gruppert per sjåfør / MAVI. Utvid for notat og detaljer.',
      _MassTab.missingShift =>
        'Kun ruter uten skiftplan — velg skift i kolonnen før publisering.',
      _MassTab.importLog =>
        'Oversikt over hva systemet gjorde med hver PDF (automatisk MAVI-fordeling eller årsak til manuell).',
      _MassTab.skipped =>
        'PDF-er uten treff på MAVI — velg bil, skiftplan og tildel manuelt før publisering.',
    };
  }

  Widget _buildTabContent(_MassUi ui) {
    return switch (_sheetTab) {
      _MassTab.allRoutes => _buildRoutesOverview(ui),
      _MassTab.drivers => _buildDriverCentricList(ui),
      _MassTab.missingShift => _buildRoutesOverview(ui, forceMissingOnly: true),
      _MassTab.importLog => _buildAssignmentOverview(ui),
      _MassTab.skipped => _buildSkippedList(ui),
    };
  }

  Widget _buildQueueSummaryStrip(_MassUi ui) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.spaceAround,
        children: [
          _summaryTile('Totalt', '${_staged.length}', ui.accentDark),
          _summaryTile('Med skift', '$_readyShiftCount', Colors.green.shade700),
          _summaryTile('Mangler skift', '$_missingShiftCount', Colors.red.shade700),
          _summaryTile('Valgt', '${_selected.length}', Colors.blueGrey.shade700),
          if (_multiLoadDriverCount > 0)
            _summaryTile('2+ last', '$_multiLoadDriverCount', Colors.orange.shade900),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value, Color color) {
    return SizedBox(
      width: 100,
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _buildQueueFilterBar() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ChoiceChip(
          label: Text('Alle (${_staged.length})'),
          selected: _queueFilter == _RouteQueueFilter.all,
          onSelected: (_) => setState(() => _queueFilter = _RouteQueueFilter.all),
        ),
        ChoiceChip(
          label: Text('Mangler skift ($_missingShiftCount)'),
          selected: _queueFilter == _RouteQueueFilter.missingShift,
          onSelected: (_) => setState(() => _queueFilter = _RouteQueueFilter.missingShift),
        ),
        ChoiceChip(
          label: Text('Klare ($_readyShiftCount)'),
          selected: _queueFilter == _RouteQueueFilter.ready,
          onSelected: (_) => setState(() => _queueFilter = _RouteQueueFilter.ready),
        ),
        ChoiceChip(
          label: Text('Valgt (${_selected.length})'),
          selected: _queueFilter == _RouteQueueFilter.selected,
          onSelected: (_) => setState(() => _queueFilter = _RouteQueueFilter.selected),
        ),
      ],
    );
  }

  Widget _buildRoutesOverview(_MassUi ui, {bool forceMissingOnly = false}) {
    if (_staged.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(ui.emptyHint, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, height: 1.45)),
        ),
      );
    }

    final routes = forceMissingOnly ? _routesMissingShift : _filteredQueueRoutes;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildScrollListHeader(ui, showFilters: !forceMissingOnly, forceMissingOnly: forceMissingOnly),
        ),
        if (routes.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                forceMissingOnly ? 'Ingen ruter mangler skift — bra!' : 'Ingen ruter matcher filteret.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final share = routes[i];
                  final row = _rowForShare(share);
                  if (row == null) return _buildOrphanRouteCard(share, ui);
                  return _buildRouteCompactTile(share, row, ui);
                },
                childCount: routes.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRouteCompactTile(PartnerRouteShare share, FleetPartnerVehicleRow row, _MassUi ui) {
    final checked = _selected.contains(share.id);
    final expanded = _expandedShareIds.contains(share.id);
    final mavi = MaviUnitCodes.normalize(row.vehicle.unitCode);
    final fileLabel = (share.title ?? share.pdfStoragePath.split('/').last).split('—').last.trim();
    final shiftMissing = _effectiveShiftId(share.id) == null;
    final shiftName = _shiftLabel(_effectiveShiftId(share.id)) ?? 'Velg skift';
    final dateLabel = DateFormat('EEE d.M', 'nb').format(_routeDayFor(share.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: shiftMissing ? Colors.amber.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              if (expanded) {
                _expandedShareIds.remove(share.id);
              } else {
                _expandedShareIds.add(share.id);
              }
            }),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: shiftMissing ? Colors.amber.shade600 : checked ? ui.accent.withValues(alpha: 0.5) : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: checked,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(share.id);
                      } else {
                        _selected.remove(share.id);
                      }
                    }),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fileLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('$mavi · ${row.partner.name}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        Text('$dateLabel · $shiftName', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vis PDF',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                    icon: Icon(Icons.picture_as_pdf_outlined, color: ui.accentDark, size: 22),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildRouteCard(share, row, ui),
          ),
      ],
    );
  }

  Widget _buildOrphanRouteCard(PartnerRouteShare share, _MassUi ui) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            share.title ?? share.pdfStoragePath.split('/').last,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Ingen sjåfør koblet — velg bil i Manuell-fanen eller tildel på nytt.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishBar(_MassUi ui) {
    final blocked = _skipped.isNotEmpty;
    final missing = _missingShiftCount;
    final selectedMissing =
        _selected.where((id) => _effectiveShiftId(id) == null).length;
    final canPublish = _skipped.isEmpty &&
        _staged.isNotEmpty &&
        _selected.isNotEmpty &&
        selectedMissing == 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final statusText = blocked
            ? 'Fordel ${_skipped.length} manuell(e) PDF først'
            : _staged.isEmpty
                ? 'Ingen ruter i kø'
                : selectedMissing > 0
                    ? '$selectedMissing valgte rute(r) mangler skift · $_readyShiftCount OK totalt'
                    : canPublish
                        ? 'Gå gjennom «Per sjåfør» / «Alle ruter» og åpne PDF-er før publisering · ${_selected.length} valgt'
                        : 'Velg ruter og skift før publisering';

        final status = Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selectedMissing > 0
                ? Colors.red.shade800
                : _multiLoadDriverCount > 0 && canPublish
                    ? Colors.orange.shade900
                    : Colors.grey.shade800,
          ),
        );

        final btnGrey = FilledButton.icon(
          onPressed: _publishing || !canPublish ? null : () => _publish(notifyDriver: false),
          icon: _publishing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.inventory_2_outlined, size: 20),
          label: Text(blocked ? 'Manuell først' : 'Uten varsel (${_selected.length})'),
          style: FilledButton.styleFrom(
            backgroundColor: RouteDispatchStatus.cellColor(RouteDispatchStatus.registered),
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        );

        final btnSms = FilledButton.icon(
          onPressed: _publishing || !canPublish ? null : () => _publish(notifyDriver: true),
          icon: _publishing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.rocket_launch_outlined, size: 20),
          label: Text(
            blocked ? 'Manuell først' : '$_withNotifyLabel (${_selected.length})',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: ui.accentDark,
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status,
              const SizedBox(height: 10),
              btnGrey,
              const SizedBox(height: 8),
              btnSms,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: status),
            const SizedBox(width: 12),
            btnGrey,
            const SizedBox(width: 10),
            btnSms,
          ],
        );
      },
    );
  }

  Widget _buildDriverCentricList(_MassUi ui) {
    if (_staged.isEmpty && _skipped.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(ui.emptyHint, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700, height: 1.45)),
        ),
      );
    }

    final rows = _showAllDrivers
        ? [..._maviFleet]
        : _maviFleet.where((r) => _staged.any((s) => s.partnerVehicleId == r.vehicle.id)).toList();
    rows.sort((a, b) {
      final aMulti = _visibleStaged.where((s) => s.partnerVehicleId == a.vehicle.id).length >= 2;
      final bMulti = _visibleStaged.where((s) => s.partnerVehicleId == b.vehicle.id).length >= 2;
      if (aMulti != bMulti) return aMulti ? -1 : 1;
      final ac = _visibleStaged.where((s) => s.partnerVehicleId == a.vehicle.id).length;
      final bc = _visibleStaged.where((s) => s.partnerVehicleId == b.vehicle.id).length;
      return bc.compareTo(ac);
    });

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildScrollListHeader(ui, showFilters: false),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                dense: true,
                title: Text(
                  _showAllDrivers ? 'Alle ${_maviFleet.length} sjåfører' : '$_driversWithRoutesCount sjåfører med rute',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                value: _showAllDrivers,
                activeThumbColor: ui.accentDark,
                onChanged: (v) => setState(() => _showAllDrivers = v),
              ),
            ],
          ),
        ),
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Ingen sjåfører med rute i kø.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildDriverSection(rows[i], ui),
                childCount: rows.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDriverSection(FleetPartnerVehicleRow row, _MassUi ui) {
    final vid = row.vehicle.id;
    final routes = _visibleStaged.where((s) => s.partnerVehicleId == vid).toList();
    final mavi = MaviUnitCodes.normalize(row.vehicle.unitCode);
    final portal = _portalByVehicle[vid];
    final phone = portal?.phone ?? row.vehicle.phone;
    final hasPhone = phone != null && phone.trim().length >= 8;
    final lanes = routes.map(_stowingForShare).whereType<String>().toSet().toList()..sort();
    final multi = routes.length >= 2;

    if (routes.isEmpty && !_showAllDrivers) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: multi
              ? Colors.orange.shade400
              : routes.isNotEmpty
                  ? ui.accent.withValues(alpha: 0.35)
                  : Colors.grey.shade300,
          width: multi ? 2 : 1,
        ),
        color: multi
            ? Colors.orange.shade50.withValues(alpha: 0.65)
            : routes.isNotEmpty
                ? ui.surfaceTint.withValues(alpha: 0.5)
                : Colors.grey.shade50,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: routes.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: multi
                ? Colors.orange.shade100
                : routes.isNotEmpty
                    ? ui.accent.withValues(alpha: 0.2)
                    : Colors.grey.shade200,
            child: Icon(
              multi
                  ? Icons.layers_outlined
                  : routes.isNotEmpty
                      ? Icons.check
                      : Icons.more_horiz,
              size: 18,
              color: multi ? Colors.orange.shade900 : routes.isNotEmpty ? ui.accentDark : Colors.grey,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text('$mavi · ${row.partner.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              if (multi)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${routes.length} LAST',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          subtitle: Text(
            routes.isEmpty
                ? 'Venter på PDF'
                : multi
                    ? '${routes.length} last · Lane ${lanes.join(", ")} · ${hasPhone ? "SMS OK" : "uten telefon"}'
                    : '${routes.length} rute · ${lanes.isNotEmpty ? "Lane ${lanes.first}" : "PDF"} · ${hasPhone ? "SMS OK" : "uten telefon"}',
            style: TextStyle(
              fontSize: 11,
              color: routes.isEmpty ? Colors.grey : Colors.grey.shade700,
              fontWeight: multi ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          children: routes.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text('Ingen rute ennå.', style: TextStyle(fontSize: 12)),
                  ),
                ]
              : routes.map((share) => _buildRouteCompactTile(share, row, ui)).toList(),
        ),
      ),
    );
  }

  Widget _buildRouteCard(PartnerRouteShare share, FleetPartnerVehicleRow row, _MassUi ui) {
    final checked = _selected.contains(share.id);
    final noteCtrl = _noteByShare.putIfAbsent(share.id, () => TextEditingController(text: share.notes ?? ''));
    final lane = _stowingForShare(share);

    final mavi = MaviUnitCodes.normalize(row.vehicle.unitCode);
    final fileLabel = (share.title ?? share.pdfStoragePath.split('/').last).split('—').last.trim();
    final start = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);
    final startLabel = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    final routeDay = _routeDayFor(share.id);
    final dateLabel = DateFormat('EEE d.M.y', 'nb').format(routeDay);
    final shiftId = _effectiveShiftId(share.id);
    final shiftMissing = shiftId == null;
    final shiftName = _shiftLabel(shiftId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: shiftMissing
              ? Colors.amber.shade600
              : checked
                  ? ui.accent.withValues(alpha: 0.55)
                  : Colors.grey.shade300,
          width: shiftMissing || checked ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: checked,
                activeColor: ui.accentDark,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(share.id);
                  } else {
                    _selected.remove(share.id);
                  }
                }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fileLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                      '$mavi · ${row.partner.name}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    Text(
                      '$dateLabel · ${lane != null ? 'Lane $lane' : shiftName ?? 'Uten skift'}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Åpne PDF',
                onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                icon: Icon(Icons.picture_as_pdf_outlined, color: ui.accentDark),
              ),
              IconButton(
                tooltip: 'Slett fra kø',
                onPressed: _busyUpload ? null : () => _removeShare(share),
                icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: share.partnerVehicleId,
            isExpanded: true,
            decoration: _fieldDeco('Bytt sjåfør / MAVI'),
            items: _maviFleet
                .map((r) => DropdownMenuItem(
                      value: r.vehicle.id,
                      child: Text('${MaviUnitCodes.normalize(r.vehicle.unitCode)} · ${r.partner.name}', overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: _busyUpload
                ? null
                : (vid) {
                    if (vid != null && vid != share.partnerVehicleId) _reassignShare(share, vid);
                  },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: _fieldDeco('Notat til sjåfør (vises i portal / SMS)'),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 720;
              final dateBtn = OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: routeDay,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) await _setShareRouteDay(share, picked);
                },
                icon: const Icon(Icons.event, size: 18),
                label: Text(dateLabel, overflow: TextOverflow.ellipsis),
              );
              final shiftField = DropdownButtonFormField<String>(
                value: shiftId,
                isExpanded: true,
                decoration: _fieldDeco('Skiftplan').copyWith(
                  errorText: shiftMissing && checked ? 'Velg dag- eller kveldsrute' : null,
                ),
                items: _routeShifts
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _shiftByShare[share.id] = v);
                  await PartnerService.updateRouteShareFields(share.id, {'shift_id': v});
                },
              );
              final startBtn = OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: start);
                  if (picked != null) setState(() => _startByShare[share.id] = picked);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('Start $startLabel'),
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateBtn,
                    const SizedBox(height: 8),
                    shiftField,
                    const SizedBox(height: 8),
                    startBtn,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 2, child: dateBtn),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: shiftField),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: startBtn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );

  Widget _buildAssignmentOverview(_MassUi ui) {
    if (_importLog.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _isSap
                ? 'Importlogg fylles når SAP-e-poster hentes inn og fordeles.'
                : 'Importlogg fylles når du laster opp PDF-er.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _importLog.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final row = _importLog[i];
        final ok = row.status == 'ok';
        return ListTile(
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.15),
            child: Icon(ok ? Icons.check : Icons.priority_high, color: ok ? Colors.green.shade800 : Colors.orange.shade900, size: 20),
          ),
          title: Text(row.fileName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          subtitle: Text(
            ok
                ? 'Automatisk → ${row.maviCode ?? "?"}${row.stowingLane != null ? " · Lane ${row.stowingLane}" : ""}${row.driverLabel != null ? " · ${row.driverLabel}" : ""}'
                : 'Manuell: ${row.reason ?? "ukjent"}',
            style: TextStyle(fontSize: 11.5, color: ok ? Colors.grey.shade700 : Colors.orange.shade900),
          ),
        );
      },
    );
  }

  Widget _buildSkippedList(_MassUi ui) {
    if (_skipped.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Alle PDF-er er automatisk fordelt til riktig MAVI-sjåfør.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _skipped.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == 0) {
          return routeManualAttentionBanner(
            count: _skipped.length,
            onOpenManual: () {},
          );
        }
        final item = _skipped[i - 1];
        return Card(
          elevation: 0,
          color: ui.surfaceTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (item.reason != null)
                  Text(item.reason!, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
                if (item.detectedCode != null)
                  Text('Detektert: ${item.detectedCode}', style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: item.selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Velg sjåfør / MAVI-bil',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  items: _maviFleet
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.vehicle.id,
                          child: Text(
                            '${MaviUnitCodes.normalize(r.vehicle.unitCode)} · ${r.partner.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => item.selectedVehicleId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: item.shiftId,
                  decoration: const InputDecoration(
                    labelText: 'Skiftplan',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  items: _routeShifts
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => item.shiftId = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: item.noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notat til sjåfør',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Starttid', style: TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${item.startTime.hour.toString().padLeft(2, '0')}:'
                    '${item.startTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.schedule, size: 20),
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: item.startTime);
                    if (picked != null) setState(() => item.startTime = picked);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: item.bytes.isEmpty
                          ? null
                          : () => PartnerRoutePdfActions.openPdfBytes(
                                context,
                                bytes: item.bytes,
                                title: item.fileName,
                              ),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('Vis PDF'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busyUpload ? null : () => _assignSkipped(item),
                        style: FilledButton.styleFrom(backgroundColor: ui.accentDark),
                        child: const Text('Tildel rute'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}

class _MassUi {
  final Color accent;
  final Color accentDark;
  final Color surfaceTint;
  final String title;
  final String badge;
  final String tagline;
  final IconData icon;
  final List<String> steps;
  final String emptyHint;

  const _MassUi({
    required this.accent,
    required this.accentDark,
    required this.surfaceTint,
    required this.title,
    required this.badge,
    required this.tagline,
    required this.icon,
    required this.steps,
    required this.emptyHint,
  });

  factory _MassUi.of(PartnerRouteMassSource source) {
    if (source == PartnerRouteMassSource.sap) {
      return _MassUi(
        accent: const Color(0xFF42A5F5),
        accentDark: const Color(0xFF1565C0),
        surfaceTint: const Color(0xFFE3F2FD),
        title: 'Ruter fra SAP',
        badge: 'SAP · e-post',
        tagline: 'Importer, kontroller sjåfører og PDF-er, publiser når alt stemmer',
        icon: Icons.mark_email_read_outlined,
        steps: [
          'SAP sender PDF til ${SapRoutesConfig.inboundAddress} (emne «${SapRoutesConfig.expectedSubject}»).',
          'DriftPro henter e-post automatisk og leser MAVI-nummer fra PDF (Trip Overview).',
          'Ruter fordeles til riktig sjåfør — det som ikke matcher havner under «Manuell tildeling».',
          'Kontroller skift, notat og starttid — «Publiser uten varsel» eller «Publiser med SMS».',
        ],
        emptyHint:
            'Ingen SAP-ruter i kø ennå.\n\nNår e-post kommer til ${SapRoutesConfig.inboundAddress}, '
            'fordeler systemet automatisk. Bruk «Hent nye fra SAP» for å synce manuelt.',
      );
    }
    return _MassUi(
      accent: DriftProTheme.primaryGreen.withValues(alpha: 0.7),
      accentDark: DriftProTheme.primaryGreen,
      surfaceTint: const Color(0xFFE8F5E9),
      title: 'AUTO MASS',
      badge: 'Manuell PDF',
      tagline: 'Last opp PDF-er, kontroller fordeling, publiser når alt stemmer',
      icon: Icons.auto_awesome,
      steps: [
        'Last opp én eller mange rute-PDF-er fra PC (filnavn spiller ingen rolle).',
        'Systemet leser MAVI fra PDF og fordeler til sjåfør i flåten.',
        'PDF uten treff legges under «Manuell tildeling» — velg bil og skift der.',
        'Velg ruter, juster notat/skift/starttid — publiser uten varsel eller med SMS.',
      ],
      emptyHint:
          'Ingen ruter i kø.\n\nLast opp PDF-er med knappen over. '
          'MAVI hentes fra Trip Overview / Resource ID inne i filen.',
    );
  }
}
