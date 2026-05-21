import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
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
  final String reason;
  final String? detectedCode;
  String? selectedVehicleId;
  String? shiftId;
  TimeOfDay startTime;
  final TextEditingController noteCtrl;

  _SkippedPdf({
    required this.fileName,
    required this.bytes,
    required this.reason,
    this.detectedCode,
    TimeOfDay? startTime,
  })  : startTime = startTime ?? const TimeOfDay(hour: 6, minute: 0),
        noteCtrl = TextEditingController();
}

enum _AutoMassTab { drivers, overview, skipped }

/// AUTO MASS: masse-PDF, manuell tildeling av hoppet over, deretter publiser med SMS.
class PartnerRouteAutoMassSheet extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final DateTime initialRouteDate;

  const PartnerRouteAutoMassSheet({
    super.key,
    required this.fleet,
    required this.initialRouteDate,
  });

  static Future<bool?> show(
    BuildContext context, {
    required List<FleetPartnerVehicleRow> fleet,
    DateTime? routeDate,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.92;
        return SizedBox(
          height: h,
          child: PartnerRouteAutoMassSheet(
            fleet: fleet,
            initialRouteDate: routeDate ?? DateTime.now(),
          ),
        );
      },
    );
  }

  @override
  State<PartnerRouteAutoMassSheet> createState() => _PartnerRouteAutoMassSheetState();
}

class _PartnerRouteAutoMassSheetState extends State<PartnerRouteAutoMassSheet> {
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
  _AutoMassTab _sheetTab = _AutoMassTab.drivers;

