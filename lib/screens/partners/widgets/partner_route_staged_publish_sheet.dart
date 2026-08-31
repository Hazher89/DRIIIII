import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/notification/publish_action_labels.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../models/notification_channel.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/route_shift_resolver.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import 'partner_route_pdf_actions.dart';
import 'route_calendar_chip.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Full oversikt over kladd-ruter før SMS/publisering til sjåfører.
class PartnerRouteStagedPublishSheet extends StatefulWidget {
  final String companyId;
  final List<FleetPartnerVehicleRow> fleet;
  final List<FleetShiftDefinition> shifts;
  final DateTime routeDate;

  const PartnerRouteStagedPublishSheet({
    super.key,
    required this.companyId,
    required this.fleet,
    required this.shifts,
    required this.routeDate,
  });

  @override
  State<PartnerRouteStagedPublishSheet> createState() => _PartnerRouteStagedPublishSheetState();
}

class _PartnerRouteStagedPublishSheetState extends State<PartnerRouteStagedPublishSheet> {
  bool _loading = true;
  bool _publishing = false;
  List<PartnerRouteShare> _staged = const [];
  Map<String, PartnerPortalAccount> _portalByVehicle = {};
  final Set<String> _selected = {};
  final Map<String, String> _shiftByShare = {};
  final Map<String, String> _pdfSuggestedShiftByShare = {};
  final Map<String, TimeOfDay> _startByShare = {};
  final Map<String, DateTime> _dateByShare = {};
  final Map<String, TextEditingController> _noteCtrls = {};
  String _publishLabel = 'Publiser og send varsel';
  NotificationChannel _channel = NotificationChannel.both;

  DateTime _routeDayFor(String shareId) {
    final cached = _dateByShare[shareId];
    if (cached != null) return cached;
    final share = _staged.where((s) => s.id == shareId).firstOrNull;
    if (share == null) return widget.routeDate;
    return PartnerService.routeDayForShare(share);
  }

