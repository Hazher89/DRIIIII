import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/constants/route_dispatch_status.dart';
import '../../../core/constants/sap_routes_config.dart';
import '../../../core/services/partner/fleet_shift_filters.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/postal_code_registry.dart';
import '../../../core/services/partner/route_pdf_bytes_cache.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/partner/route_shift_resolver.dart';
import '../../../core/services/partner/sap_route_import_service.dart';
import '../../../core/services/partner/sap_route_inbox_live.dart';
import '../../../core/services/partner/staged_route_duplicate_helper.dart';
import '../../../core/services/notification/publish_action_labels.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/notification_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/sap_route_inbox.dart';
import 'partner_mass_route_queue_card.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_pdf_thumbnail.dart';
import 'partner_route_publish_review_dialog.dart';
import 'partner_route_workflow_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

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
    this.selectedVehicleId,
    TimeOfDay? startTime,
  })  : startTime = startTime ?? const TimeOfDay(hour: 6, minute: 0),
        noteCtrl = TextEditingController();
}

String _friendlyImportError(Object error) {
  final msg = error.toString();
  if (msg.contains('malformed_path')) {
    return 'Skylagring avviste filstien (ugyldig tegn i filnavn). Lagrer nå via Supabase i stedet — prøv på nytt.';
  }
  if (msg.contains('Dropbox') || msg.contains('dropbox')) {
    return 'Skylagring feilet. Sjekk tilkobling under Mer → Fillagring, eller prøv import på nytt.';
  }
  if (msg.contains('FunctionException')) {
    return 'Serverfeil ved lagring av PDF. Prøv på nytt — systemet bruker alternativ lagring ved behov.';
  }
  if (msg.length > 160) return '${msg.substring(0, 157)}…';
  return msg;
}

enum PartnerRouteMassSource { manual, sap }

enum _MassTab { skipped, duplicates, drivers, missingShift, allRoutes }

/// Fanerekkefølge: Manuell → Duplikater → Flere last → Mangler skift → Ruter.
const _kTabManual = 0;
const _kTabDuplicates = 1;
const _kTabMultiLoad = 2;
const _kTabMissingShift = 3;
const _kTabRoutes = 4;

enum _RouteQueueFilter { all, missingShift, ready, selected }

enum _DateQueueAction { clearAll, publishNoSms, publishSms }

