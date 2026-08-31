import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/postal_code_registry.dart';
import '../../../core/services/partner/route_pdf_text_service.dart';
import '../../../core/services/partner/fleet_shift_filters.dart';
import '../../../core/services/partner/route_shift_resolver.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';
import 'route_calendar_chip.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Én arbeidsflate: last opp PDF → kontroller alle sjåfører → publiser.
class PartnerRoutePublishPanel extends StatefulWidget {
  final List<FleetPartnerVehicleRow> fleet;
  final VoidCallback? onChanged;

  const PartnerRoutePublishPanel({
    super.key,
    this.fleet = const [],
    this.onChanged,
  });

  @override
  State<PartnerRoutePublishPanel> createState() => _PartnerRoutePublishPanelState();
}

class _PartnerRoutePublishPanelState extends State<PartnerRoutePublishPanel> {
  bool _loading = true;
  bool _busyUpload = false;
  bool _publishing = false;
  List<PartnerRouteShare> _staged = [];
  final Set<String> _selected = {};
  final Map<String, String> _shiftByShare = {};
  final Map<String, String> _pdfSuggestedShiftByShare = {};
  final Map<String, TimeOfDay?> _startByShare = {};
  final Map<String, DateTime> _dateByShare = {};
  List<FleetShiftDefinition> _shifts = [];
  Map<String, PartnerPortalAccount> _portalByVehicle = {};
  DateTime _routeDate = DateTime.now();