  @override
  void dispose() {
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
    _reload();
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
          if (_skipped.isNotEmpty) _sheetTab = _AutoMassTab.skipped;
          else _sheetTab = _AutoMassTab.drivers;
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
          if (_skipped.isEmpty) _sheetTab = _AutoMassTab.drivers;
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

  Future<void> _publish() async {
    if (_skipped.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Du har ${_skipped.length} PDF som ikke er tildelt sjåfør. Fordel alle før publisering.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      setState(() => _sheetTab = _AutoMassTab.skipped);
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
        title: const Text('Publiser ruter?'),
        content: Text(
          '${_multiLoadSummaryLine()}\n\n'
          'Sender ${_selected.length} valgte rute(r) med SMS '
          '(${_missingPhoneCount > 0 ? "$_missingPhoneCount uten telefon — får ikke SMS" : "alle med telefon varsles"}).\n\n'
          'Flere PDF med samme MAVI samme dag = flere last (Stowing Lane 1A, 1B, 17B osv.).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            child: const Text('Publiser'),
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
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publisert ${map.length} rute(r). SMS sendt der telefon finnes.')),
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: DriftProTheme.primaryGreen, size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AUTO MASS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                    Text(
                      'Last opp mange PDF-er · fordél · publiser med SMS til sjåfør og bileier',
                      style: TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _routeDate,
                firstDate: DateTime.now().subtract(const Duration(days: 7)),
                lastDate: DateTime.now().add(const Duration(days: 90)),
              );
              if (d != null) setState(() => _routeDate = d);
            },
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('Rutedato: ${DateFormat('d. MMM yyyy', 'nb').format(_routeDate)}'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busyUpload ? null : _pickPdfs,
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 48),
            ),
            icon: _busyUpload
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.upload_file),
            label: const Text('Last opp rute-PDF-er'),
          ),
          const SizedBox(height: 10),
          _summaryBanner(),
          if (_staged.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busyUpload ? null : _clearAllStaged,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text('Tøm alle tildelte ruter (${_staged.length})'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DriftProTheme.error,
                side: BorderSide(color: DriftProTheme.error.withValues(alpha: 0.5)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SegmentedButton<_AutoMassTab>(
            segments: [
              ButtonSegment(
                value: _AutoMassTab.drivers,
                label: Text('Sjåfører ($_driverWithRouteCount)'),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
              ),
              ButtonSegment(
                value: _AutoMassTab.overview,
                label: Text('Fordeling (${_importLog.length})'),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
              ),
              ButtonSegment(
                value: _AutoMassTab.skipped,
                label: Text('Hoppet over (${_skipped.length})'),
                icon: Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: _skipped.isNotEmpty ? Colors.orange : null,
                ),
              ),
            ],
            selected: {_sheetTab},
            onSelectionChanged: (s) => setState(() => _sheetTab = s.first),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: switch (_sheetTab) {
              _AutoMassTab.drivers => _buildDriverCentricList(),
              _AutoMassTab.overview => _buildAssignmentOverview(),
              _AutoMassTab.skipped => _buildSkippedList(),
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _publishing || _staged.isEmpty ? null : _publish,
            icon: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_outlined),
            label: Text(
              _skipped.isNotEmpty
                  ? 'Fordel alle manuelle først'
                  : _multiLoadDriverCount > 0
                      ? 'Publiser ${_selected.length} ruter (${_multiLoadDriverCount} sjåf. 2+ last)'
                      : 'Publiser ${_selected.length} rute(r) — SMS til sjåfør',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBanner() {
    final ready = _skipped.isEmpty && _staged.isNotEmpty && _selected.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ready ? Colors.green : Colors.blue).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (ready ? Colors.green : Colors.blue).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ready ? 'Klar til publisering' : 'Kontroller fordeling før publisering',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: ready ? Colors.green.shade800 : Colors.blue.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_staged.length} rute-PDF · $_driverWithRouteCount sjåfører · '
            '${_skipped.length} hoppet over',
            style: const TextStyle(fontSize: 12),
          ),
          if (_staged.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _multiLoadSummaryLine(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _multiLoadDriverCount > 0 ? Colors.orange.shade900 : Colors.grey.shade700,
              ),
            ),
          ],
          if (_missingPhoneCount > 0)
            Text(
              '$_missingPhoneCount bil uten telefon — får ikke SMS ved publisering',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverCentricList() {
    if (_staged.isEmpty && _skipped.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Last opp rute-PDF-er. Systemet leser MAVI-nummer kun fra PDF-innhold '
            '(Trip Overview / Resource ID, f.eks. NO_O_M0042) — ikke filnavn. '
            'Sjekk fanen «Fordeling» etter opplasting.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))),
              child: const Text('Velg alle ruter'),
            ),
            TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Fjern valg')),
          ],
        ),
        ..._maviFleet.map(_buildDriverSection),
      ],
    );
  }

  Widget _buildDriverSection(FleetPartnerVehicleRow row) {
    final vid = row.vehicle.id;
    final routes = _staged.where((s) => s.partnerVehicleId == vid).toList();
    final mavi = MaviUnitCodes.normalize(row.vehicle.unitCode);
    final portal = _portalByVehicle[vid];
    final phone = portal?.phone ?? row.vehicle.phone;
    final hasPhone = phone != null && phone.trim().length >= 8;
    final lanes = routes.map(_stowingForShare).whereType<String>().toSet().toList()..sort();
    final multi = routes.length >= 2;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: routes.isNotEmpty,
        leading: Icon(
          routes.isNotEmpty ? Icons.check_circle : Icons.radio_button_unchecked,
          color: routes.isNotEmpty ? Colors.green : Colors.grey,
        ),
        title: Text(
          '$mavi · ${row.partner.name}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          routes.isEmpty
              ? 'Ingen rute i kø — venter på PDF'
              : multi
                  ? '${routes.length} last samme dag'
                      '${lanes.isNotEmpty ? " · Lane ${lanes.join(", ")}" : ""}'
                      ' · ${hasPhone ? "SMS OK" : "mangler telefon"}'
                  : '${routes.length} PDF'
                      '${lanes.isNotEmpty ? " · Lane ${lanes.first}" : ""}'
                      ' · ${hasPhone ? "SMS OK" : "mangler telefon"}',
          style: TextStyle(
            fontSize: 11,
            color: routes.isEmpty
                ? Colors.grey
                : multi
                    ? Colors.orange.shade900
                    : null,
            fontWeight: multi ? FontWeight.w600 : null,
          ),
        ),
        children: [
          if (routes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Ingen PDF tildelt ennå. Last opp flere filer eller tildel under «Hoppet over».',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            ...routes.map((share) => _buildRouteCard(share, row)),
        ],
      ),
    );
  }

  Widget _buildRouteCard(PartnerRouteShare share, FleetPartnerVehicleRow row) {
    final checked = _selected.contains(share.id);
    final noteCtrl = _noteByShare.putIfAbsent(share.id, () => TextEditingController(text: share.notes ?? ''));
    final lane = _stowingForShare(share);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: checked,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              share.title ?? share.pdfStoragePath.split('/').last,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              lane != null
                  ? 'Stowing Lane $lane · ${MaviUnitCodes.normalize(row.vehicle.unitCode)} · ${row.partner.name}'
                  : 'PDF → ${MaviUnitCodes.normalize(row.vehicle.unitCode)} · ${row.partner.name}',
              style: const TextStyle(fontSize: 11),
            ),
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(share.id);
                } else {
                  _selected.remove(share.id);
                }
              });
            },
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Åpne PDF'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Fjern fra kø',
                onPressed: _busyUpload ? null : () => _removeShare(share),
                icon: const Icon(Icons.delete_outline, color: DriftProTheme.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: share.partnerVehicleId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Bytt sjåfør / bedrift (MAVI)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
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
            onChanged: _busyUpload
                ? null
                : (vid) {
                    if (vid != null && vid != share.partnerVehicleId) {
                      _reassignShare(share, vid);
                    }
                  },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notat til sjåfør',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _shiftByShare[share.id]?.isNotEmpty == true ? _shiftByShare[share.id] : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Skiftplan',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: _shifts.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _shiftByShare[share.id] = v);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Starttid', style: TextStyle(fontSize: 12)),
            subtitle: Text(
              () {
                final t = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);
                return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              }(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: const Icon(Icons.schedule, size: 20),
            onTap: () async {
              final t = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);
              final picked = await showTimePicker(context: context, initialTime: t);
              if (picked != null) setState(() => _startByShare[share.id] = picked);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentOverview() {
    if (_importLog.isEmpty) {
      return const Center(
        child: Text(
          'Ingen import ennå. Etter opplasting ser du her hvilken PDF som ble gitt hvilken sjåfør.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _importLog.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final row = _importLog[i];
        final ok = row.status == 'ok';
        return ListTile(
          leading: Icon(
            ok ? Icons.check_circle : Icons.warning_amber_rounded,
            color: ok ? Colors.green : Colors.orange,
          ),
          title: Text(row.fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Text(
            ok
                ? '→ ${row.maviCode ?? "?"}'
                    '${row.stowingLane != null ? " · Lane ${row.stowingLane}" : ""}'
                    ' · ${row.driverLabel ?? ""}'
                : row.reason ?? 'Hoppet over',
            style: TextStyle(fontSize: 12, color: ok ? null : Colors.orange.shade900),
          ),
          isThreeLine: !ok,
        );
      },
    );
  }

  Widget _buildSkippedList() {
    if (_skipped.isEmpty) {
      return const Center(
        child: Text(
          'Ingen hoppet-over PDF-er. Alt er fordelt automatisk.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _skipped.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = _skipped[i];
        return Card(
          color: Colors.orange.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(item.reason, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
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
                        style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
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
