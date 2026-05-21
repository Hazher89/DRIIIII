import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';
import '../../../core/constants/sap_routes_config.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/partner/sap_route_import_service.dart';
import '../../../core/services/partner/sap_route_inbox_live.dart';
import '../../../core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/sap_route_inbox.dart';
import 'partner_route_pdf_actions.dart';

class _PdfAssignmentRow {
  final String fileName;
  final String status; // ok | skipped
  final String? maviCode;
  final String? stowingLane;
  final String? driverLabel;
  final String? reason;

  const _PdfAssignmentRow({
    required this.fileName,
    required this.status,
    this.maviCode,
    this.stowingLane,
    this.driverLabel,
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

enum _MassTab { drivers, overview, skipped }

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
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.94;
        return SizedBox(
          height: h,
          child: PartnerRouteMassDispatchSheet(
            fleet: fleet,
            initialRouteDate: routeDate ?? DateTime.now(),
            source: source,
          ),
        );
      },
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
  _MassTab _sheetTab = _MassTab.drivers;
  bool _sapSyncing = false;
  int _sapPendingInbox = 0;
  RealtimeChannel? _sapLiveChannel;
  bool _showAllDrivers = false;
  bool _guideExpanded = true;

  bool get _isSap => widget.source == PartnerRouteMassSource.sap;

  _MassUi get _ui => _MassUi.of(widget.source);

  int get _driversWithRoutesCount => _routesByVehicle.length;

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
        _syncSapInbox();
      }
    });
  }

  Future<void> _bindSapLive() async {
    final cid = await SupabaseService.getCurrentCompanyId();
    if (!mounted || cid == null) return;
    SapRouteInboxLive.unsubscribe(_sapLiveChannel);
    _sapLiveChannel = SapRouteInboxLive.subscribe(
      companyId: cid,
      onChanged: () => _syncSapInbox(),
    );
  }

  Future<void> _syncSapInbox() async {
    if (!_isSap || _sapSyncing) return;
    setState(() => _sapSyncing = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      final pending = await PartnerService.fetchSapRouteInboxPending(cid);
      if (!mounted) return;
      setState(() => _sapPendingInbox = pending.length);
      if (pending.isEmpty) return;

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
                '${result.skipped > 0 ? " · ${result.skipped} trenger manuell tildeling" : ""}.',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
      await _reload();
      if (mounted) {
        final n = await PartnerService.countSapRouteInboxPending(cid);
        setState(() => _sapPendingInbox = n);
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

  List<FleetPartnerVehicleRow> get _maviFleet =>
      PartnerService.filterMaviFleetOnly(widget.fleet);

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final staged = await PartnerService.fetchStagedRouteShares(cid);
      final portals = <String, PartnerPortalAccount>{};
      final partnerIds = _maviFleet.map((r) => r.partner.id).toSet();
      for (final pid in partnerIds) {
        for (final a in await PartnerService.fetchPortalAccounts(pid)) {
          if (a.partnerVehicleId != null) portals[a.partnerVehicleId!] = a;
        }
      }
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _staged = staged;
        _portalByVehicle = portals;
        _selected
          ..clear()
          ..addAll(staged.map((s) => s.id));
        _stowingByShare.clear();
        for (final s in staged) {
          _shiftByShare.putIfAbsent(s.id, () => _guessShift(s, shifts));
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
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _guessShift(PartnerRouteShare share, List<FleetShiftDefinition> shifts) {
    if (shifts.isEmpty) return '';
    final title = (share.title ?? '').toLowerCase();
    for (final s in shifts) {
      if (title.contains(s.name.toLowerCase())) return s.id;
    }
    final routeOps = shifts.where((s) => s.shiftKind == 'route_ops').toList();
    return routeOps.isNotEmpty ? routeOps.first.id : shifts.first.id;
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

  Map<String, List<PartnerRouteShare>> get _routesByVehicle {
    final map = <String, List<PartnerRouteShare>>{};
    for (final s in _staged) {
      final vid = s.partnerVehicleId;
      if (vid == null) continue;
      map.putIfAbsent(vid, () => []).add(s);
    }
    return map;
  }

  int get _multiLoadDriverCount =>
      _routesByVehicle.values.where((list) => list.length >= 2).length;

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

  Future<String> _createStagedShare({
    required String companyId,
    required Partner partner,
    required PartnerVehicle vehicle,
    required String fileName,
    required Uint8List bytes,
    String? notes,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'company_$companyId/partner_routes/${DateTime.now().millisecondsSinceEpoch}_${vehicle.unitCode}_$safeName';
    final storedPath =
        await PartnerService.uploadPartnerRoutePdf(storagePath: path, bytes: bytes);
    final pdfText = RoutePdfTextService.extractFullText(bytes);
    final meta = RoutePdfTextService.extractTripOverviewMetaFromText(pdfText);
    final schedule = RoutePdfTextService.resolveSchedule(pdfText, fallbackDate: _routeDate);
    final composedNotes = RoutePdfTextService.composeRouteNotes(
      stowingLane: meta.stowingLane,
      userNote: notes,
    );
    final share = await PartnerService.addRouteShare(
      PartnerRouteShare(
        id: '',
        partnerId: partner.id,
        companyId: companyId,
        title: 'Rute ${MaviUnitCodes.normalize(vehicle.unitCode)} — $fileName',
        pdfStoragePath: storedPath,
        shareDate: schedule.routeDate,
        isDailyShare: true,
        createdAt: DateTime.now(),
        dispatchStatus: 'staged',
        pdfSearchText: pdfText.isEmpty ? null : pdfText,
        partnerVehicleId: vehicle.id,
        notes: composedNotes.isEmpty ? null : composedNotes,
      ),
    );
    if (meta.stowingLane != null) {
      _stowingByShare[share.id] = meta.stowingLane!;
    }
    if (pdfText.isNotEmpty) {
      await PartnerService.saveRoutePdfSearchText(share.id, pdfText);
    }
    final patch = <String, dynamic>{};
    if (schedule.routeStartAt != null) {
      patch['route_start_at'] = schedule.routeStartAt!.toUtc().toIso8601String();
    }
    if (notes != null && notes.trim().isNotEmpty) patch['notes'] = notes.trim();
    if (patch.isNotEmpty) {
      await PartnerService.updateRouteShareFields(share.id, patch);
    }
    if (schedule.routeStartAt != null) {
      _startByShare[share.id] = TimeOfDay(
        hour: schedule.routeStartAt!.hour,
        minute: schedule.routeStartAt!.minute,
      );
    }
    return share.id;
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

      int ok = 0;
      final newSkipped = <_SkippedPdf>[];
      final log = <_PdfAssignmentRow>[];

      for (final file in files) {
        final bytes = await _readPlatformFile(file);
        if (bytes == null || bytes.isEmpty) {
          log.add(_PdfAssignmentRow(
            fileName: file.name,
            status: 'skipped',
            reason: 'Kunne ikke lese fil',
          ));
          newSkipped.add(_SkippedPdf(
            fileName: file.name,
            bytes: Uint8List(0),
            reason: 'Kunne ikke lese fil',
          ));
          continue;
        }
        final meta = RoutePdfTextService.extractTripOverviewMeta(bytes);
        final code = meta.maviCode ?? RoutePdfTextService.extractResourceIdFromBytes(bytes);
        if (code == null) {
          log.add(_PdfAssignmentRow(
            fileName: file.name,
            status: 'skipped',
            reason: 'Fant ikke MAVI-nummer inne i PDF (sjekk Trip Overview / Resource ID)',
          ));
          newSkipped.add(_SkippedPdf(
            fileName: file.name,
            bytes: bytes,
            reason: 'Fant ikke MAVI-nummer inne i PDF (sjekk Trip Overview / Resource ID)',
          ));
          continue;
        }
        final vehicle = RoutePdfTextService.findVehicleInLookup(vehicleMap, code);
        if (vehicle == null) {
          log.add(_PdfAssignmentRow(
            fileName: file.name,
            status: 'skipped',
            maviCode: code,
            reason: 'Ingen bil matcher $code i flåten',
          ));
          newSkipped.add(_SkippedPdf(
            fileName: file.name,
            bytes: bytes,
            reason: 'Ingen bil matcher $code',
            detectedCode: code,
          ));
          continue;
        }
        final partner = partnerById[vehicle.partnerId];
        if (partner == null) {
          log.add(_PdfAssignmentRow(
            fileName: file.name,
            status: 'skipped',
            maviCode: code,
            reason: 'Partner mangler',
          ));
          newSkipped.add(_SkippedPdf(
            fileName: file.name,
            bytes: bytes,
            reason: 'Partner mangler for $code',
            detectedCode: code,
          ));
          continue;
        }
        final mavi = MaviUnitCodes.normalize(vehicle.unitCode);
        await _createStagedShare(
          companyId: cid,
          partner: partner,
          vehicle: vehicle,
          fileName: file.name,
          bytes: bytes,
        );
        log.add(_PdfAssignmentRow(
          fileName: file.name,
          status: 'ok',
          maviCode: mavi,
          stowingLane: meta.stowingLane,
          driverLabel: partner.name,
        ));
        ok++;
      }

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
              '${newSkipped.length} hoppet over — tildel manuelt under «Hoppet over».',
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
      final shareId = await _createStagedShare(
        companyId: cid,
        partner: row.partner,
        vehicle: row.vehicle,
        fileName: item.fileName,
        bytes: item.bytes,
        notes: item.noteCtrl.text,
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
      setState(() => _sheetTab = _MassTab.skipped);
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen ruter valgt for publisering.')),
      );
      return;
    }
    final missingShift = _selected.where((id) => (_shiftByShare[id] ?? '').isEmpty);
    if (missingShift.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle valgte ruter må ha skift.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(notifyDriver ? 'Publiser og varsle?' : 'Publiser uten varsel?'),
        content: Text(
          '${_multiLoadSummaryLine()}\n\n'
          '${notifyDriver ? "Sender ${_selected.length} valgte rute(r) med SMS (${_missingPhoneCount > 0 ? "$_missingPhoneCount uten telefon — får ikke SMS" : "alle med telefon varsles"})." : "Registrerer ${_selected.length} rute(r) i kalender uten SMS — synlig som grå «Uten varsel»."}\n\n'
          'Flere PDF med samme MAVI samme dag = flere last (Stowing Lane 1A, 1B, 17B osv.).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: notifyDriver
                  ? DriftProTheme.primaryGreen
                  : RouteDispatchStatus.cellColor(RouteDispatchStatus.registered),
            ),
            child: Text(notifyDriver ? 'Publiser med SMS' : 'Publiser uten varsel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;
    setState(() => _publishing = true);
    try {
      for (final id in _selected) {
        final note = _noteByShare[id]?.text.trim();
        if (note != null && note.isNotEmpty) {
          await PartnerService.updateRouteShareFields(id, {'notes': note});
        }
      }
      final map = {for (final id in _selected) id: _shiftByShare[id]!};
      final starts = <String, DateTime?>{};
      for (final id in _selected) {
        final t = _startByShare[id];
        if (t != null) {
          starts[id] = DateTime(_routeDate.year, _routeDate.month, _routeDate.day, t.hour, t.minute);
        }
      }
      await PartnerService.dispatchRouteShares(
        companyId: cid,
        shareIdToShiftId: map,
        date: _routeDate,
        shareIdToStartAt: starts,
        notifyDriver: notifyDriver,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              notifyDriver
                  ? 'Publisert ${map.length} rute(r). SMS sendt der telefon finnes.'
                  : 'Registrert ${map.length} rute(r) uten varsel — ingen SMS sendt.',
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (_loading) {
      return const SizedBox(height: 320, child: Center(child: CircularProgressIndicator()));
    }

    final ui = _ui;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: ui.accent, width: 5)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 12 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(ui),
            const SizedBox(height: 10),
            _buildWorkflowGuide(ui),
            const SizedBox(height: 10),
            _buildActionsRow(ui),
            const SizedBox(height: 10),
            _buildMetricsDashboard(ui),
            const SizedBox(height: 8),
            _buildAlertsPanel(ui),
            const SizedBox(height: 10),
            _buildTabSection(ui),
            const SizedBox(height: 8),
            Expanded(child: _buildTabContent(ui)),
            const SizedBox(height: 10),
            _buildPublishBar(ui),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_MassUi ui) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: ui.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(ui.icon, color: ui.accentDark, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(ui.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ui.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ui.accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      ui.badge,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: ui.accentDark),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(ui.tagline, style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowGuide(_MassUi ui) {
    return Material(
      color: ui.surfaceTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _guideExpanded = !_guideExpanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.help_outline, size: 18, color: ui.accentDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Slik fungerer det',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: ui.accentDark),
                    ),
                  ),
                  Icon(_guideExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                ],
              ),
              if (_guideExpanded) ...[
                const SizedBox(height: 10),
                ...ui.steps.asMap().entries.map((e) => _workflowStep(e.key + 1, e.value, ui)),
              ],
            ],
          ),
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

  Widget _buildActionsRow(_MassUi ui) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _routeDate,
                firstDate: DateTime.now().subtract(const Duration(days: 7)),
                lastDate: DateTime.now().add(const Duration(days: 90)),
              );
              if (d != null) setState(() => _routeDate = d);
            },
            icon: const Icon(Icons.event, size: 18),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rutedato', style: TextStyle(fontSize: 10)),
                Text(
                  DateFormat('d. MMM yyyy', 'nb').format(_routeDate),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: _isSap
                ? (_sapSyncing ? null : _syncSapInbox)
                : (_busyUpload ? null : _pickPdfs),
            style: FilledButton.styleFrom(
              backgroundColor: ui.accentDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _isSap
                ? (_sapSyncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_download_outlined))
                : (_busyUpload
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file)),
            label: Text(
              _isSap
                  ? (_sapPendingInbox > 0 ? 'Hent nye fra SAP ($_sapPendingInbox)' : 'Synk SAP-innboks')
                  : 'Last opp rute-PDF-er',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsDashboard(_MassUi ui) {
    final ready = _skipped.isEmpty && _staged.isNotEmpty && _selected.isNotEmpty;
    return Row(
      children: [
        Expanded(child: _metricTile('Ruter i kø', '${_staged.length}', Icons.description_outlined, ui.accentDark)),
        const SizedBox(width: 8),
        Expanded(child: _metricTile('Sjåfører', '$_driversWithRoutesCount', Icons.local_shipping_outlined, ui.accentDark)),
        const SizedBox(width: 8),
        Expanded(
          child: _metricTile(
            'Manuell',
            '${_skipped.length}',
            Icons.build_outlined,
            _skipped.isNotEmpty ? Colors.orange.shade800 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _metricTile(
            'Publiser',
            ready ? 'Klar' : 'Vent',
            ready ? Icons.check_circle : Icons.hourglass_empty,
            ready ? Colors.green.shade700 : Colors.blue.shade700,
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAlertsPanel(_MassUi ui) {
    final ready = _skipped.isEmpty && _staged.isNotEmpty && _selected.isNotEmpty;
    final alerts = <Widget>[];

    if (!ready && _staged.isNotEmpty) {
      alerts.add(_alertRow(Icons.fact_check_outlined, Colors.blue.shade800, 'Kontroller skift, starttid og notat før du publiserer.'));
    }
    if (_staged.isNotEmpty && _multiLoadDriverCount > 0) {
      alerts.add(_alertRow(Icons.layers_outlined, Colors.orange.shade900, _multiLoadSummaryLine()));
    }
    if (_missingPhoneCount > 0) {
      alerts.add(_alertRow(
        Icons.phone_disabled_outlined,
        Colors.red.shade700,
        '$_missingPhoneCount sjåfør uten telefon — de får ikke SMS (ruten publiseres likevel).',
      ));
    }
    if (_skipped.isNotEmpty) {
      alerts.add(_alertRow(
        Icons.warning_amber_rounded,
        Colors.orange.shade900,
        '${_skipped.length} PDF må fordeles manuelt under fanen «Manuell tildeling».',
      ));
    }
    if (alerts.isEmpty && _staged.isEmpty) {
      alerts.add(_alertRow(Icons.info_outline, ui.accentDark, ui.emptyHint));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_staged.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busyUpload ? null : _clearAllStaged,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text('Tøm hele køen (${_staged.length})'),
              style: TextButton.styleFrom(foregroundColor: DriftProTheme.error),
            ),
          ),
        ...alerts,
      ],
    );
  }

  Widget _alertRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11.5, height: 1.35, color: color))),
        ],
      ),
    );
  }

  Widget _buildTabSection(_MassUi ui) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_MassTab>(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.all(Colors.white),
            foregroundColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.selected)) return ui.accentDark;
              return Colors.grey.shade700;
            }),
          ),
          segments: [
            ButtonSegment(
              value: _MassTab.drivers,
              label: const Text('Sjåfører', style: TextStyle(fontSize: 12)),
              icon: Badge(
                isLabelVisible: _driversWithRoutesCount > 0,
                label: Text('$_driversWithRoutesCount'),
                child: const Icon(Icons.groups_outlined, size: 18),
              ),
            ),
            ButtonSegment(
              value: _MassTab.overview,
              label: const Text('Importlogg', style: TextStyle(fontSize: 12)),
              icon: Badge(
                isLabelVisible: _importLog.isNotEmpty,
                label: Text('${_importLog.length}'),
                child: const Icon(Icons.history, size: 18),
              ),
            ),
            ButtonSegment(
              value: _MassTab.skipped,
              label: const Text('Manuell', style: TextStyle(fontSize: 12)),
              icon: Badge(
                isLabelVisible: _skipped.isNotEmpty,
                backgroundColor: Colors.orange,
                label: Text('${_skipped.length}'),
                child: const Icon(Icons.pan_tool_alt_outlined, size: 18),
              ),
            ),
          ],
          selected: {_sheetTab},
          onSelectionChanged: (s) => setState(() => _sheetTab = s.first),
        ),
        const SizedBox(height: 4),
        Text(_tabHint(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3)),
      ],
    );
  }

  String _tabHint() {
    return switch (_sheetTab) {
      _MassTab.drivers =>
        'Hver sjåfør kan ha én eller flere ruter samme dag. Velg ruter, juster skift og notat, deretter publiser.',
      _MassTab.overview =>
        'Oversikt over hva systemet gjorde med hver PDF (automatisk MAVI-fordeling eller årsak til manuell).',
      _MassTab.skipped =>
        'PDF-er uten treff på MAVI — velg bil, skiftplan og tildel manuelt før publisering.',
    };
  }

  Widget _buildTabContent(_MassUi ui) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ui.accent.withValues(alpha: 0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: switch (_sheetTab) {
          _MassTab.drivers => _buildDriverCentricList(ui),
          _MassTab.overview => _buildAssignmentOverview(ui),
          _MassTab.skipped => _buildSkippedList(ui),
        },
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildPublishBar(_MassUi ui) {
    final ready = _skipped.isEmpty && _staged.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ui.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ui.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ready
                ? 'Alt er fordelt — ${_selected.length} rute(r) klare. Velg registrering uten varsel eller SMS-varsling.'
                : _skipped.isNotEmpty
                    ? 'Fullfør manuell tildeling før publisering.'
                    : 'Legg til ruter før du publiserer.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 8),
          if (ready) ...[
            Row(
              children: [
                _legendDot('Uten varsel', RouteDispatchStatus.cellColor(RouteDispatchStatus.registered)),
                const SizedBox(width: 12),
                _legendDot('Varslet', RouteDispatchStatus.cellColor(RouteDispatchStatus.sent)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: _publishing || !ready ? null : () => _publish(notifyDriver: false),
            icon: _publishing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.inventory_2_outlined),
            label: Text(
              _skipped.isNotEmpty
                  ? 'Fordel ${_skipped.length} manuell(e) først'
                  : 'Publiser uten varsel (${_selected.length})',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: RouteDispatchStatus.cellColor(RouteDispatchStatus.registered),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _publishing || _staged.isEmpty ? null : () => _publish(notifyDriver: true),
            icon: _publishing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.rocket_launch_outlined),
            label: Text(
              _skipped.isNotEmpty
                  ? 'Fordel ${_skipped.length} manuell(e) først'
                  : _multiLoadDriverCount > 0
                      ? 'Publiser med SMS · ${_selected.length} ruter · $_multiLoadDriverCount med 2+ last'
                      : 'Publiser med SMS (${_selected.length})',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: ui.accentDark,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
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
        ? _maviFleet
        : _maviFleet.where((r) => _staged.any((s) => s.partnerVehicleId == r.vehicle.id)).toList();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            _showAllDrivers
                ? 'Viser alle ${_maviFleet.length} sjåfører i flåten'
                : 'Viser kun $_driversWithRoutesCount sjåfører med rute i kø',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Slå på for å se også de uten PDF', style: TextStyle(fontSize: 11)),
          value: _showAllDrivers,
          activeThumbColor: ui.accentDark,
          onChanged: (v) => setState(() => _showAllDrivers = v),
        ),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))),
              child: const Text('Velg alle'),
            ),
            TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Fjern valg')),
            const Spacer(),
            Text('${_selected.length}/${_staged.length} valgt', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Ingen sjåfører med rute i kø. ${_isSap ? "Trykk «Hent nye fra SAP»." : "Last opp PDF-er."}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          )
        else
          ...rows.map((r) => _buildDriverSection(r, ui)),
      ],
    );
  }

  Widget _buildDriverSection(FleetPartnerVehicleRow row, _MassUi ui) {
    final vid = row.vehicle.id;
    final routes = _staged.where((s) => s.partnerVehicleId == vid).toList();
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
          color: routes.isNotEmpty ? ui.accent.withValues(alpha: 0.35) : Colors.grey.shade300,
        ),
        color: routes.isNotEmpty ? ui.surfaceTint.withValues(alpha: 0.5) : Colors.grey.shade50,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: routes.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: routes.isNotEmpty ? ui.accent.withValues(alpha: 0.2) : Colors.grey.shade200,
            child: Icon(
              routes.isNotEmpty ? Icons.check : Icons.more_horiz,
              size: 18,
              color: routes.isNotEmpty ? ui.accentDark : Colors.grey,
            ),
          ),
          title: Text('$mavi · ${row.partner.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          subtitle: Text(
            routes.isEmpty
                ? 'Venter på PDF'
                : multi
                    ? '${routes.length} last · Lane ${lanes.join(", ")} · ${hasPhone ? "SMS OK" : "uten telefon"}'
                    : '${routes.length} rute · ${lanes.isNotEmpty ? "Lane ${lanes.first}" : "PDF"} · ${hasPhone ? "SMS OK" : "uten telefon"}',
            style: TextStyle(
              fontSize: 11,
              color: routes.isEmpty ? Colors.grey : (multi ? Colors.orange.shade900 : Colors.grey.shade700),
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
              : routes.map((share) => _buildRouteCard(share, row, ui)).toList(),
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

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: checked ? ui.accent.withValues(alpha: 0.5) : Colors.grey.shade300, width: checked ? 2 : 1),
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
                    Text(fileLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    Text(
                      lane != null ? 'Stowing Lane $lane · $mavi' : 'MAVI $mavi',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _shiftByShare[share.id]?.isNotEmpty == true ? _shiftByShare[share.id] : null,
                  isExpanded: true,
                  decoration: _fieldDeco('Skiftplan'),
                  items: _shifts.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _shiftByShare[share.id] = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: start);
                    if (picked != null) setState(() => _startByShare[share.id] = picked);
                  },
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('Start $startLabel'),
                ),
              ),
            ],
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
      itemCount: _skipped.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = _skipped[i];
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
                  items: _shifts
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
        tagline: 'Backup Form fra SAP → ${SapRoutesConfig.inboundAddress}',
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
      tagline: 'Last opp mange ruter på én gang — publiser med SMS',
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
