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
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Velg dag + sjåfør, last opp én PDF, lagre kladd eller publiser med én gang.
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

  @override
  State<PartnerRouteSingleAssignSheet> createState() => _PartnerRouteSingleAssignSheetState();
}

class _PartnerRouteSingleAssignSheetState extends State<PartnerRouteSingleAssignSheet> {
  late DateTime _day;
  FleetPartnerVehicleRow? _row;
  String? _shiftId;
  TimeOfDay _start = const TimeOfDay(hour: 6, minute: 0);
  bool _publishNow = true;
  bool _busy = false;
  String? _pickedFileName;

  @override
  void initState() {
    super.initState();
    _day = _dayOnly(widget.initialDay);
    _row = widget.initialRow ?? (widget.fleet.isNotEmpty ? widget.fleet.first : null);
    final shiftItems = widget.shifts.where((s) => !s.isAvailability).toList();
    final routeOps = shiftItems.where((s) => s.shiftKind == 'route_ops').toList();
    _shiftId = (routeOps.isNotEmpty ? routeOps.first : shiftItems.firstOrNull)?.id;
  }

  List<FleetShiftDefinition> get _shiftItems =>
      widget.shifts.where((s) => !s.isAvailability).toList();

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

  Future<void> _submit() async {
    if (_row == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg sjåfør / MAVI-bil først.')),
      );
      return;
    }
    if (_shiftId == null || _shiftItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingen skift — opprett skift under Ruter → Administrer skift.')),
      );
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _pickedFileName = file.name;
      _busy = true;
    });

    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunne ikke lese PDF-filen.')),
        );
      }
      return;
    }

    try {
      final row = _row!;
      final cid = widget.companyId;
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
        fallbackDate: _day,
      );
      final routeDay = _dayOnly(schedule.routeDate);
      final startAt = schedule.routeStartAt ??
          DateTime(routeDay.year, routeDay.month, routeDay.day, _start.hour, _start.minute);

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
          shiftId: _shiftId,
          partnerVehicleId: row.vehicle.id,
          createdAt: DateTime.now(),
          pdfSearchText: pdfExtract?.isEmpty ?? true ? null : pdfExtract,
        ),
      );

      if ((pdfExtract ?? '').isNotEmpty) {
        await PartnerService.saveRoutePdfSearchText(created.id, pdfExtract!.trim());
      }

      await PartnerService.updateRouteShareFields(created.id, {
        'shift_id': _shiftId,
        'route_start_at': startAt.toUtc().toIso8601String(),
        'share_date': routeDay.toIso8601String().split('T').first,
      });

      if (_publishNow) {
        await PartnerService.dispatchRouteShares(
          companyId: cid,
          shareIdToShiftId: {created.id: _shiftId!},
          date: routeDay,
          shareIdToStartAt: {created.id: startAt},
        );
      }

      widget.onDone();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _publishNow
                ? 'Rute publisert til ${MaviUnitCodes.normalize(row.vehicle.unitCode)} '
                    '(${DateFormat('d.M.y').format(routeDay)}). SMS sendt til sjåfør og bil-eier.'
                : 'PDF lagret som kladd for ${MaviUnitCodes.normalize(row.vehicle.unitCode)} '
                    '(${DateFormat('d.M.y').format(routeDay)}). Publiser fra kalender eller kladd-kø.',
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

  @override
  Widget build(BuildContext context) {
    final shiftItems = _shiftItems;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ny rute — én og én', style: DriftProTheme.headingMd),
            const SizedBox(height: 4),
            Text(
              'Velg dag og sjåfør, last opp PDF, publiser med én gang eller lagre som kladd.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.35),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickDay,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat('EEEE d. MMMM yyyy', 'nb').format(_day)),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FleetPartnerVehicleRow>(
              decoration: const InputDecoration(
                labelText: 'Sjåfør / MAVI-bil *',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              value: _row,
              items: widget.fleet
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(
                        '${MaviUnitCodes.normalize(r.vehicle.unitCode)} · ${r.partner.name} · ${r.vehicle.registrationNumber}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _row = v),
            ),
            const SizedBox(height: 12),
            if (shiftItems.isEmpty)
              const Text(
                'Ingen skift funnet. Gå til «Administrer skift» først.',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              )
            else
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Skift *', border: OutlineInputBorder()),
                isExpanded: true,
                value: _shiftId,
                items: shiftItems.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: _busy ? null : (v) => setState(() => _shiftId = v),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Planlagt start'),
              subtitle: Text(
                _start.format(context),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              trailing: const Icon(Icons.schedule),
              onTap: _busy ? null : _pickStart,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Publiser og send SMS med én gang'),
              subtitle: const Text('Av = lagres som kladd — publiser senere fra kalender'),
              value: _publishNow,
              onChanged: _busy ? null : (v) => setState(() => _publishNow = v),
            ),
            if (_pickedFileName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Valgt fil: $_pickedFileName', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size(double.infinity, 52),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(_publishNow ? Icons.rocket_launch_outlined : Icons.upload_file),
              label: Text(_publishNow ? 'Velg PDF, last opp og publiser' : 'Velg PDF og lagre som kladd'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Avbryt'),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