const _routeCardGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 280,
  childAspectRatio: 0.54,
  crossAxisSpacing: 10,
  mainAxisSpacing: 10,
);

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
  _MassTab _sheetTab = _MassTab.skipped;
  _RouteQueueFilter _queueFilter = _RouteQueueFilter.all;
  bool _sapSyncing = false;
  int _sapPendingInbox = 0;
  List<SapRouteInboxItem> _pendingInboxItems = [];
  bool _importAborted = false;
  RealtimeChannel? _sapLiveChannel;
  bool _showAllDrivers = false;
  bool _guideExpanded = false;
  bool _fillingShifts = false;
  bool _initialTabSet = false;
  List<FleetPartnerVehicleRow> _expandedMaviFleet = const [];
  bool _selectionInitialized = false;
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
    _importAborted = true;
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
    _reload().then((_) async {
      if (!_isSap || !mounted) return;
      _bindSapLive();
      await _refreshSapInboxCounts();
      // Ingen auto-import — bruker må trykke «Importer» etter å ha sett ventende PDF-er.
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
      final pending = await PartnerService.fetchSapRouteInboxPending(cid);
      if (mounted) {
        setState(() {
          _sapPendingInbox = pending.length;
          _pendingInboxItems = pending;
        });
      }
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
        detectedCode: item.detectedMaviCode ??
            RoutePdfTextService.extractResourceIdFromFileName(item.fileName),
        sapInboxId: item.id,
      ));
    }
    return added;
  }

  Future<void> _syncSapInbox() async {
    if (!_isSap || _sapSyncing || _importAborted) return;
    setState(() => _sapSyncing = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null || _importAborted) return;
      await PartnerService.reconcileSapInboxWithStagedQueue(cid);
      final pending = await PartnerService.fetchSapRouteInboxPending(cid);
      if (!mounted || _importAborted) return;
      setState(() {
        _sapPendingInbox = pending.length;
        _pendingInboxItems = pending;
      });
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
      if (_importAborted || !mounted) return;
      final newSkipped = <_SkippedPdf>[];
      for (final s in result.skippedItems) {
        final exists = _skipped.any((x) => x.sapInboxId == s.inboxId);
        if (exists) continue;
        newSkipped.add(_SkippedPdf(
          fileName: s.fileName,
          bytes: Uint8List.fromList(s.bytes),
          reason: s.reason,
          detectedCode: s.detectedCode ??
              RoutePdfTextService.extractResourceIdFromFileName(s.fileName),
          sapInboxId: s.inboxId,
        ));
      }

      if (mounted) {
        setState(() {
          _importLog = [..._importLog, ..._mapImportLines(result.lines)];
          _skipped.addAll(newSkipped);
        });
      }
      await _autoAssignReadySkipped(newSkipped);
      await _reload(preferRoutesTab: result.imported > 0, expectedMinStaged: result.imported);
      await _refreshSapInboxCounts();
      if (mounted) {
        if (result.imported > 0 && _staged.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'SAP-ruter ble importert, men køen vises ikke. Prøv å lukke og åpne på nytt.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 8),
            ),
          );
        } else if (result.imported == 0 && (result.skipped > 0 || _skipped.isNotEmpty)) {
          setState(() => _sheetTab = _MassTab.skipped);
        }
        if (result.imported > 0 || result.skipped > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.imported > 0
                    ? 'SAP: ${result.imported} rute(r) i kø.'
                        '${result.skipped > 0 ? " ${result.skipped} trenger manuell tildeling." : ""} '
                        'Sjekk PDF-forside på kortene før publisering.'
                    : 'SAP: ingen auto-fordeling — ${result.skipped} PDF under «Manuell».',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
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

  List<FleetPartnerVehicleRow> get _maviFleet {
    final byVehicleId = <String, FleetPartnerVehicleRow>{};
    for (final row in widget.fleet) {
      byVehicleId[row.vehicle.id] = row;
    }
    for (final row in _expandedMaviFleet) {
      byVehicleId.putIfAbsent(row.vehicle.id, () => row);
    }
    return PartnerService.filterMaviFleetOnly(byVehicleId.values);
  }

  Future<void> _refreshExpandedFleet(String companyId) async {
    final fresh = PartnerService.filterMaviFleetOnly(
      await PartnerService.fetchCompanyFleet(companyId),
    );
    if (!mounted) return;
    _expandedMaviFleet = fresh;
  }

  String _normalizedMaviKey(String? code) {
    if (code == null || code.trim().isEmpty) return '';
    return RoutePdfTextService.normalizeUnitCodeForMatch(MaviUnitCodes.normalize(code));
  }

  List<StagedRouteDuplicateGroup> get _duplicateGroups =>
      StagedRouteDuplicateHelper.findGroups(_staged);

  List<PartnerRouteShare> get _orphanShares =>
      _staged.where((s) => _rowForShare(s) == null).toList();

  /// Kun 100 % identisk PDF-innhold — flere last samme MAVI samme dag er normalt.
  int get _duplicatesTabCount => _duplicateExtraCount;

  String? _maviCodeForShare(PartnerRouteShare share) {
    final title = share.title ?? '';
    final fileLabel = title.contains('—')
        ? title.split('—').last.trim()
        : share.pdfStoragePath.split('/').last;
    return RoutePdfTextService.extractResourceIdFromFileName(fileLabel) ??
        RoutePdfTextService.extractResourceIdFromFileName(title) ??
        _maviFromRouteTitle(title);
  }

  String? _maviFromRouteTitle(String title) {
    final m = RegExp(r'Rute\s+(\S+)', caseSensitive: false).firstMatch(title.trim());
    if (m == null) return null;
    final raw = m.group(1)!.trim();
    if (raw.isEmpty) return null;
    return MaviUnitCodes.normalize(raw);
  }

  FleetPartnerVehicleRow? _fleetRowForMaviCode(String? code) {
    final want = _normalizedMaviKey(code);
    if (want.isEmpty) return null;
    for (final row in _maviFleet) {
      if (_normalizedMaviKey(row.vehicle.unitCode) == want) return row;
    }
    return null;
  }

  int get _duplicateExtraCount =>
      StagedRouteDuplicateHelper.totalExtraDuplicates(_duplicateGroups);

  Set<String> get _allDuplicateRemoveIds {
    final remove = <String>{};
    for (final g in _duplicateGroups) {
      remove.addAll(StagedRouteDuplicateHelper.idsToRemoveShares(g.shares));
    }
    return remove;
  }

  int get _allDuplicateExtraCount => _allDuplicateRemoveIds.length;

  Set<String> get _duplicateRouteIds {
    final ids = <String>{};
    for (final g in _duplicateGroups) {
      for (final s in g.shares) {
        ids.add(s.id);
      }
    }
    return ids;
  }

  int get _duplicateGroupCount => _duplicateGroups.length;

  int get _stagedCountAfterDedup => _staged.length - _allDuplicateExtraCount;

  void _selectReadyNonDuplicates() {
    final dupIds = StagedRouteDuplicateHelper.allDuplicateIds(_duplicateGroups);
    setState(() {
      _selected
        ..clear()
        ..addAll(
          _staged
              .where((s) {
                if (dupIds.contains(s.id)) return false;
                return _effectiveShiftId(s.id) != null;
              })
              .map((s) => s.id),
        );
    });
  }

  Future<void> _removeSharesByIds(List<String> removeIds) async {
    if (removeIds.isEmpty) return;
    setState(() => _busyUpload = true);
    try {
      for (final id in removeIds) {
        final share = _staged.where((s) => s.id == id).firstOrNull;
        if (share == null) continue;
        await PartnerService.deleteRouteShare(share);
        _selected.remove(id);
      }
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke fjerne ruter: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _removeDuplicateGroupShares(List<PartnerRouteShare> shares) async {
    if (shares.length < 2) return;
    final extra = shares.length - 1;
    final label = StagedRouteDuplicateHelper.countLabel(shares.length);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Behold én i denne gruppen?'),
        content: Text(
          'Fant ${shares.length} like ruter ($label). Systemet beholder én '
          '(med skift om mulig) og sletter $extra.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Behold én her ($extra slettes)'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _removeSharesByIds(StagedRouteDuplicateHelper.idsToRemoveShares(shares));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fjernet $extra duplikat-rute(r).')),
      );
    }
  }

  Future<void> _relinkOrphanShare(PartnerRouteShare share) async {
    final code = _maviCodeForShare(share);
    final row = _fleetRowForMaviCode(code);
    if (row == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              code == null
                  ? 'Fant ikke MAVI i filnavn eller tittel.'
                  : 'Ingen sjåfør matcher $code i flåten.',
            ),
          ),
        );
      }
      return;
    }
    await _reassignShare(share, row.vehicle.id);
  }

  Future<int> _autoRelinkOrphanSharesQuiet(List<PartnerRouteShare> staged) async {
    var linked = 0;
    for (final share in staged) {
      if (_rowForShare(share) != null) continue;
      final code = _maviCodeForShare(share);
      final row = _fleetRowForMaviCode(code);
      if (row == null) continue;
      final baseTitle = share.title ?? share.pdfStoragePath.split('/').last;
      final fileLabel = baseTitle.contains('—')
          ? baseTitle.split('—').last.trim()
          : baseTitle;
      await PartnerService.reassignStagedRouteShare(
        share: share,
        partnerId: row.partner.id,
        partnerVehicleId: row.vehicle.id,
        title: 'Rute ${MaviUnitCodes.compactLabel(row.vehicle.unitCode)} — $fileLabel',
      );
      linked++;
    }
    return linked;
  }

  Future<void> _relinkAllOrphanShares() async {
    final orphans = _orphanShares;
    if (orphans.isEmpty) return;
    setState(() => _busyUpload = true);
    try {
      final linked = await _autoRelinkOrphanSharesQuiet(orphans);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              linked > 0
                  ? 'Koblet $linked rute(r) til sjåfør fra filnavn/tittel.'
                  : 'Ingen foreslåtte sjåfører kunne kobles automatisk.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kobling feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _dismissSkippedPdf(_SkippedPdf item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern manuell PDF?'),
        content: Text(item.fileName),
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
    try {
      if (item.sapInboxId != null) {
        await PartnerService.dismissSapRouteInbox(item.sapInboxId!);
      }
      item.noteCtrl.dispose();
      if (mounted) {
        setState(() => _skipped.remove(item));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke fjerne: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deduplicateAllKeepOneEach() async {
    final removeIds = _allDuplicateRemoveIds.toList();
    if (removeIds.isEmpty) return;
    final extra = removeIds.length;
    final groups = _duplicateGroups.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Behold én av hver?'),
        content: Text(
          'Fant $extra ekstra kopi(er) av identisk PDF i $groups gruppe(r).\n\n'
          'Systemet beholder én rute per gruppe (helst med skift) og sletter resten fra køen. '
          'Ulike last/rute for samme bil på samme dag påvirkes ikke.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Behold én av hver ($extra slettes)'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _removeSharesByIds(removeIds);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fjernet $extra duplikat-rute(r). Én beholdt per gruppe.')),
      );
    }
  }

  Future<void> _removeDuplicateRoutes() async => _deduplicateAllKeepOneEach();

  Widget _buildDuplicateBanner(_MassUi ui) {
    if (_allDuplicateExtraCount == 0) {
      return const SizedBox.shrink();
    }
    final extra = _allDuplicateExtraCount;
    final inGroups = _duplicateRouteIds.length;
    final groups = _duplicateGroupCount;
    final after = _stagedCountAfterDedup;
    final total = _staged.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.copy_all_outlined, color: Colors.deepPurple.shade800, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Identisk PDF i køen',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: Colors.deepPurple.shade900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _duplicateStatChip('$total totalt', Colors.deepPurple.shade900),
                            _duplicateStatChip('$inGroups i duplikat', Colors.deepPurple.shade800),
                            _duplicateStatChip('$extra ekstra', Colors.orange.shade900),
                            _duplicateStatChip('$groups gruppe(r)', Colors.deepPurple.shade700),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Etter «Behold én av hver»: $after ruter igjen '
                          '(sletter $extra identiske kopier, beholder én per gruppe)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepPurple.shade900,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _busyUpload || _publishing ? null : () => _setTabIndex(_kTabDuplicates),
                    child: const Text('Se duplikater'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busyUpload || _publishing ? null : _deduplicateAllKeepOneEach,
                    child: Text('Behold én av hver (slett $extra)'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _duplicateStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Future<Map<String, String>> _resolveShiftIdsForStaged({
    required List<PartnerRouteShare> staged,
    required List<FleetShiftDefinition> shifts,
  }) async {
    final shiftById = <String, String>{};
    for (final s in staged) {
      try {
        final pdfText = await RouteShiftResolver.loadPdfTextForShare(s);
        final sid = await RouteShiftResolver.resolveShiftIdForStagedShare(
          share: s,
          allShifts: shifts,
          pdfText: pdfText,
        );
        if (sid != null && sid.isNotEmpty) {
          shiftById[s.id] = sid;
          if (s.shiftId != sid) {
            try {
              await PartnerService.updateRouteShareFields(s.id, {'shift_id': sid});
            } catch (_) {}
          }
        } else {
          shiftById[s.id] = s.shiftId ?? '';
        }
      } catch (_) {
        shiftById[s.id] = s.shiftId ?? '';
      }
    }
    return shiftById;
  }

  void _applyStagedQueueState({
    required List<PartnerRouteShare> staged,
    required List<FleetShiftDefinition> shifts,
    required Map<String, String> shiftById,
    required Map<String, PartnerPortalAccount> portals,
    List<_SkippedPdf> manualSkipped = const [],
    bool preferRoutesTab = false,
    bool preserveSelection = false,
  }) {
    _shifts = shifts;
    _staged = staged;
    for (final s in manualSkipped) {
      if (!_skipped.any((x) => x.sapInboxId == s.sapInboxId)) {
        _skipped.add(s);
      }
    }
    _portalByVehicle = portals;
    if (preserveSelection) {
      _selected.removeWhere((id) => !_staged.any((s) => s.id == id));
    } else if (!_selectionInitialized) {
      // Ikke auto-velg — bruker må gjennomgå og velge ruter manuelt før publisering.
      _selected.clear();
      _selectionInitialized = true;
    } else if (!preserveSelection) {
      _selected.removeWhere((id) => !_staged.any((s) => s.id == id));
    }
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
    if (preferRoutesTab && staged.isNotEmpty) {
      _sheetTab = _MassTab.allRoutes;
      _queueFilter = _RouteQueueFilter.all;
    } else if (!_initialTabSet) {
      if (_skipped.isNotEmpty) {
        _sheetTab = _MassTab.skipped;
      } else if (_duplicateExtraCount > 0) {
        _sheetTab = _MassTab.duplicates;
      } else if (_routesMissingShift.isNotEmpty) {
        _sheetTab = _MassTab.missingShift;
        _queueFilter = _RouteQueueFilter.missingShift;
      } else if (staged.isNotEmpty) {
        _sheetTab = _MassTab.allRoutes;
        _queueFilter = _RouteQueueFilter.all;
      }
    }
    _initialTabSet = true;
  }

  Future<void> _reload({bool preferRoutesTab = false, int expectedMinStaged = 0}) async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      try {
        await PartnerService.ensureCanonicalFleetShifts(cid);
      } catch (_) {}
      final shifts = await PartnerService.fetchFleetShifts(cid);
      if (_isSap) {
        try {
          await PartnerService.reconcileSapInboxWithStagedQueue(cid);
        } catch (_) {}
      }
      List<PartnerRouteShare> staged = const [];
      for (var attempt = 0; attempt < 4; attempt++) {
        staged = await PartnerService.fetchStagedRouteShares(
          cid,
          importSource: _isSap
              ? PartnerService.stagedImportSap
              : PartnerService.stagedImportManual,
        );
        if (expectedMinStaged <= 0 || staged.length >= expectedMinStaged || attempt == 3) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
      if (!mounted) return;
      setState(() {
        _applyStagedQueueState(
          staged: staged,
          shifts: shifts,
          shiftById: {
            for (final s in staged) s.id: s.shiftId ?? '',
          },
          portals: const {},
          preferRoutesTab: preferRoutesTab,
        );
        _loading = false;
      });
      unawaited(_enrichStagedQueue(
        companyId: cid,
        staged: staged,
        shifts: shifts,
        preferRoutesTab: preferRoutesTab,
        preserveSelection: true,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kunne ikke laste rute-kø: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _enrichStagedQueue({
    required String companyId,
    required List<PartnerRouteShare> staged,
    required List<FleetShiftDefinition> shifts,
    bool preferRoutesTab = false,
    bool preserveSelection = false,
  }) async {
    try {
      await _refreshExpandedFleet(companyId);
      var working = staged;
      final relinked = await _autoRelinkOrphanSharesQuiet(working);
      if (relinked > 0) {
        working = await PartnerService.fetchStagedRouteShares(
          companyId,
          importSource: _isSap
              ? PartnerService.stagedImportSap
              : PartnerService.stagedImportManual,
        );
      }
      final manualSkipped = _isSap
          ? await _collectSapManualSkipped(companyId)
          : const <_SkippedPdf>[];
      final portals = <String, PartnerPortalAccount>{};
      final partnerIds = _maviFleet.map((r) => r.partner.id).toSet();
      for (final pid in partnerIds) {
        for (final a in await PartnerService.fetchPortalAccounts(pid)) {
          if (a.partnerVehicleId != null) portals[a.partnerVehicleId!] = a;
        }
      }
      await PostalCodeRegistry.ensureLoaded();
      final shiftById = await _resolveShiftIdsForStaged(staged: working, shifts: shifts);
      if (manualSkipped.isNotEmpty) {
        await _autoAssignReadySkipped(manualSkipped);
      }
      if (!mounted) return;
      setState(() {
        _applyStagedQueueState(
          staged: working,
          shifts: shifts,
          shiftById: shiftById,
          portals: portals,
          manualSkipped: manualSkipped,
          preferRoutesTab: preferRoutesTab,
          preserveSelection: preserveSelection,
        );
      });
      if (relinked > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Koblet $relinked rute(r) automatisk til riktig MAVI fra filnavn/tittel.',
            ),
          ),
        );
      }
    } catch (_) {}
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
      final mavi = row != null ? MaviUnitCodes.compactLabel(row.vehicle.unitCode) : '?';
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
          mavi: row != null ? MaviUnitCodes.compactLabel(row.vehicle.unitCode) : '?',
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
        if (_skipped.isNotEmpty)
          '${_skipped.length} manuell(e) PDF venter i «Manuell»-fanen og sendes ikke med nå.',
        if (_duplicateExtraCount > 0)
          '$_duplicateExtraCount duplikat-rute(r) ligger fortsatt i køen — vurder «Behold én».',
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
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg ruter du vil publisere først.')),
      );
      return;
    }
    if (_staged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen ruter i kø.')),
      );
      return;
    }
    if (!await _guardPublishPrerequisites()) return;

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
        _setTabIndex(_kTabMissingShift);
        return;
      }

      final routeIds = Set<String>.from(_selected);
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
                  'Tøm hele køen ($_queueTotalCount)',
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
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.shade300),
          color: busy ? Colors.grey.shade100 : Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.tune, size: 18, color: Colors.blueGrey.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Dato & publisering (${groups.length} dager)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: busy ? Colors.grey : Colors.blueGrey.shade900,
                ),
                overflow: TextOverflow.ellipsis,
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
      final mavi = row != null ? MaviUnitCodes.compactLabel(row.vehicle.unitCode) : '?';
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

    final bundle = RoutePdfTextService.parseBundle(
      bytes,
      fallbackDate: _routeDate,
      fileName: file.name,
    );
    final code = bundle.meta.maviCode;
    if (code == null) {
      return (
        row: _PdfAssignmentRow(
          fileName: file.name,
          status: 'skipped',
          reason: 'Fant ikke MAVI-nummer i PDF eller filnavn',
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
    try {
      final existingStaged = await PartnerService.fetchStagedRouteShares(
        companyId,
        importSource: PartnerService.stagedImportManual,
      );
      final dup = StagedRouteDuplicateHelper.findDuplicateInStaged(
        staged: existingStaged,
        pdfSearchText: bundle.searchText,
        bytes: bytes,
      );
      if (dup != null) {
        return (
          row: _PdfAssignmentRow(
            fileName: file.name,
            status: 'skipped',
            maviCode: MaviUnitCodes.normalize(vehicle.unitCode),
            reason: 'Duplikat — allerede i kø',
          ),
          shareId: dup.id,
          stowing: RoutePdfTextService.parseStowingLane(bundle.searchText),
          start: bundle.schedule.routeStartAt != null
              ? TimeOfDay(
                  hour: bundle.schedule.routeStartAt!.hour,
                  minute: bundle.schedule.routeStartAt!.minute,
                )
              : null,
        );
      }

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
    } catch (e) {
      return (
        row: _PdfAssignmentRow(
          fileName: file.name,
          status: 'skipped',
          maviCode: code,
          reason: 'Lagring feilet: ${_friendlyImportError(e)}',
        ),
        shareId: null,
        stowing: null,
        start: null,
      );
    }
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
            final isDupInQueue = result.shareId != null &&
                (result.row.reason?.toLowerCase().contains('duplikat') ?? false);
            if (isDupInQueue) {
              continue;
            }
            final bytes = await _readPlatformFile(file);
            String? preselect;
            final code = result.row.maviCode ??
                RoutePdfTextService.extractResourceIdFromFileName(file.name);
            if (code != null) {
              for (final r in _maviFleet) {
                if (MaviUnitCodes.normalize(r.vehicle.unitCode) ==
                    MaviUnitCodes.normalize(code)) {
                  preselect = r.vehicle.id;
                  break;
                }
              }
            }
            newSkipped.add(_SkippedPdf(
              fileName: file.name,
              bytes: bytes ?? Uint8List(0),
              reason: result.row.reason ?? 'Ukjent feil',
              detectedCode: code,
              selectedVehicleId: preselect,
            ));
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
          _skipped.addAll(newSkipped);
          _importLog = log;
        });
      }
      await _autoAssignReadySkipped(newSkipped);
      await _reload(preferRoutesTab: ok > 0);
      if (mounted) {
        if (ok > 0 && _staged.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'PDF-er ble lagret, men køen vises ikke. Lukk og åpne ${_ui.title} på nytt, '
                'eller sjekk fanen Manuell.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 8),
            ),
          );
        } else if (newSkipped.isNotEmpty && ok == 0) {
          setState(() => _sheetTab = _MassTab.skipped);
        }
        final skippedMsg = newSkipped.isEmpty
            ? ''
            : ' ${newSkipped.length} trenger manuell tildeling under «Manuell».';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok > 0
                  ? '${_ui.title}: $ok rute(r) i kø.$skippedMsg Sjekk PDF-forside på kortene før publisering.'
                  : newSkipped.isNotEmpty
                      ? 'Ingen ruter auto-fordelt.$skippedMsg'
                      : 'Ingen PDF-er ble importert — sjekk at filene er gyldige rute-PDF-er.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
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

  Future<String?> _resolveShiftIdForSkipped(_SkippedPdf item) async {
    if (item.bytes.isEmpty) return null;
    final bundle = RoutePdfTextService.parseBundle(
      item.bytes,
      fallbackDate: _routeDate,
      fileName: item.fileName,
    );
    if (_routeShifts.isEmpty) return null;
    final best = await RouteShiftResolver.resolveBestFromPdfText(
      pdfText: bundle.searchText,
      shifts: _routeShifts,
      routeStartAt: bundle.schedule.routeStartAt,
      routeDate: bundle.schedule.routeDate,
      title: item.fileName,
    );
    return best?.id;
  }

  Future<bool> _tryAutoAssignSkipped(_SkippedPdf item) async {
    if (item.selectedVehicleId == null || item.bytes.isEmpty) return false;
    if (item.reason?.toLowerCase().contains('duplikat') == true) return false;

    if ((item.shiftId ?? '').isEmpty) {
      final shiftId = await _resolveShiftIdForSkipped(item);
      if (shiftId == null || shiftId.isEmpty) return false;
      item.shiftId = shiftId;
    }

    final bundle = RoutePdfTextService.parseBundle(
      item.bytes,
      fallbackDate: _routeDate,
      fileName: item.fileName,
    );
    if (bundle.schedule.routeStartAt != null) {
      item.startTime = TimeOfDay(
        hour: bundle.schedule.routeStartAt!.hour,
        minute: bundle.schedule.routeStartAt!.minute,
      );
    }

    await _assignSkipped(item, silent: true);
    return !_skipped.contains(item);
  }

  Future<void> _autoAssignReadySkipped(Iterable<_SkippedPdf> items) async {
    var assigned = 0;
    for (final item in items.toList()) {
      try {
        if (await _tryAutoAssignSkipped(item)) assigned++;
      } catch (_) {}
    }
    if (assigned > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Auto-tildelte $assigned PDF-er (MAVI + skift funnet i PDF).',
          ),
        ),
      );
    }
  }

  Future<void> _assignSkipped(_SkippedPdf item, {bool silent = false}) async {
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
      final bundle = RoutePdfTextService.parseBundle(
        item.bytes,
        fallbackDate: _routeDate,
        fileName: item.fileName,
      );
      final shareId = await PartnerService.createStagedRouteShareFromPdf(
        companyId: cid,
        partner: row.partner,
        vehicle: row.vehicle,
        fileName: item.fileName,
        bytes: item.bytes,
        routeDate: bundle.schedule.routeDate,
        notes: item.noteCtrl.text,
        parsed: bundle,
        stagedImportSource: _isSap
            ? PartnerService.stagedImportSap
            : PartnerService.stagedImportManual,
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
          if (_skipped.isEmpty) {
            if (_duplicateExtraCount > 0) {
              _sheetTab = _MassTab.duplicates;
            } else if (_missingShiftCount > 0) {
              _sheetTab = _MassTab.missingShift;
            } else {
              _sheetTab = _MassTab.allRoutes;
            }
          }
        });
      }
      await _reload();
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.fileName} tildelt ${row.vehicle.unitCode}')),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tildeling feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busyUpload = false);
    }
  }

  Future<void> _clearAllSkippedPdfsQuiet() async {
    for (final item in List<_SkippedPdf>.from(_skipped)) {
      if (item.sapInboxId != null) {
        await PartnerService.dismissSapRouteInbox(item.sapInboxId!);
      }
      item.noteCtrl.dispose();
    }
    if (mounted) {
      setState(() => _skipped.clear());
    }
  }

  int get _queueTotalCount => _staged.length + _skipped.length;

  Future<void> _clearAllStaged() async {
    if (_staged.isEmpty && _skipped.isEmpty) return;
    final stagedN = _staged.length;
    final manualN = _skipped.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tøm hele køen?'),
        content: Text(
          stagedN > 0 && manualN > 0
              ? 'Fjerner $stagedN rute(r) fra køen og $manualN manuell(e) PDF-er.'
              : stagedN > 0
                  ? 'Fjerner alle $stagedN rute(r) fra køen.'
                  : 'Fjerner alle $manualN manuell(e) PDF-er fra køen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            child: const Text('Tøm alt'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyUpload = true);
    try {
      RoutePdfBytesCache.clear();
      for (final s in List<PartnerRouteShare>.from(_staged)) {
        await PartnerService.deleteRouteShare(s);
      }
      await _clearAllSkippedPdfsQuiet();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              stagedN > 0 && manualN > 0
                  ? 'Køen er tømt ($stagedN ruter + $manualN manuelle PDF-er).'
                  : stagedN > 0
                      ? 'Alle $stagedN ruter er fjernet fra køen.'
                      : 'Alle $manualN manuelle PDF-er er fjernet.',
            ),
          ),
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
        title: 'Rute ${MaviUnitCodes.compactLabel(row.vehicle.unitCode)} — $fileLabel',
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Flyttet til ${MaviUnitCodes.fleetDriverLabel(row.vehicle.unitCode, row.partner.name)}',
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

  Future<bool> _guardPublishPrerequisites() async {
    if (_allDuplicateExtraCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Duplikat-ruter i køen'),
          content: Text(
            '${_duplicateRouteIds.length} ruter er dobbelt/trippel '
            '($_allDuplicateExtraCount ekstra kopier).\n\n'
            'Etter «Behold én av hver» blir det ${_stagedCountAfterDedup} ruter igjen. '
            'Rydd duplikater før publisering.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fjern duplikater nå'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _removeDuplicateRoutes();
      }
      if (_allDuplicateExtraCount > 0) return false;
    }
    if (_isSap && _sapPendingInbox > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_sapPendingInbox SAP-PDF venter fortsatt på import. '
            'Importer og kontroller alle ruter før publisering.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 6),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _publish({required bool notifyDriver}) async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg ruter du vil publisere etter kontroll.')),
      );
      return;
    }
    if (!await _guardPublishPrerequisites()) return;
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
      _setTabIndex(_kTabMissingShift);
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
        _MassTab.skipped => _kTabManual,
        _MassTab.duplicates => _kTabDuplicates,
        _MassTab.drivers => _kTabMultiLoad,
        _MassTab.missingShift => _kTabMissingShift,
        _MassTab.allRoutes => _kTabRoutes,
      };

  int get _currentWorkflowStepNumber => switch (_sheetTab) {
        _MassTab.skipped => 1,
        _MassTab.duplicates => 2,
        _MassTab.drivers => 3,
        _MassTab.missingShift => 4,
        _MassTab.allRoutes => 5,
      };

  void _setTabIndex(int i) {
    setState(() {
      _sheetTab = switch (i) {
        _kTabManual => _MassTab.skipped,
        _kTabDuplicates => _MassTab.duplicates,
        _kTabMultiLoad => _MassTab.drivers,
        _kTabMissingShift => _MassTab.missingShift,
        _kTabRoutes => _MassTab.allRoutes,
        _ => _MassTab.allRoutes,
      };
      if (_sheetTab == _MassTab.allRoutes) {
        _queueFilter = _RouteQueueFilter.all;
      } else if (_sheetTab == _MassTab.missingShift) {
        _queueFilter = _RouteQueueFilter.missingShift;
      }
    });
  }

  void _goToNextWorkflowStep() {
    if (_skipped.isNotEmpty) {
      _setTabIndex(_kTabManual);
      return;
    }
    if (_duplicateExtraCount > 0) {
      _setTabIndex(_kTabDuplicates);
      return;
    }
    if (_multiLoadDriverCount > 0) {
      _setTabIndex(_kTabMultiLoad);
      return;
    }
    if (_missingShiftCount > 0) {
      _setTabIndex(_kTabMissingShift);
      return;
    }
    _setTabIndex(_kTabRoutes);
  }

  Widget _buildWorkflowStepBanner(_MassUi ui) {
    const steps = ['Manuell', 'Duplikater', '2+ last', 'Skift', 'Del ruter'];
    final current = _currentWorkflowStepNumber;
  final issues = <String>[
      if (_skipped.isNotEmpty) '${_skipped.length} manuell',
      if (_duplicateExtraCount > 0) '$_duplicateExtraCount duplikat',
      if (_multiLoadDriverCount > 0) '$_multiLoadDriverCount med 2+ last',
      if (_missingShiftCount > 0) '$_missingShiftCount mangler skift',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ui.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Steg $current av 5',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: ui.accentDark),
              ),
              const Spacer(),
              if (current < 5)
                TextButton(
                  onPressed: _goToNextWorkflowStep,
                  child: const Text('Neste steg'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: List.generate(steps.length, (i) {
              final n = i + 1;
              final active = n == current;
              final done = n < current;
              return ActionChip(
                label: Text(
                  '${n}. ${steps[i]}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active ? ui.accentDark : done ? Colors.green.shade800 : Colors.grey.shade700,
                  ),
                ),
                backgroundColor: active
                    ? ui.surfaceTint
                    : done
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                side: BorderSide(
                  color: active ? ui.accentDark : Colors.grey.shade300,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () => _setTabIndex(i),
              );
            }),
          ),
          if (issues.isNotEmpty && current < 5) ...[
            const SizedBox(height: 6),
            Text(
              'Gjenstår: ${issues.join(' · ')}',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
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
          onTap: () => _setTabIndex(_kTabMissingShift),
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
    if (_queueTotalCount > 0) {
      chips.add(
        TextButton.icon(
          onPressed: _busyUpload ? null : _clearAllStaged,
          icon: Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.grey.shade700),
          label: Text(
            'Tøm kø ($_queueTotalCount)',
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
              _setTabIndex(_kTabMultiLoad);
            },
            child: const Text('Se flere last/rute'),
          ),
        ],
      ),
    );
  }

  Widget _multiLoadDetailTile(MapEntry<String, List<PartnerRouteShare>> entry) {
    final row = _rowForVehicleId(entry.key);
    final mavi = row != null ? MaviUnitCodes.compactLabel(row.vehicle.unitCode) : '?';
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
      return const DriftProLoadingCenter();
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
      topBanner: DriftProClient.isMobile ? null : _buildWorkflowStepBanner(ui),
      showTabCaption: !DriftProClient.isMobile,
      tabLabels: const ['Manuell', 'Duplikater', 'Flere last/rute', 'Mangler skift', 'Ruter'],
      tabBadges: [
        _skipped.isNotEmpty ? _skipped.length : null,
        _duplicatesTabCount > 0 ? _duplicatesTabCount : null,
        _multiLoadDriverCount > 0 ? _multiLoadDriverCount : null,
        missingShift > 0 ? missingShift : null,
        _staged.isNotEmpty ? _staged.length : null,
      ],
      tabBadgeColors: [
        Colors.orange.shade800,
        Colors.deepPurple.shade800,
        _multiLoadDriverCount > 0 ? Colors.orange.shade900 : ui.accentDark,
        Colors.red.shade700,
        ui.accentDark,
      ],
      selectedTabIndex: _tabIndex,
      onTabSelected: _setTabIndex,
      tabCaption: _tabHint(),
      tabBody: _buildTabContent(ui),
      footer: _buildPublishBar(ui),
    );
  }

  Widget _buildSidebar(_MassUi ui) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPendingInboxBanner(ui),
          _buildActionsRow(ui),
        ],
      );

  Widget _buildWorkflowGuideContent(_MassUi ui) {
    return Material(
      color: ui.surfaceTint,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: ui.steps.asMap().entries.map((e) => _workflowStepRow(e.key + 1, e.value, ui)).toList(),
        ),
      ),
    );
  }

  Widget _workflowStepRow(int n, String text, _MassUi ui) {
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

  Future<void> _pickDefaultRouteDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _routeDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _routeDate = DateTime(d.year, d.month, d.day));
  }

  Widget _buildMultiDatePanel(_MassUi ui) {
    final dateLabel = DateFormat('d. MMM yyyy', 'nb').format(_routeDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busyUpload || _publishing ? null : _pickDefaultRouteDate,
          icon: const Icon(Icons.event_outlined, size: 20),
          label: Text(
            _staged.isEmpty
                ? 'Standarddato nye PDF: $dateLabel'
                : 'Standarddato: $dateLabel',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (_queueTotalCount > 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _busyUpload || _publishing ? null : _clearAllStaged,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: Text('Tøm kø ($_queueTotalCount)'),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                ),
              ),
              const SizedBox(width: 8),
              if (_staged.isNotEmpty) Expanded(child: _buildDateQueueMenu(_stagedByDate)),
            ],
          ),
          if (_staged.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_staged.length} ruter i kø${_filterDay != null ? ' · filtrert' : ''}'
              '${_skipped.isNotEmpty ? ' · ${_skipped.length} manuelle' : ''}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ui.accentDark),
            ),
          ] else if (_skipped.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_skipped.length} manuelle PDF-er i kø',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ui.accentDark),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPendingInboxBanner(_MassUi ui) {
    if (!_isSap || _sapPendingInbox <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inbox_outlined, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_sapPendingInbox PDF fra SAP venter',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Ingenting fordeles automatisk. Trykk «Importer» nedenfor, '
                'kontroller alle ruter i køen, og publiser først når alt stemmer.',
                style: TextStyle(fontSize: 12, height: 1.35, color: Colors.orange.shade900),
              ),
              if (_pendingInboxItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._pendingInboxItems.take(6).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• ${item.fileName}'
                      '${item.detectedMaviCode != null ? ' (${MaviUnitCodes.compactLabel(item.detectedMaviCode!)})' : ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_pendingInboxItems.length > 6)
                  Text(
                    '… og ${_pendingInboxItems.length - 6} til',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ],
          ),
        ),
      ),
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
                  ? SizedBox(width: 20, height: 20, child: DriftProLoadingIndicator(size: 20))
                  : const Icon(Icons.cloud_download_outlined))
              : (_busyUpload
                  ? SizedBox(width: 20, height: 20, child: DriftProLoadingIndicator(size: 20))
                  : const Icon(Icons.upload_file)),
          label: Text(
            _isSap
                ? (_sapPendingInbox > 0
                    ? 'Importer $_sapPendingInbox SAP-PDF til kø'
                    : _staged.isEmpty
                        ? 'Ingen nye SAP-PDF'
                        : 'Oppdater kø')
                : 'Last opp PDF-er',
          ),
        ),
        if (_staged.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _fillingShifts ? null : _fillAllShiftsForStaged,
            icon: _fillingShifts
                ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                : const Icon(Icons.auto_fix_high_outlined),
            label: Text(_fillingShifts ? 'Fyller skift…' : 'Fyll skift fra PDF (alle)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busyUpload || _publishing ? null : _selectReadyNonDuplicates,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text('Velg alle klare (${_readyShiftCount})'),
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
            text: '$_multiLoadDriverCount bil(er) med 2+ last/rute — trykk for liste',
            onTap: _showMultiLoadDetails,
          ),
        if (_orphanShares.isNotEmpty && _sheetTab == _MassTab.allRoutes)
          _buildCompactAlert(
            icon: Icons.link_off_outlined,
            color: Colors.blue.shade800,
            text: '${_orphanShares.length} rute(r) uten sjåfør — koble fra MAVI i filnavn',
            onTap: _relinkAllOrphanShares,
          ),
        if (_skipped.isNotEmpty && _sheetTab != _MassTab.skipped)
          _buildCompactAlert(
            icon: Icons.pan_tool_alt_outlined,
            color: Colors.orange.shade900,
            text: '${_skipped.length} PDF krever manuell tildeling',
            onTap: () => _setTabIndex(_kTabManual),
          ),
        if (_missingShiftCount > 0 && _sheetTab != _MassTab.missingShift)
          _buildCompactAlert(
            icon: Icons.warning_amber_rounded,
            color: Colors.red.shade800,
            text: '$_missingShiftCount rute(r) mangler skift',
            onTap: () => _setTabIndex(_kTabMissingShift),
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
        if (showFilters && !forceMissingOnly) _buildDuplicateBanner(ui),
        if (showFilters && !forceMissingOnly) _buildPendingInboxBanner(ui),
        if (showFilters && !forceMissingOnly)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: _buildQueueFilterBar(),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              TextButton(
                onPressed: _selectReadyNonDuplicates,
                child: const Text('Velg klare'),
              ),
              TextButton(
                onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))),
                child: const Text('Velg alle'),
              ),
              TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Fjern valg')),
              const Spacer(),
              Text(
                '${_filteredQueueRoutes.length}/${_staged.length} · zoom header',
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
      _MassTab.skipped =>
        'Steg 1: Tildel sjåfør og skift på PDF-er som ikke ble auto-fordelt. Trykk OK når valgt.',
      _MassTab.duplicates =>
        'Steg 2: Kun identisk PDF er duplikat. Rydd bort ekstra kopier før du deler ruter.',
      _MassTab.drivers =>
        _multiLoadDriverCount > 0
            ? 'Steg 3: $_multiLoadDriverCount bil(er) med 2+ last — sjekk at fordelingen er rettferdig.'
            : 'Steg 3: Ingen biler med flere last akkurat nå.',
      _MassTab.missingShift =>
        'Steg 4: Velg skift på ruter uten skiftplan før publisering.',
      _MassTab.allRoutes =>
        'Steg 5: Velg ruter og del med SMS + e-post eller uten varsel.',
    };
  }

  Widget _buildTabContent(_MassUi ui) {
    return switch (_sheetTab) {
      _MassTab.skipped => _buildSkippedList(ui),
      _MassTab.duplicates => _buildDuplicatesTab(ui),
      _MassTab.drivers => _buildDriverCentricList(ui),
      _MassTab.missingShift => _buildRoutesOverview(ui, forceMissingOnly: true),
      _MassTab.allRoutes => _buildRoutesOverview(ui),
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

  Widget _routeCardsSliver({
    required List<PartnerRouteShare> routes,
    required Widget Function(PartnerRouteShare share) itemBuilder,
    EdgeInsets padding = const EdgeInsets.fromLTRB(12, 4, 12, 24),
  }) {
    if (DriftProClient.isMobile) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: itemBuilder(routes[i]),
            ),
            childCount: routes.length,
          ),
        ),
      );
    }
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: _routeCardGridDelegate,
        delegate: SliverChildBuilderDelegate(
          (context, i) => itemBuilder(routes[i]),
          childCount: routes.length,
        ),
      ),
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
          _routeCardsSliver(
            routes: routes,
            itemBuilder: (share) {
              final row = _rowForShare(share);
              if (row == null) return _buildOrphanRouteCard(share, ui);
              return _buildMassRouteCard(share, row, ui);
            },
          ),
      ],
    );
  }

  Future<void> _showRouteEditSheet(
    PartnerRouteShare share,
    FleetPartnerVehicleRow row,
    _MassUi ui,
  ) async {
    final noteCtrl = _noteByShare.putIfAbsent(
      share.id,
      () => TextEditingController(text: share.notes ?? ''),
    );
    final shiftId = _effectiveShiftId(share.id);
    final start = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: PartnerMassRouteQueueCard.buildDetailsForm(
            context: ctx,
            share: share,
            row: row,
            accentDark: ui.accentDark,
            shiftMissing: shiftId == null,
            checked: _selected.contains(share.id),
            busy: _busyUpload || _publishing,
            shiftId: shiftId,
            shiftLabel: _shiftLabel(shiftId),
            lane: _stowingForShare(share),
            routeDay: _routeDayFor(share.id),
            startTime: start,
            routeShifts: _routeShifts,
            maviFleet: _maviFleet,
            noteController: noteCtrl,
            onReassignVehicle: (vid) => _reassignShare(share, vid),
            onDateChanged: (d) => _setShareRouteDay(share, d),
            onShiftChanged: (v) async {
              setState(() => _shiftByShare[share.id] = v);
              await PartnerService.updateRouteShareFields(share.id, {'shift_id': v});
            },
            onStartChanged: (t) => setState(() => _startByShare[share.id] = t),
            onRemove: () {
              Navigator.pop(ctx);
              _removeShare(share);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMassRouteCard(
    PartnerRouteShare share,
    FleetPartnerVehicleRow row,
    _MassUi ui,
  ) {
    final noteCtrl = _noteByShare.putIfAbsent(
      share.id,
      () => TextEditingController(text: share.notes ?? ''),
    );
    final shiftId = _effectiveShiftId(share.id);
    final start = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);

    return PartnerMassRouteQueueCard(
      share: share,
      row: row,
      accent: ui.accent,
      accentDark: ui.accentDark,
      checked: _selected.contains(share.id),
      shiftMissing: shiftId == null,
      busy: _busyUpload || _publishing,
      shiftId: shiftId,
      shiftLabel: _shiftLabel(shiftId),
      lane: _stowingForShare(share),
      routeDay: _routeDayFor(share.id),
      startTime: start,
      routeShifts: _routeShifts,
      maviFleet: _maviFleet,
      noteController: noteCtrl,
      onOpenDetails: () => _showRouteEditSheet(share, row, ui),
      onChecked: (v) => setState(() {
        if (v == true) {
          _selected.add(share.id);
        } else {
          _selected.remove(share.id);
        }
      }),
      onRemove: () => _removeShare(share),
      onReassignVehicle: (vid) => _reassignShare(share, vid),
      onDateChanged: (d) => _setShareRouteDay(share, d),
      onShiftChanged: (v) async {
        setState(() => _shiftByShare[share.id] = v);
        await PartnerService.updateRouteShareFields(share.id, {'shift_id': v});
      },
      onStartChanged: (t) => setState(() => _startByShare[share.id] = t),
    );
  }

  Widget _buildOrphanRouteCard(PartnerRouteShare share, _MassUi ui) {
    final code = _maviCodeForShare(share);
    final row = _fleetRowForMaviCode(code);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade400, width: 2),
        boxShadow: DriftProTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PartnerRoutePdfThumbnail(
            share: share,
            driverLabel: 'Ingen sjåfør',
            height: 170,
            showFullPage: true,
            zoomTripHeader: true,
            onTapOpen: () => PartnerRoutePdfActions.openPdf(context, share),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  share.title ?? share.pdfStoragePath.split('/').last,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  code != null && row == null
                      ? '${MaviUnitCodes.compactLabel(code)} finnes ikke som aktiv MAVI i flåten — '
                          'registrer bilen under Samarbeidspartner først.'
                      : code != null
                          ? 'Foreslått MAVI: ${MaviUnitCodes.compactLabel(code)}'
                          : 'Ingen sjåfør koblet — velg bil i Duplikater- eller Manuell-fanen.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                ),
                const SizedBox(height: 8),
                if (row != null)
                  FilledButton.tonal(
                    onPressed: _busyUpload ? null : () => _relinkOrphanShare(share),
                    child: Text('Koble til ${MaviUnitCodes.fleetDriverLabel(row.vehicle.unitCode, row.partner.name)}'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _setTabIndex(_kTabManual),
                    icon: const Icon(Icons.pan_tool_alt_outlined, size: 18),
                    label: const Text('Gå til manuell tildeling'),
                  ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => _setTabIndex(_kTabDuplicates),
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('Se i Duplikater'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishBar(_MassUi ui) {
    final selectedMissing =
        _selected.where((id) => _effectiveShiftId(id) == null).length;
    final canPublish = _staged.isNotEmpty &&
        _selected.isNotEmpty &&
        selectedMissing == 0 &&
        _skipped.isEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final statusText = _staged.isEmpty
            ? 'Steg 5: Ingen ruter i kø ennå'
            : _skipped.isNotEmpty
                ? 'Fullfør steg 1 (manuell) før du deler ruter'
                : selectedMissing > 0
                    ? 'Steg 4: $selectedMissing valgte rute(r) mangler skift'
                    : canPublish
                        ? 'Steg 5: Klar — ${_selected.length} rute(r) valgt for utsending'
                        : 'Steg 5: Huk av ruter du vil dele';

        final status = Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _skipped.isNotEmpty
                ? Colors.orange.shade900
                : selectedMissing > 0
                    ? Colors.red.shade800
                    : canPublish
                        ? Colors.green.shade800
                        : Colors.grey.shade800,
          ),
        );

        final btnGrey = FilledButton.icon(
          onPressed: _publishing || !canPublish ? null : () => _publish(notifyDriver: false),
          icon: _publishing
              ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
              : const Icon(Icons.notifications_off_outlined, size: 20),
          label: Text('Uten varsel (${_selected.length})'),
          style: FilledButton.styleFrom(
            backgroundColor: RouteDispatchStatus.cellColor(RouteDispatchStatus.registered),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
        );

        final btnSms = FilledButton.icon(
          onPressed: _publishing || !canPublish ? null : () => _publish(notifyDriver: true),
          icon: _publishing
              ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
              : const Icon(Icons.sms_outlined, size: 20),
          label: Text('SMS + e-post (${_selected.length})'),
          style: FilledButton.styleFrom(
            backgroundColor: ui.accentDark,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
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

    final rows = _maviFleet.where((r) {
      final count = _visibleStaged.where((s) => s.partnerVehicleId == r.vehicle.id).length;
      if (_showAllDrivers) return count > 0;
      return count >= 2;
    }).toList();
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
                  _showAllDrivers
                      ? 'Viser alle $_driversWithRoutesCount biler med rute'
                      : 'Kun biler med 2+ last/rute ($_multiLoadDriverCount)',
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
                _showAllDrivers
                    ? 'Ingen biler med rute i kø.'
                    : 'Ingen biler med 2+ last/rute — bra!',
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
    final mavi = MaviUnitCodes.compactLabel(row.vehicle.unitCode);
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
              : [
                  DriftProClient.isMobile
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          child: Column(
                            children: [
                              for (final route in routes)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildMassRouteCard(route, row, ui),
                                ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: _routeCardGridDelegate,
                            itemCount: routes.length,
                            itemBuilder: (_, i) =>
                                _buildMassRouteCard(routes[i], row, ui),
                          ),
                        ),
                ],
        ),
      ),
    );
  }

  String? _skippedDriverLabel(_SkippedPdf item) {
    if (item.selectedVehicleId == null) {
      return item.detectedCode != null
          ? 'Detektert ${MaviUnitCodes.compactLabel(item.detectedCode!)}'
          : 'Velg sjåfør';
    }
    return _maviFleet
        .where((r) => r.vehicle.id == item.selectedVehicleId)
        .map((r) => MaviUnitCodes.fleetDriverLabel(r.vehicle.unitCode, r.partner.name))
        .firstOrNull;
  }

  String _shortFileLabel(String name) {
    final parts = name.split('_');
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('_');
    }
    return name.length > 28 ? '${name.substring(0, 25)}…' : name;
  }

  Future<void> _showSkippedAssignSheet(_SkippedPdf item, _MassUi ui) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final driverChosen = item.selectedVehicleId != null;
            final shiftChosen = item.shiftId != null && item.shiftId!.isNotEmpty;
            final canOk = driverChosen && shiftChosen && !_busyUpload;
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (item.reason != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.reason!,
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ],
                    const SizedBox(height: 12),
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
                                MaviUnitCodes.fleetDriverLabel(r.vehicle.unitCode, r.partner.name),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setSheetState(() => item.selectedVehicleId = v);
                        setState(() => item.selectedVehicleId = v);
                      },
                    ),
                    if (driverChosen) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _skippedDriverLabel(item) ?? 'Sjåfør valgt',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                      onChanged: (v) {
                        setSheetState(() => item.shiftId = v);
                        setState(() => item.shiftId = v);
                      },
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
                        final picked =
                            await showTimePicker(context: ctx, initialTime: item.startTime);
                        if (picked != null) {
                          setSheetState(() => item.startTime = picked);
                          setState(() => item.startTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Avbryt'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: canOk
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _assignSkipped(item);
                                }
                              : null,
                          icon: const Icon(Icons.check, size: 20),
                          style: FilledButton.styleFrom(backgroundColor: ui.accentDark),
                          label: const Text('OK — legg i kø'),
                        ),
                      ],
                    ),
                    if (driverChosen && !shiftChosen)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Velg også skiftplan for å aktivere OK.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _shortSkipReason(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('duplikat')) return 'Allerede i kø — ikke importert på nytt';
    if (lower.contains('lagring feilet')) return 'Lagring feilet — tildel manuelt';
    if (lower.contains('ingen bil matcher')) return 'MAVI ikke i flåten';
    if (lower.contains('fant ikke mavi')) return 'Fant ikke MAVI i PDF';
    return reason.length > 72 ? '${reason.substring(0, 69)}…' : reason;
  }

  Widget _buildSkippedCompactCard(_SkippedPdf item, _MassUi ui, {bool showDelete = false}) {
    final label = _skippedDriverLabel(item);
    final shortName = _shortFileLabel(item.fileName);
    final storageError = item.reason?.contains('Lagring feilet') == true;

    return Material(
      color: ui.surfaceTint,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showSkippedAssignSheet(item, ui),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PartnerRoutePdfThumbnail(
                bytes: item.bytes,
                driverLabel: label,
                height: 170,
                showFullPage: true,
                zoomTripHeader: true,
                onTapOpen: item.bytes.isEmpty
                    ? null
                    : () => PartnerRoutePdfActions.openPdfBytes(
                          context,
                          bytes: item.bytes,
                          title: item.fileName,
                        ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    if (item.detectedCode != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        MaviUnitCodes.compactLabel(item.detectedCode!),
                        style: TextStyle(fontSize: 11, color: ui.accentDark, fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (item.reason != null && !storageError) ...[
                      const SizedBox(height: 4),
                      Text(
                        _shortSkipReason(item.reason!),
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade900, height: 1.25),
                      ),
                    ],
                    if (storageError) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Lagring feilet — trykk for å tildele manuelt',
                        style: TextStyle(fontSize: 10, color: Colors.orange.shade900),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.touch_app_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Trykk for tildeling',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ),
                        if (showDelete)
                          IconButton(
                            tooltip: 'Fjern manuell PDF',
                            onPressed: _busyUpload ? null : () => _dismissSkippedPdf(item),
                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade700),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                      ],
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

  Widget _buildDuplicatesTab(_MassUi ui) {
    final contentDupes = _duplicateGroups;

    if (contentDupes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Ingen duplikater akkurat nå.\n\n'
            'Flere ulike ruter for samme bil samme dag er ikke duplikat — '
            'kun 100 % identisk PDF-innhold flagges her.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.45),
          ),
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildDuplicateSectionHeader(
            title: 'Identisk PDF (${contentDupes.length} gruppe(r))',
            subtitle:
                '100 % samme innhold — ved 2+ kopier beholdes kun én. Ulike freight order / kunder er separate ruter.',
            action: FilledButton.icon(
              onPressed: _busyUpload || _publishing ? null : _deduplicateAllKeepOneEach,
              icon: const Icon(Icons.filter_1_outlined, size: 18),
              label: Text('Behold én av hver (${_allDuplicateExtraCount} slettes)'),
            ),
          ),
        ),
        for (final group in contentDupes)
          ..._duplicateGroupSlivers(group, ui),
      ],
    );
  }

  Widget _buildDuplicateSectionHeader({
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35)),
          if (action != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ],
      ),
    );
  }

  List<Widget> _duplicateGroupSlivers(
    StagedRouteDuplicateGroup group,
    _MassUi ui,
  ) {
    final shares = group.shares;
    final label = group.countLabel;
    final mavi = _maviCodeForShare(shares.first);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$label · ${mavi != null ? MaviUnitCodes.compactLabel(mavi) : 'Ukjent MAVI'} · ${shares.length} ruter',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.deepPurple.shade900),
                ),
              ),
              FilledButton.tonal(
                onPressed: _busyUpload ? null : () => _removeDuplicateGroupShares(shares),
                child: const Text('Behold én her'),
              ),
            ],
          ),
        ),
      ),
      _routeCardsSliver(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        routes: shares,
        itemBuilder: (share) => _buildDuplicateShareCard(
          share,
          ui,
          isKeeper: share.id == StagedRouteDuplicateHelper.pickKeeper(shares).id,
        ),
      ),
    ];
  }

  Widget _buildDuplicateShareCard(
    PartnerRouteShare share,
    _MassUi ui, {
    bool isOrphan = false,
    bool isKeeper = false,
  }) {
    final code = _maviCodeForShare(share);
    final row = _rowForShare(share) ?? _fleetRowForMaviCode(code);
    final driverLabel = row != null
        ? MaviUnitCodes.fleetDriverLabel(row.vehicle.unitCode, row.partner.name)
        : 'Ingen sjåfør';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isKeeper ? Colors.green.shade400 : Colors.deepPurple.shade200,
          width: isKeeper ? 2 : 1,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PartnerRoutePdfThumbnail(
            share: share,
            driverLabel: driverLabel,
            height: 170,
            showFullPage: true,
            zoomTripHeader: true,
            onTapOpen: () => PartnerRoutePdfActions.openPdf(context, share),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isKeeper)
                  Text(
                    'Beholdes',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.green.shade800),
                  ),
                Text(
                  share.title ?? share.pdfStoragePath.split('/').last,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (isOrphan && row != null)
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _busyUpload ? null : () => _relinkOrphanShare(share),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('Koble', style: TextStyle(fontSize: 11)),
                        ),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      tooltip: 'Fjern fra kø',
                      onPressed: _busyUpload ? null : () => _removeShare(share),
                      icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade700),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                routeManualAttentionBanner(
                  count: _skipped.length,
                  onOpenManual: () {},
                ),
                const SizedBox(height: 8),
                Text(
                  'Steg 1: Velg sjåfør og skift på hvert kort, trykk OK — ruten legges i køen.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                ),
              ],
            ),
          ),
        ),
        if (DriftProClient.isMobile)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildSkippedCompactCard(_skipped[i], ui, showDelete: true),
                ),
                childCount: _skipped.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildSkippedCompactCard(_skipped[i], ui, showDelete: true),
                childCount: _skipped.length,
              ),
            ),
          ),
      ],
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
        tagline: 'Importer manuelt, kontroller sjåfører og PDF-er, publiser når alt stemmer',
        icon: Icons.mark_email_read_outlined,
        steps: [
          'Importer/lag opp PDF-er — systemet fordeler automatisk der MAVI finnes.',
          'Manuell: velg sjåfør + skift, trykk OK.',
          'Duplikater: behold én per identisk PDF.',
          'Sjekk 2+ last og manglende skift.',
          'Velg ruter og del med SMS + e-post eller uten varsel.',
        ],
        emptyHint:
            'Ingen SAP-ruter i kø.\n\n'
            'Når e-post kommer til ${SapRoutesConfig.inboundAddress}, vises ventende PDF-er her. '
            'Trykk «Importer» for å legge dem i kø — ingenting sendes til sjåfør før du publiserer.',
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
        'Last opp PDF-er — MAVI leses automatisk fra filen.',
        'Manuell: velg sjåfør + skift, trykk OK.',
        'Duplikater: behold én per identisk PDF.',
        'Sjekk 2+ last og manglende skift.',
        'Velg ruter og del med SMS + e-post eller uten varsel.',
      ],
      emptyHint:
          'Ingen ruter i kø.\n\nLast opp PDF-er med knappen over. '
          'MAVI hentes fra Trip Overview / Resource ID inne i filen.',
    );
  }
}