  DateTime _routeDayFor(String shareId) {
    final cached = _dateByShare[shareId];
    if (cached != null) return cached;
    final share = _staged.where((s) => s.id == shareId).firstOrNull;
    if (share == null) return _routeDate;
    return PartnerService.routeDayForShare(share);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid);
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final staged = await PartnerService.fetchStagedRouteShares(cid);
      final portals = <String, PartnerPortalAccount>{};
      final partnerIds = widget.fleet.map((r) => r.partner.id).toSet();
      for (final pid in partnerIds) {
        for (final a in await PartnerService.fetchPortalAccounts(pid)) {
          if (a.partnerVehicleId != null) portals[a.partnerVehicleId!] = a;
        }
      }
      await PostalCodeRegistry.ensureLoaded();
      final shiftById = <String, String>{};
      final pdfSuggested = <String, String>{};
      for (final s in staged) {
        final pdfText = await RouteShiftResolver.loadPdfTextForShare(s);
        final sid = await RouteShiftResolver.resolveShiftIdForStagedShare(
          share: s,
          allShifts: shifts,
          pdfText: pdfText,
        );
        if (sid != null && sid.isNotEmpty) {
          shiftById[s.id] = sid;
          pdfSuggested[s.id] = sid;
          if (s.shiftId != sid) {
            await PartnerService.updateRouteShareFields(s.id, {'shift_id': sid});
          }
        } else {
          shiftById[s.id] = s.shiftId ?? '';
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
        _shiftByShare
          ..clear()
          ..addAll(shiftById);
        _pdfSuggestedShiftByShare
          ..clear()
          ..addAll(pdfSuggested);
        _dateByShare.clear();
        for (final s in staged) {
          _dateByShare[s.id] = PartnerService.routeDayForShare(s);
          _startByShare.putIfAbsent(s.id, () {
            if (s.routeStartAt != null) {
              return TimeOfDay(
                hour: s.routeStartAt!.hour,
                minute: s.routeStartAt!.minute,
              );
            }
            return const TimeOfDay(hour: 6, minute: 0);
          });
        }
        if (staged.isNotEmpty) {
          _routeDate = PartnerService.groupSharesByRouteDay(staged).keys.first;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  FleetPartnerVehicleRow? _rowForShare(PartnerRouteShare share) {
    for (final row in widget.fleet) {
      if (row.vehicle.id == share.partnerVehicleId) return row;
    }
    return null;
  }

  Map<String, List<PartnerRouteShare>> get _byVehicle {
    final m = <String, List<PartnerRouteShare>>{};
    for (final s in _staged) {
      final key = s.partnerVehicleId ?? s.id;
      m.putIfAbsent(key, () => []).add(s);
    }
    return m;
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

  // ── PDF import (samme logikk som mass panel) ─────────────────────────────

  Future<void> _importPdfs(List<PlatformFile> files) async {
    if (_busyUpload || files.isEmpty) return;
    setState(() => _busyUpload = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final vehicleMap = RoutePdfTextService.buildVehicleLookupMap(
        vehicles: widget.fleet.map((r) => r.vehicle),
        unitCodeOf: (v) => v.unitCode,
        registrationOf: (v) => v.registrationNumber,
      );
      final partnerById = {for (final r in widget.fleet) r.partner.id: r.partner};
      int ok = 0, skip = 0;
      for (final file in files) {
        Uint8List? bytes = file.bytes;
        if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }
        if (bytes == null || bytes.isEmpty) {
          skip++;
          continue;
        }
        final code = RoutePdfTextService.extractResourceIdFromBytes(bytes);
        if (code == null) {
          skip++;
          continue;
        }
        final vehicle = RoutePdfTextService.findVehicleInLookup(vehicleMap, code);
        if (vehicle == null) {
          skip++;
          continue;
        }
        final partner = partnerById[vehicle.partnerId];
        if (partner == null) {
          skip++;
          continue;
        }
        final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path =
            'company_$cid/partner_routes/${DateTime.now().millisecondsSinceEpoch}_${vehicle.unitCode}_$safeName';
        final storedPath =
            await PartnerService.uploadPartnerRoutePdf(storagePath: path, bytes: bytes);
        final pdfText = RoutePdfTextService.extractFullText(bytes);
        final schedule = RoutePdfTextService.resolveSchedule(pdfText, fallbackDate: _routeDate);
        final share = await PartnerService.addRouteShare(
          PartnerRouteShare(
            id: '',
            partnerId: partner.id,
            companyId: cid,
            title: 'Rute ${vehicle.unitCode} — ${file.name}',
            pdfStoragePath: storedPath,
            shareDate: schedule.routeDate,
            isDailyShare: true,
            createdAt: DateTime.now(),
            dispatchStatus: 'staged',
            pdfSearchText: pdfText.isEmpty ? null : pdfText,
            partnerVehicleId: vehicle.id,
          ),
        );
        if (pdfText.isNotEmpty) {
          await PartnerService.saveRoutePdfSearchText(share.id, pdfText);
        }
        if (schedule.routeStartAt != null) {
          await PartnerService.updateRouteShareFields(share.id, {
            'route_start_at': schedule.routeStartAt!.toUtc().toIso8601String(),
          });
        }
        ok++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('La til $ok rute(r) i køen. $skip hoppet over.')),
        );
      }
      await _reload();
      widget.onChanged?.call();
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

    final lines = <String>[];
    final seenVehicle = <String>{};
    for (final id in _selected) {
      final share = _staged.firstWhere((s) => s.id == id);
      final row = _rowForShare(share);
      final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
      final partner = row?.partner.name ?? '';
      final shiftId = _shiftByShare[id];
      final shiftName = shiftId != null
          ? _shifts.where((s) => s.id == shiftId).map((s) => s.name).firstOrNull ?? '—'
          : '—';
      final t = _startByShare[id] ?? const TimeOfDay(hour: 6, minute: 0);
      final startStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final dayLabel = DateFormat('d.M.y').format(_routeDayFor(id));
      if (seenVehicle.add(share.partnerVehicleId ?? id)) {
        lines.add('• $dayLabel · $partner · $mavi — skift «$shiftName», start $startStr');
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publiser ruter til sjåfører?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Du sender ${_selected.length} PDF til ${_selected.length} tildeling(er). '
                'Sjåfører med telefon får SMS.',
                style: const TextStyle(height: 1.35),
              ),
              if (_missingPhoneCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '⚠ $_missingPhoneCount bil mangler telefon/portal — de får ikke SMS.',
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Oversikt:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...lines.take(12).map((l) => Text(l, style: const TextStyle(fontSize: 12))),
              if (lines.length > 12) Text('… og ${lines.length - 12} flere'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            child: const Text('Publiser nå'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;
    setState(() => _publishing = true);
    try {
      final map = {for (final id in _selected) id: _shiftByShare[id]!};
      final starts = <String, DateTime?>{};
      for (final id in _selected) {
        final t = _startByShare[id];
        if (t == null) continue;
        final day = _routeDayFor(id);
        starts[id] = DateTime(day.year, day.month, day.day, t.hour, t.minute);
      }
      await PartnerService.dispatchRouteShares(
        companyId: cid,
        shareIdToShiftId: map,
        date: _selected.isNotEmpty ? _routeDayFor(_selected.first) : _routeDate,
        shareIdToStartAt: starts,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publisert ${map.length} rute(r). Sjåfører kan logge inn og akseptere.')),
        );
      }
      await _reload();
      widget.onChanged?.call();
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
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(32), child: const DriftProLoadingCenter());
    }

    final vehicleCount = _byVehicle.length;
    final selectedCount = _selected.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: DriftProTheme.primaryGreen.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.publish_outlined, color: DriftProTheme.primaryGreen, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rutefordeling', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                      Text(
                        'Last opp PDF, kontroller at hver sjåfør har riktig rute, skift og start — publiser når alt stemmer.',
                        style: TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busyUpload ? null : _pickPdfs,
                  icon: _busyUpload
                      ? SizedBox(width: 16, height: 16, child: DriftProLoadingIndicator(size: 16))
                      : const Icon(Icons.upload_file),
                  label: const Text('Last opp rute-PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Oppdater'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (PartnerService.groupSharesByRouteDay(_staged).length > 1)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Text(
                  '${_staged.length} ruter på ${PartnerService.groupSharesByRouteDay(_staged).length} datoer — publiseres per PDF-dato.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                ),
              ),
            const SizedBox(height: 12),
            _statusBanner(vehicleCount, selectedCount),
            const SizedBox(height: 10),
            if (_staged.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Ingen ruter i køen. Last opp PDF-er — de kobles automatisk til MAVI-nummer i PDF-en.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              Row(
                children: [
                  TextButton(onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))), child: const Text('Velg alle')),
                  TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Fjern alle')),
                ],
              ),
              ..._buildReviewGroups(),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _publishing || _staged.isEmpty || _selected.isEmpty ? null : _publish,
              icon: _publishing
                  ? SizedBox(width: 18, height: 18, child: DriftProLoadingIndicator(size: 18))
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text('Publiser $selectedCount rute(r) til sjåfører'),
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(int vehicles, int selected) {
    final ok = selected > 0 && _missingPhoneCount == 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (ok ? Colors.green : Colors.orange).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ok ? 'Klar til publisering' : 'Kontroller før du publiserer',
            style: TextStyle(fontWeight: FontWeight.w800, color: ok ? Colors.green.shade800 : Colors.orange.shade900),
          ),
          const SizedBox(height: 4),
          Text('$_staged.length PDF i kø · $vehicles MAVI-bil · $selected valgt for sending', style: const TextStyle(fontSize: 12)),
          if (_missingPhoneCount > 0)
            Text(
              '$_missingPhoneCount bil uten telefon — opprett sjåførportal under bedriften først',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildReviewGroups() {
    return _byVehicle.entries.map((group) {
      final routes = group.value;
      final first = routes.first;
      final row = _rowForShare(first);
      final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
      final partner = row?.partner.name ?? 'Partner';
      final vid = first.partnerVehicleId;
      final portal = vid != null ? _portalByVehicle[vid] : null;
      final hasPhone = (portal?.phone ?? row?.vehicle.phone ?? '').trim().length >= 8;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$partner · $mavi · ${routes.length} PDF',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                Icon(
                  hasPhone ? Icons.sms_outlined : Icons.sms_failed_outlined,
                  size: 18,
                  color: hasPhone ? Colors.green : Colors.red,
                ),
              ],
            ),
          ),
          ...routes.map((share) {
            final checked = _selected.contains(share.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: checked ? null : Colors.grey.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      value: checked,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        share.title ?? share.pdfStoragePath.split('/').last,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                    if (checked) ...[
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                            label: const Text('Vis PDF'),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                            icon: const Icon(Icons.download_outlined, size: 16),
                            label: const Text('Last ned'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _shiftByShare[share.id],
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Skift (endres før send)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: _shifts
                            .map((s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _shiftByShare[share.id] = v);
                        },
                      ),
                      RoutePdfShiftSuggestionButton(
                        shifts: _shifts,
                        suggestedShiftId: _pdfSuggestedShiftByShare[share.id],
                        selectedShiftId: _shiftByShare[share.id],
                        onApply: () => setState(
                          () => _shiftByShare[share.id] = _pdfSuggestedShiftByShare[share.id]!,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Rutedato', style: TextStyle(fontSize: 12)),
                              subtitle: Text(
                                DateFormat('EEE d.M.y', 'nb').format(_routeDayFor(share.id)),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              trailing: const Icon(Icons.event, size: 20),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _routeDayFor(share.id),
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked == null) return;
                                final t = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);
                                await PartnerService.updateShareRouteDay(
                                  share: share,
                                  day: picked,
                                  startHour: t.hour,
                                  startMinute: t.minute,
                                );
                                if (mounted) setState(() => _dateByShare[share.id] = DateTime(picked.year, picked.month, picked.day));
                              },
                            ),
                          ),
                          Expanded(
                            child: ListTile(
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
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      );
    }).toList();
  }
}
