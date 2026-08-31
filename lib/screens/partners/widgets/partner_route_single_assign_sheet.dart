import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/partner/fleet_shift_filters.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/postal_code_registry.dart';
import '../../../core/services/partner/route_pdf_auto_assign.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/partner/route_time_band.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/route_notify_prefs.dart';
import 'partner_route_pdf_actions.dart';
import 'partner_route_pdf_thumbnail.dart';
import 'partner_route_workflow_ui.dart';
import 'route_publish_notify_buttons.dart';
import 'route_workflow_shared.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

enum _SingleAssignPhase { upload, review, publishing, success }

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ny rute: 1) last opp PDF → 2) auto sjåfør/skift/tid → 3) juster → lagre eller publiser.
class PartnerRouteSingleAssignSheet extends StatefulWidget {
  final String companyId;
  final List<FleetPartnerVehicleRow> fleet;
  final List<FleetShiftDefinition> shifts;
  final DateTime initialDay;
  final FleetPartnerVehicleRow? initialRow;
  final VoidCallback onDone;

  const PartnerRouteSingleAssignSheet({
    super.key,
    required this.companyId,
    required this.fleet,
    required this.shifts,
    required this.initialDay,
    this.initialRow,
    required this.onDone,
  });

  static Future<void> show(
    BuildContext context, {
    required String companyId,
    required List<FleetPartnerVehicleRow> fleet,
    required List<FleetShiftDefinition> shifts,
    required DateTime initialDay,
    FleetPartnerVehicleRow? initialRow,
    required VoidCallback onDone,
  }) {
    return showPartnerRouteWorkflowDialog<void>(
      context,
      child: PartnerRouteSingleAssignSheet(
        companyId: companyId,
        fleet: fleet,
        shifts: shifts,
        initialDay: initialDay,
        initialRow: initialRow,
        onDone: onDone,
      ),
    );
  }

  @override
  State<PartnerRouteSingleAssignSheet> createState() => _PartnerRouteSingleAssignSheetState();
}

class _PartnerRouteSingleAssignSheetState extends State<PartnerRouteSingleAssignSheet> {
  late DateTime _day;
  FleetPartnerVehicleRow? _row;
  String? _shiftId;
  TimeOfDay _start = const TimeOfDay(hour: 6, minute: 0);
  bool _busy = false;
  bool _analyzing = false;
  String? _actionError;

  Uint8List? _pdfBytes;
  String? _pdfFileName;
  RoutePdfAutoAssign? _auto;
  String? _analyzeError;
  _SingleAssignPhase _phase = _SingleAssignPhase.upload;
  String? _successDetail;
  String? _successMessage;
  String _successTitle = 'Rute sendt';

  @override
  void initState() {
    super.initState();
    _day = _dayOnly(widget.initialDay);
    _row = widget.initialRow;
  }

  // removed _loadPublishLabel — varsel velges per kanal nederst

  List<FleetPartnerVehicleRow> get _maviFleet =>
      PartnerService.filterMaviFleetOnly(widget.fleet);

  List<FleetShiftDefinition> get _shiftItems =>
      FleetShiftFilters.forRouteAssignment(widget.shifts);

