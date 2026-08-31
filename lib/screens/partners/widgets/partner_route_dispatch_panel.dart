import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/postal_code_registry.dart';
import '../../../core/services/partner/fleet_shift_filters.dart';
import '../../../core/services/partner/route_shift_resolver.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/fleet_shift.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/route_notify_prefs.dart';
import 'route_publish_notify_buttons.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Steg 2: Hver rute-PDF får eget skift før sending til sjåfør.
class PartnerRouteDispatchPanel extends StatefulWidget {
  final VoidCallback? onDispatched;
  final List<FleetPartnerVehicleRow> fleet;

  const PartnerRouteDispatchPanel({
    super.key,
    this.onDispatched,
    this.fleet = const [],
  });

  @override
  State<PartnerRouteDispatchPanel> createState() => _PartnerRouteDispatchPanelState();
}

class _PartnerRouteDispatchPanelState extends State<PartnerRouteDispatchPanel> {
  bool _loading = true;
  bool _sending = false;
  List<PartnerRouteShare> _staged = [];
  final Set<String> _selected = {};
  final Map<String, String> _shiftByShare = {};
  final Map<String, TimeOfDay?> _startByShare = {};
  List<FleetShiftDefinition> _shifts = [];
  DateTime _sendDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) return;
      await PartnerService.ensureCanonicalFleetShifts(cid); // Oppdaterer til standard skift ved behov
      final shifts = await PartnerService.fetchFleetShifts(cid);
      final staged = await PartnerService.fetchStagedRouteShares(cid);
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
        } else {
          shiftById[s.id] = '';
        }
      }
      if (mounted) {
        setState(() {
          _shifts = shifts;
          _staged = staged;
          _selected
            ..clear()
            ..addAll(staged.map((s) => s.id));
          _shiftByShare
            ..clear()
            ..addAll(shiftById);
          for (final s in staged) {
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
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _vehicleLabel(PartnerRouteShare share) {
    for (final row in widget.fleet) {
      if (row.vehicle.id == share.partnerVehicleId) {
        return MaviUnitCodes.normalize(row.vehicle.unitCode);
      }
    }
    return 'Ukjent MAVI';
  }

  String? _partnerName(PartnerRouteShare share) {
    for (final row in widget.fleet) {
      if (row.vehicle.id == share.partnerVehicleId) return row.partner.name;
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

  Future<void> _sendWithPrefs(RouteNotifyPrefs? prefs) async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én rute å sende.')),
      );
      return;
    }
    final missingShift = _selected.where((id) => !_shiftByShare.containsKey(id) || _shiftByShare[id]!.isEmpty);
    if (missingShift.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hver valgte rute må ha skift.')),
      );
      return;
    }
    final notifyPrefs = prefs ?? RouteNotifyPrefs.none;
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) return;
    setState(() => _sending = true);
    try {
      final map = {for (final id in _selected) id: _shiftByShare[id]!};
      final starts = <String, DateTime?>{};
      for (final id in _selected) {
        final t = _startByShare[id];
        if (t != null) {
          starts[id] = DateTime(
            _sendDate.year,
            _sendDate.month,
            _sendDate.day,
            t.hour,
            t.minute,
          );
        }
      }
      await PartnerService.dispatchRouteShares(
        companyId: cid,
        shareIdToShiftId: map,
        date: _sendDate,
        shareIdToStartAt: starts,
        notifyDriver: notifyPrefs.anyEnabled,
        notifyPrefs: notifyPrefs,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(notifyPrefs.successMessage(map.length))),
        );
      }
      widget.onDispatched?.call();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke sende: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _shiftDropdown(String shareId) {
    return DropdownButtonFormField<String>(
      initialValue: _shiftByShare[shareId],
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Skift for denne ruten',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: _shifts
          .map(
            (s) => DropdownMenuItem(
              value: s.id,
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: s.color, radius: 6),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _shiftByShare[shareId] = v);
      },
    );
  }

  Widget _startTimePicker(String shareId) {
    final t = _startByShare[shareId] ?? const TimeOfDay(hour: 6, minute: 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Starttid', style: TextStyle(fontSize: 12)),
      subtitle: Text(
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(Icons.schedule, size: 20),
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: t);
        if (picked != null) setState(() => _startByShare[shareId] = picked);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: const DriftProLoadingCenter(),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: DriftProTheme.primaryGreen.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.send_outlined, color: DriftProTheme.primaryGreen),
                const SizedBox(width: 8),
                Expanded(child: Text('Send til sjåfør', style: DriftProTheme.headingSm)),
                Text('${_staged.length} PDF', style: DriftProTheme.caption),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Hver rute-PDF får eget skift og starttid. Bil-eier får SMS og ser alt i partner-portalen.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _sendDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 7)),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (d != null) setState(() => _sendDate = d);
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Rutedato: ${DateFormat('d. MMM yyyy', 'nb').format(_sendDate)}'),
            ),
            const SizedBox(height: 10),
            if (_staged.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Ingen ruter klare. Bruk «Fordel PDF» først.',
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _selected.addAll(_staged.map((s) => s.id))),
                    child: const Text('Velg alle'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected.clear()),
                    child: const Text('Fjern alle'),
                  ),
                ],
              ),
              ..._byVehicle.entries.map((group) {
                final vehicleId = group.key;
                final routes = group.value;
                final first = routes.first;
                final partner = _partnerName(first);
                final mavi = _vehicleLabel(first);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        '${partner ?? 'Partner'} · $mavi · ${routes.length} rute(r)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    ...routes.map((share) {
                      final checked = _selected.contains(share.id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
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
                                _shiftDropdown(share.id),
                                _startTimePicker(share.id),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
            const SizedBox(height: 8),
            RoutePublishNotifyButtons(
              busy: _sending || _staged.isEmpty,
              compact: true,
              onPublish: _selected.isEmpty ? (_) async {} : _sendWithPrefs,
            ),
          ],
        ),
      ),
    );
  }
}