  FleetPartnerVehicleRow? _rowForShare(PartnerRouteShare share) {
    final vid = share.partnerVehicleId;
    if (vid == null) return null;
    for (final r in widget.fleet) {
      if (r.vehicle.id == vid) return r;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadPublishLabels();
  }

  Future<void> _loadPublishLabels() async {
    try {
      final label = await PublishActionLabels.singleRoutePublishLabel(widget.companyId);
      final ch = await PublishActionLabels.singleRouteChannel(widget.companyId);
      if (mounted) {
        setState(() {
          _publishLabel = label;
          _channel = ch;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final staged = await PartnerService.fetchStagedRouteShares(widget.companyId);
      final portals = <String, PartnerPortalAccount>{};
      final partnerIds = widget.fleet.map((r) => r.partner.id).toSet();
      for (final pid in partnerIds) {
        for (final a in await PartnerService.fetchPortalAccounts(pid)) {
          if (a.partnerVehicleId != null) portals[a.partnerVehicleId!] = a;
        }
      }
      final shiftItems = widget.shifts.where((s) => !s.isAvailability).toList();
      final defaultShift = shiftItems
          .where((s) => s.shiftKind == 'route_ops')
          .map((e) => e.id)
          .firstOrNull ??
          (shiftItems.isNotEmpty ? shiftItems.first.id : null);

      final shiftById = <String, String>{};
      final pdfSuggested = <String, String>{};
      for (final s in staged) {
        final pdfText = await RouteShiftResolver.loadPdfTextForShare(s);
        final sid = await RouteShiftResolver.resolveShiftIdForStagedShare(
          share: s,
          allShifts: widget.shifts,
          pdfText: pdfText,
        );
        if (sid != null && sid.isNotEmpty) {
          shiftById[s.id] = sid;
          pdfSuggested[s.id] = sid;
        } else {
          shiftById[s.id] = s.shiftId ?? defaultShift ?? '';
        }
      }

      if (!mounted) return;
      setState(() {
        _staged = staged;
        _portalByVehicle = portals;
        _selected
          ..clear()
          ..addAll(staged.map((s) => s.id));
        _dateByShare.clear();
        for (final s in staged) {
          _dateByShare[s.id] = PartnerService.routeDayForShare(s);
          _shiftByShare[s.id] = shiftById[s.id] ?? defaultShift ?? '';
          _startByShare[s.id] = s.routeStartAt != null
              ? TimeOfDay.fromDateTime(s.routeStartAt!.toLocal())
              : const TimeOfDay(hour: 6, minute: 0);
          _noteCtrls[s.id] = TextEditingController(text: s.notes ?? '');
        }
        _pdfSuggestedShiftByShare
          ..clear()
          ..addAll(pdfSuggested);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _missingPhoneCount {
    var n = 0;
    final seen = <String>{};
    for (final id in _selected) {
      final share = _staged.where((s) => s.id == id).firstOrNull;
      if (share == null) continue;
      final vid = share.partnerVehicleId;
      if (vid == null || !seen.add(vid)) continue;
      final row = _rowForShare(share);
      final portal = _portalByVehicle[vid];
      final phone = (portal?.phone ?? row?.vehicle.phone ?? '').trim();
      if (phone.length < 8) n++;
    }
    return n;
  }

  Future<void> _publish() async {
    if (_selected.isEmpty) return;
    final missingShift = _selected.where((id) => (_shiftByShare[id] ?? '').isEmpty);
    if (missingShift.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle valgte ruter må ha skift.')),
      );
      return;
    }

    final lines = <String>[];
    for (final id in _selected) {
      final share = _staged.firstWhere((s) => s.id == id);
      final row = _rowForShare(share);
      final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
      final partner = row?.partner.name ?? '';
      final shiftName = widget.shifts.where((s) => s.id == _shiftByShare[id]).map((s) => s.name).firstOrNull ?? '—';
      final t = _startByShare[id] ?? const TimeOfDay(hour: 6, minute: 0);
      final dayLabel = DateFormat('d.M.y').format(_routeDayFor(id));
      lines.add('• $dayLabel · $partner · $mavi — $shiftName, start ${t.format(context)}');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_publishLabel?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_selected.length} rute(r) sendes til sjåførportal. '
                'Sjåfører får SMS og må logge inn for å akseptere.',
              ),
              if (_missingPhoneCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠ $_missingPhoneCount bil mangler telefon — får ikke SMS.',
                  style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 10),
              const Text('Tildeling:', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ...lines.take(15).map((l) => Text(l, style: const TextStyle(fontSize: 12))),
              if (lines.length > 15) Text('… og ${lines.length - 15} flere'),
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
    if (ok != true || !mounted) return;

    setState(() => _publishing = true);
    try {
      for (final id in _selected) {
        final note = _noteCtrls[id]?.text.trim();
        await PartnerService.updateRouteShareFields(id, {
          if (note != null && note.isNotEmpty) 'notes': note,
          'shift_id': _shiftByShare[id],
        });
      }
      final map = {for (final id in _selected) id: _shiftByShare[id]!};
      final starts = <String, DateTime?>{};
      for (final id in _selected) {
        final t = _startByShare[id] ?? const TimeOfDay(hour: 6, minute: 0);
        final day = _routeDayFor(id);
        starts[id] = DateTime(day.year, day.month, day.day, t.hour, t.minute);
      }
      final notify = _channel != NotificationChannel.none;
      await PartnerService.dispatchRouteShares(
        companyId: widget.companyId,
        shareIdToShiftId: map,
        date: _selected.isNotEmpty ? _routeDayFor(_selected.first) : widget.routeDate,
        shareIdToStartAt: starts,
        notifyDriver: notify,
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              PublishActionLabels.successMessage(
                routeCount: map.length,
                channel: _channel,
                notifyDriver: notify,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 320, child: const DriftProLoadingCenter());
    }

    final shiftItems = widget.shifts.where((s) => !s.isAvailability).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text('Publiser kladd-ruter', style: DriftProTheme.headingMd),
          Text(
            () {
              final groups = PartnerService.groupSharesByRouteDay(_staged);
              final datePart = groups.length <= 1
                  ? 'Rutedato: ${DateFormat('d. MMM yyyy', 'nb').format(groups.keys.firstOrNull ?? widget.routeDate)}'
                  : '${groups.length} ulike datoer i kø';
              return '$datePart · ${_staged.length} i kø · ${_selected.length} valgt';
            }(),
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_staged.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Ingen kladd-ruter. Last opp PDF via kalender eller masseimport.'),
            )
          else ...[
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))),
                  child: const Text('Velg alle'),
                ),
                TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Fjern alle')),
              ],
            ),
            ..._staged.map((share) {
              final row = _rowForShare(share);
              final mavi = row != null ? MaviUnitCodes.normalize(row.vehicle.unitCode) : '?';
              final partner = row?.partner.name ?? 'Partner';
              final checked = _selected.contains(share.id);
              final vid = share.partnerVehicleId;
              final portal = vid != null ? _portalByVehicle[vid] : null;
              final hasPhone = (portal?.phone ?? row?.vehicle.phone ?? '').trim().length >= 8;
              final start = _startByShare[share.id] ?? const TimeOfDay(hour: 6, minute: 0);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CheckboxListTile(
                        value: checked,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('$partner · $mavi', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          share.title ?? share.pdfStoragePath.split('/').last,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: Icon(
                          hasPhone ? Icons.sms_outlined : Icons.sms_failed_outlined,
                          color: hasPhone ? Colors.green : Colors.red,
                        ),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(share.id);
                          } else {
                            _selected.remove(share.id);
                          }
                        }),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('Vis PDF'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => PartnerRoutePdfActions.openPdf(context, share),
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: const Text('Last ned'),
                          ),
                        ],
                      ),
                      if (checked && shiftItems.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Skift (endres før send)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          initialValue: _shiftByShare[share.id],
                          items: shiftItems.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _shiftByShare[share.id] = v);
                          },
                        ),
                        RoutePdfShiftSuggestionButton(
                          shifts: widget.shifts,
                          suggestedShiftId: _pdfSuggestedShiftByShare[share.id],
                          selectedShiftId: _shiftByShare[share.id],
                          onApply: () => setState(
                            () => _shiftByShare[share.id] = _pdfSuggestedShiftByShare[share.id]!,
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Starttid'),
                          subtitle: Text(start.format(context), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          trailing: const Icon(Icons.schedule),
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: start);
                            if (picked != null) setState(() => _startByShare[share.id] = picked);
                          },
                        ),
                        TextField(
                          controller: _noteCtrls[share.id],
                          decoration: const InputDecoration(
                            labelText: 'Notat til sjåfør',
                            border: OutlineInputBorder(),
                          ),
                          minLines: 2,
                          maxLines: 3,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _publishing || _selected.isEmpty ? null : _publish,
              style: FilledButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                minimumSize: const Size(double.infinity, 52),
              ),
              icon: _publishing
                  ? SizedBox(width: 20, height: 20, child: DriftProLoadingIndicator(size: 20))
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text('$_publishLabel (${_selected.length})'),
            ),
          ],
        ],
      ),
    );
  }
}