  bool get _hasPdf => _pdfBytes != null && _pdfBytes!.isNotEmpty;

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 14)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _day = _dayOnly(d));
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _uploadPdfOnly() async {
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
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke lese PDF-filen.')),
        );
      }
      return;
    }

    setState(() {
      _analyzing = true;
      _analyzeError = null;
      _pdfFileName = file.name;
    });

    try {
      await PostalCodeRegistry.ensureLoaded();
      await PartnerService.ensureCanonicalFleetShifts(widget.companyId);
      final shifts = await PartnerService.fetchFleetShifts(widget.companyId);

      final vehicleMap = RoutePdfTextService.buildVehicleLookupMap<PartnerVehicle>(
        vehicles: _maviFleet.map((r) => r.vehicle),
        unitCodeOf: (v) => v.unitCode,
        registrationOf: (v) => v.registrationNumber,
      );

      final bundle = RoutePdfTextService.parseBundle(bytes, fallbackDate: _day);
      final auto = await RoutePdfAutoAssign.analyze(
        bytes: bytes,
        fallbackDate: _day,
        shifts: shifts,
        bundle: bundle,
      );

      FleetPartnerVehicleRow? matchedRow;
      if (auto.maviCode != null) {
        final vehicle = RoutePdfTextService.findVehicleInLookup(vehicleMap, auto.maviCode);
        if (vehicle != null) {
          for (final r in _maviFleet) {
            if (r.vehicle.id == vehicle.id) {
              matchedRow = r;
              break;
            }
          }
        }
      }

      final schedule = bundle.schedule;

      if (!mounted) return;
      final shiftOptions = _shiftItems;
      setState(() {
        _pdfBytes = bytes;
        _auto = auto;
        _row = matchedRow ?? _row ?? (_maviFleet.isNotEmpty ? _maviFleet.first : null);
        _day = _dayOnly(schedule.routeDate);
        if (schedule.routeStartAt != null) {
          _start = TimeOfDay(
            hour: schedule.routeStartAt!.hour,
            minute: schedule.routeStartAt!.minute,
          );
        }
        _shiftId = auto.shift?.id ??
            (shiftOptions.any((s) => s.id == _shiftId) ? _shiftId : null) ??
            (shiftOptions.isNotEmpty ? shiftOptions.first.id : null);
        _phase = _SingleAssignPhase.review;
        if (matchedRow == null && auto.maviCode != null) {
          _analyzeError =
              'Fant MAVI ${auto.maviCode} i PDF, men ingen matchende bil i flåten — velg sjåfør manuelt.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _analyzeError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<bool> _confirmPublish(RouteNotifyPrefs prefs) async {
    final channel = prefs.noneEnabled
        ? 'Uten varsel (kladd i kalender)'
        : prefs.shortLabel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bekreft utsendelse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rute til ${MaviUnitCodes.normalize(_row?.vehicle.unitCode ?? 'bil')} '
              '· ${DateFormat('d. MMM', 'nb').format(_day)}',
            ),
            const SizedBox(height: 8),
            Text('Varsling: $channel', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Sjåfør/eier får beskjed etter valgt kanal. Du kan sende purring senere fra planleggeren.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send nå')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _saveRoute({
    required bool publish,
    RouteNotifyPrefs notifyPrefs = RouteNotifyPrefs.none,
  }) async {
    if (!_hasPdf || _pdfFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Last opp PDF først.')),
      );
      return;
    }
    if (_row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg sjåfør / MAVI-bil.')),
      );
      return;
    }
    if (_shiftId == null || _shiftItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg skift.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _actionError = null;
      if (publish) _phase = _SingleAssignPhase.publishing;
    });
    try {
      final row = _row!;
      final cid = widget.companyId;
      final bytes = _pdfBytes!;
      final fileName = _pdfFileName!;

      final bundle = RoutePdfTextService.parseBundle(bytes, fallbackDate: _day);
      final shareId = await PartnerService.createStagedRouteShareFromPdf(
        companyId: cid,
        partner: row.partner,
        vehicle: row.vehicle,
        fileName: fileName,
        bytes: bytes,
        routeDate: bundle.schedule.routeDate,
        notes: _auto != null
            ? RoutePdfAutoAssign.composeAutoNotes(_auto!)
            : null,
        parsed: bundle,
      );

      final startAt = DateTime(
        _day.year,
        _day.month,
        _day.day,
        _start.hour,
        _start.minute,
      );

      await PartnerService.updateRouteShareFields(shareId, {
        'shift_id': _shiftId,
        'route_start_at': startAt.toUtc().toIso8601String(),
        'share_date': _day.toIso8601String().split('T').first,
        'partner_vehicle_id': row.vehicle.id,
      });

      final notifyDriver = publish && notifyPrefs.anyEnabled;

      if (publish) {
        await PartnerService.dispatchRouteShares(
          companyId: cid,
          shareIdToShiftId: {shareId: _shiftId!},
          date: _day,
          shareIdToStartAt: {shareId: startAt},
          notifyDriver: notifyDriver,
          notifyPrefs: notifyPrefs,
        );
      }

      final unit = MaviUnitCodes.normalize(row.vehicle.unitCode);
      final msg = publish
          ? notifyPrefs.successMessage(1)
          : 'PDF lagret som kladd for $unit.';

      if (!mounted) return;
      setState(() {
        _phase = _SingleAssignPhase.success;
        _successTitle = publish ? 'Rute sendt' : 'Kladd lagret';
        _successMessage = msg;
        _successDetail =
            '${row.partner.name} · ${DateFormat('EEEE d. MMM', 'nb').format(_day)} · '
            'Start ${_start.format(context)} · ${notifyPrefs.shortLabel}';
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _actionError = e.toString();
          _phase = _hasPdf ? _SingleAssignPhase.review : _SingleAssignPhase.upload;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted && _phase != _SingleAssignPhase.success) {
        setState(() => _busy = false);
      }
    }
  }

  void _finishSuccess() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final msg = _successMessage ?? 'Rute publisert.';
    Navigator.pop(context);
    widget.onDone();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _publishWithPrefs(RouteNotifyPrefs? prefs) async {
    final effective = prefs ?? RouteNotifyPrefs.none;
    if (!effective.noneEnabled) {
      final ok = await _confirmPublish(effective);
      if (!ok) return;
    }
    await _saveRoute(publish: true, notifyPrefs: effective);
  }

  Widget _buildReviewBody(bool busy) {
    final a = _auto;
    if (a == null) return const SizedBox.shrink();
    final band = RouteTimeBand.label(a.timeBand);
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lest fra PDF',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (a.maviCode != null) Text('MAVI: ${a.maviCode}'),
            if (a.driverNameFromPdf != null) Text('Sjåfør (PDF): ${a.driverNameFromPdf}'),
            if (a.postal.postalCodes.isNotEmpty)
              Text('Postnr: ${a.postal.postalCodes.take(8).join(', ')}'
                  '${a.postal.postalCodes.length > 8 ? '…' : ''}'),
            if (a.postal.hasConfidentRegion && a.postal.dominantRegion != null)
              Text(
                'Område: ${a.postal.dominantRegion} (${a.postal.dominantCount} av ${a.postal.deliveryStopCount} stopp) · $band',
              )
            else if (a.postal.postalCodes.isNotEmpty)
              const Text(
                'Område: ikke entydig fra PDF — velg skift manuelt.',
                style: TextStyle(color: Colors.black87),
              ),
            if (a.shiftLabel != null) Text('Foreslått skift: ${a.shiftLabel}'),
          ],
        ),
      ),
    );
  }

  void _handleBack() {
    if (_busy) return;
    switch (_phase) {
      case _SingleAssignPhase.review:
        setState(() => _phase = _SingleAssignPhase.upload);
      case _SingleAssignPhase.success:
        _finishSuccess();
      case _SingleAssignPhase.upload:
      case _SingleAssignPhase.publishing:
        if (!_busy) Navigator.of(context).maybePop();
    }
  }

  int get _stepIndex {
    switch (_phase) {
      case _SingleAssignPhase.upload:
        return 0;
      case _SingleAssignPhase.review:
      case _SingleAssignPhase.publishing:
        return 1;
      case _SingleAssignPhase.success:
        return 2;
    }
  }

  Widget _buildMainContent(bool busy, Color accent) {
    if (_phase == _SingleAssignPhase.success) {
      return RouteWorkflowSuccessPanel(
        title: _successTitle,
        message: _successMessage ?? 'Ruten er lagret og sendt.',
        detail: _successDetail,
        accent: accent,
        onDone: _finishSuccess,
      );
    }

    if (_phase == _SingleAssignPhase.publishing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DriftProLoadingIndicator(size: 48),
            const SizedBox(height: 16),
            const Text(
              'Lagrer og sender rute…',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Varsling sendes etter valgt kanal',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        RouteWorkflowStepRail(
          steps: const ['PDF', 'Kontroll', 'Sendt'],
          activeIndex: _stepIndex,
          accent: accent,
        ),
        const SizedBox(height: 16),
        if (!_hasPdf) ...[
          RouteWorkflowUploadHero(
            accent: accent,
            busy: _analyzing,
            onUpload: busy ? null : _uploadPdfOnly,
            title: 'Dra hit eller velg rute-PDF',
            subtitle:
                'MAVI, sjåfør, dato, skift og starttid leses automatisk. '
                'Du ser forhåndsvisning og kontrollerer før du sender push, SMS eller e-post.',
          ),
        ] else ...[
          if (_pdfFileName != null)
            Text(
              'Fil: $_pdfFileName',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          if (_analyzeError != null) ...[
            const SizedBox(height: 8),
            Material(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _analyzeError!,
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900, height: 1.35),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PartnerRoutePdfThumbnail(
              bytes: _pdfBytes,
              height: 160,
              showFullPage: true,
              zoomTripHeader: true,
              onTapOpen: busy
                  ? null
                  : () => PartnerRoutePdfActions.openPdfBytes(
                        context,
                        bytes: _pdfBytes!,
                        title: _pdfFileName ?? 'Rute-PDF',
                      ),
            ),
          ),
          const SizedBox(height: 12),
          _buildReviewBody(busy),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => PartnerRoutePdfActions.openPdfBytes(
                      context,
                      bytes: _pdfBytes!,
                      title: _pdfFileName ?? 'Rute-PDF',
                    ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Åpne full PDF — kontroller før publisering'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
          ),
          if (_phase == _SingleAssignPhase.review) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: busy ? null : _pickDay,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('EEEE d. MMMM yyyy', 'nb').format(_day)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FleetPartnerVehicleRow>(
              decoration: const InputDecoration(
                labelText: 'Sjåfør / MAVI-bil *',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              isExpanded: true,
              value: _maviFleet.contains(_row) ? _row : null,
              items: _maviFleet
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        '${MaviUnitCodes.normalize(r.vehicle.unitCode)}'
                        '${r.vehicle.driverName != null && r.vehicle.driverName!.trim().isNotEmpty ? ' · ${r.vehicle.driverName}' : ''}'
                        ' · ${r.partner.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => _row = v),
            ),
            const SizedBox(height: 12),
            if (_shiftItems.isEmpty)
              Text(
                'Ingen skift — opprett under Administrer skift.',
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              )
            else
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Skift *',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                isExpanded: true,
                value: _shiftItems.any((s) => s.id == _shiftId) ? _shiftId : null,
                items: _shiftItems
                    .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => _shiftId = v),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starttid'),
              subtitle: Text(
                _start.format(context),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              trailing: const Icon(Icons.schedule),
              onTap: busy ? null : _pickStart,
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || _analyzing;
    const accent = DriftProTheme.primaryGreen;

    return PartnerRouteWorkflowShell(
      accent: accent,
      accentDark: accent,
      icon: Icons.route_outlined,
      title: 'Ny rute',
      subtitle: 'Én PDF — auto sjåfør, skift og dato fra filen',
      badge: 'Enkelt',
      onBack: _handleBack,
      metrics: [
        RouteWorkflowMetric(
          label: 'PDF',
          value: _hasPdf ? 'OK' : '—',
          icon: Icons.picture_as_pdf_outlined,
          color: _hasPdf ? Colors.green.shade700 : Colors.grey,
        ),
        RouteWorkflowMetric(
          label: 'Sjåfør',
          value: _row != null ? MaviUnitCodes.normalize(_row!.vehicle.unitCode) : '—',
          icon: Icons.local_shipping_outlined,
          color: accent,
        ),
        RouteWorkflowMetric(
          label: 'Dato',
          value: DateFormat('d.M', 'nb').format(_day),
          icon: Icons.event_outlined,
          color: accent,
        ),
        RouteWorkflowMetric(
          label: 'Start',
          value: _start.format(context),
          icon: Icons.schedule_outlined,
          color: accent,
        ),
      ],
      sidebar: FilledButton.icon(
        onPressed: busy ? null : _uploadPdfOnly,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          minimumSize: const Size(double.infinity, 52),
        ),
        icon: _analyzing
            ? SizedBox(width: 20, height: 20, child: DriftProLoadingIndicator(size: 20))
            : const Icon(Icons.upload_file),
        label: Text(_hasPdf ? 'Bytt PDF' : 'Last opp PDF'),
      ),
      tabLabels: const ['Oppsett'],
      selectedTabIndex: 0,
      onTabSelected: (_) {},
      tabCaption: switch (_phase) {
        _SingleAssignPhase.upload =>
          'Last opp rute-PDF. MAVI, dato, skift og starttid leses automatisk.',
        _SingleAssignPhase.review =>
          'Kontroller det systemet fant — juster om nødvendig, deretter lagre eller publiser.',
        _SingleAssignPhase.publishing => 'Sender rute og varsling…',
        _SingleAssignPhase.success => 'Ferdig — ruten er i planleggeren.',
      },
      tabBody: _buildMainContent(busy, accent),
      footer: _phase == _SingleAssignPhase.success
          ? const SizedBox.shrink()
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_actionError != null) ...[
            Material(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_actionError!, style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_phase == _SingleAssignPhase.review && _hasPdf) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : () => _saveRoute(publish: false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lagre som kladd'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
            ),
            const SizedBox(height: 8),
            RoutePublishNotifyButtons(
              busy: busy,
              onPublish: (prefs) => _publishWithPrefs(prefs),
            ),
          ] else if (_phase == _SingleAssignPhase.upload)
            Text(
              'Last opp PDF for å aktivere lagring og publisering.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }
}
