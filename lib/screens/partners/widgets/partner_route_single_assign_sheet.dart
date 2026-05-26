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
import 'partner_route_workflow_ui.dart';

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

  Uint8List? _pdfBytes;
  String? _pdfFileName;
  RoutePdfAutoAssign? _auto;
  String? _analyzeError;

  @override
  void initState() {
    super.initState();
    _day = _dayOnly(widget.initialDay);
    _row = widget.initialRow;
  }

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
        _shiftId = auto.shift?.id ?? _shiftId;
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

  Future<void> _saveRoute({required bool publish}) async {
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

    setState(() => _busy = true);
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

      if (publish) {
        await PartnerService.dispatchRouteShares(
          companyId: cid,
          shareIdToShiftId: {shareId: _shiftId!},
          date: _day,
          shareIdToStartAt: {shareId: startAt},
        );
      }

      widget.onDone();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish
                ? 'Rute publisert til ${MaviUnitCodes.normalize(row.vehicle.unitCode)} '
                    '(${DateFormat('d.M.y').format(_day)}).'
                : 'PDF lagret som kladd for ${MaviUnitCodes.normalize(row.vehicle.unitCode)}.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _autoSummaryCard() {
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

  Widget _stepIndicator() {
    final step = _hasPdf ? 2 : 1;
    return Row(
      children: [
        _stepDot(1, 'PDF', step >= 1),
        Expanded(child: Container(height: 2, color: step >= 2 ? DriftProTheme.primaryGreen : Colors.grey.shade300)),
        _stepDot(2, 'Kontroll', step >= 2),
        Expanded(child: Container(height: 2, color: Colors.grey.shade300)),
        _stepDot(3, 'Lagre', false),
      ],
    );
  }

  Widget _stepDot(int n, String label, bool active) {
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: active ? DriftProTheme.primaryGreen : Colors.grey.shade300,
          child: Text('$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiftItems = _shiftItems;
    final busy = _busy || _analyzing;
    const accent = DriftProTheme.primaryGreen;

    return PartnerRouteWorkflowShell(
      accent: accent,
      accentDark: accent,
      icon: Icons.route_outlined,
      title: 'Ny rute',
      subtitle: 'Én PDF — auto sjåfør, skift og dato fra filen',
      badge: 'Enkelt',
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
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: Text(_hasPdf ? 'Bytt PDF' : 'Last opp PDF'),
      ),
      tabLabels: const ['Oppsett'],
      selectedTabIndex: 0,
      onTabSelected: (_) {},
      tabCaption: _hasPdf
          ? 'Kontroller det systemet fant — juster om nødvendig, deretter lagre eller publiser.'
          : 'Last opp rute-PDF. MAVI, dato, skift og starttid leses automatisk.',
      tabBody: ListView(
        padding: const EdgeInsets.all(14),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _stepIndicator(),
          const SizedBox(height: 16),
          if (_pdfFileName != null)
            Text('Fil: $_pdfFileName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
          if (_hasPdf) ...[
            const SizedBox(height: 12),
            _autoSummaryCard(),
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
            if (shiftItems.isEmpty)
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
                value: shiftItems.any((s) => s.id == _shiftId) ? _shiftId : null,
                items: shiftItems
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
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasPdf) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : () => _saveRoute(publish: false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Lagre som kladd'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : () => _saveRoute(publish: true),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                minimumSize: const Size(double.infinity, 50),
              ),
              icon: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch_outlined),
              label: const Text('Publiser og send SMS'),
            ),
          ] else
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
