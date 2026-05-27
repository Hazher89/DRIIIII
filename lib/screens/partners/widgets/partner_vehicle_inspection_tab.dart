import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'partner_ui.dart';

/// Bilkontroll: mal (reppe, dekk, …), avvik, arkiv og oppfølging.
class PartnerVehicleInspectionTab extends StatefulWidget {
  final Partner partner;
  final List<PartnerVehicle> vehicles;

  const PartnerVehicleInspectionTab({
    super.key,
    required this.partner,
    required this.vehicles,
  });

  @override
  State<PartnerVehicleInspectionTab> createState() => _PartnerVehicleInspectionTabState();
}

class _PartnerVehicleInspectionTabState extends State<PartnerVehicleInspectionTab> {
  List<PartnerVehicleInspection> _archive = [];
  List<PartnerVehicleInspection> _followUps = [];
  bool _loading = true;
  String? _selectedVehicleId;
  final _deviationNotes = TextEditingController();
  final _checklistValues = <String, dynamic>{};
  bool _hasDeviation = false;
  DateTime? _nextInspection;
  DateTime? _followUpDue;
  bool _saving = false;

  int _countNotChecked(PartnerVehicleInspection ins) {
    var c = 0;
    for (final f in VehicleInspectionTemplate.items) {
      if (f.type != InspectionFieldType.okAvvik) continue;
      final raw = ins.checklist[f.key];
      if (raw is String && raw == 'not_checked') c++;
    }
    return c;
  }

  List<PartnerVehicle> get _regVehicles => widget.vehicles
      .where((v) =>
          v.vehicleKind == 'registration' || MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .toList();

  List<PartnerVehicle> get _maviVehicles => widget.vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .toList();

  @override
  void initState() {
    super.initState();
    _resetChecklist();
    _load();
  }

  @override
  void dispose() {
    _deviationNotes.dispose();
    super.dispose();
  }

  void _resetChecklist() {
    _checklistValues.clear();
    for (final f in VehicleInspectionTemplate.items) {
      _checklistValues[f.key] = f.type == InspectionFieldType.okAvvik ? 'ok' : '';
    }
    _hasDeviation = false;
    _nextInspection = null;
    _followUpDue = DateTime.now().add(const Duration(days: 14));
    _deviationNotes.clear();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final archive = await PartnerService.fetchVehicleInspections(widget.partner.id);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final followUps = await PartnerService.fetchOpenInspectionFollowUps(
      companyId: widget.partner.companyId,
      assigneeProfileId: uid,
    );
    if (mounted) {
      setState(() {
        _archive = archive;
        _followUps = followUps;
        _loading = false;
      });
    }
  }

  PartnerVehicle? get _selectedVehicle {
    if (_selectedVehicleId == null) return null;
    for (final v in widget.vehicles) {
      if (v.id == _selectedVehicleId) return v;
    }
    return null;
  }

  String _vehicleLabel(PartnerVehicle v) {
    if (MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode)) {
      return 'Reg ${MaviUnitCodes.plateFromRegistrationUnit(v.unitCode)}';
    }
    final reg = v.registrationNumber == MaviUnitCodes.regNrPlaceholder ? '' : v.registrationNumber;
    return '${MaviUnitCodes.normalize(v.unitCode)}${reg.isNotEmpty ? ' · $reg' : ''}';
  }

  bool _checklistImpliesDeviation() {
    for (final f in VehicleInspectionTemplate.items) {
      if (f.type == InspectionFieldType.okAvvik) {
        if (_checklistValues[f.key] == 'avvik') return true;
      }
      if (f.key.startsWith('dekk_')) {
        final mm = double.tryParse('${_checklistValues[f.key]}'.replaceAll(',', '.'));
        if (mm != null && mm < 3.0) return true;
      }
    }
    return false;
  }

  Future<void> _saveInspection() async {
    final v = _selectedVehicle;
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg bil (reg.nr eller MAVI) først.')),
      );
      return;
    }
    final implied = _checklistImpliesDeviation();
    if (_hasDeviation || implied) {
      if (_deviationNotes.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beskriv avviket før lagring.')),
        );
        return;
      }
      if (_followUpDue == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sett dato for oppfølging av avvik.')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final reg = MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode)
          ? MaviUnitCodes.plateFromRegistrationUnit(v.unitCode)
          : (v.registrationNumber == MaviUnitCodes.regNrPlaceholder ? null : v.registrationNumber);
      final draft = PartnerVehicleInspection(
        id: '',
        partnerId: widget.partner.id,
        companyId: widget.partner.companyId,
        partnerVehicleId: v.id,
        registrationNumber: reg,
        unitCode: MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode) ? null : v.unitCode,
        inspectedAt: DateTime.now(),
        checklist: Map<String, dynamic>.from(_checklistValues),
        hasDeviation: _hasDeviation || implied,
        deviationNotes: _deviationNotes.text.trim().isEmpty ? null : _deviationNotes.text.trim(),
        deviationAssignee: (_hasDeviation || implied) ? uid : null,
        nextInspectionAt: _nextInspection,
        followUpDueAt: (_hasDeviation || implied) ? _followUpDue : null,
        createdAt: DateTime.now(),
      );
      await PartnerService.saveVehicleInspection(draft);
      _resetChecklist();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kontroll lagret og arkivert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _ackFollowUp(PartnerVehicleInspection ins) async {
    await PartnerService.acknowledgeInspectionFollowUp(ins.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final vehicleOptions = [..._regVehicles, ..._maviVehicles];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        PartnerHeroBanner(
          compact: true,
          title: 'Bilkontroll',
          subtitle: 'Utstyrskontroll per bil — avvik arkiveres og varsler om oppfølging.',
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fact_check_outlined, color: Colors.white),
          ),
        ),
        if (_followUps.isNotEmpty)
          PartnerSectionCard(
            icon: Icons.warning_amber_rounded,
            iconColor: DriftProTheme.warning,
            title: 'Åpne avvik (${_followUps.length})',
            children: _followUps.map((f) {
              final overdue = f.followUpOverdue;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: (overdue ? DriftProTheme.error : DriftProTheme.warning).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
                  border: Border.all(
                    color: (overdue ? DriftProTheme.error : DriftProTheme.warning).withValues(alpha: 0.25),
                  ),
                ),
                child: ListTile(
                  title: Text(
                    '${f.registrationNumber ?? f.unitCode ?? "Bil"} — oppfølging',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${f.deviationNotes ?? "Avvik"}\n'
                    'Frist: ${f.followUpDueAt!.day}.${f.followUpDueAt!.month}.${f.followUpDueAt!.year}'
                    '${overdue ? " ⚠ Forfalt" : ""}',
                  ),
                  trailing: FilledButton(
                    onPressed: () => _ackFollowUp(f),
                    style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                    child: const Text('Utført'),
                  ),
                ),
              );
            }).toList(),
          ),
        PartnerSectionCard(
          icon: Icons.checklist_rtl_outlined,
          title: 'Ny kontroll',
          children: [
            DropdownButtonFormField<String>(
              value: _selectedVehicleId,
              decoration: const InputDecoration(labelText: 'Velg bil (reg.nr eller MAVI)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('— velg —')),
                ...vehicleOptions.map(
                  (v) => DropdownMenuItem(value: v.id, child: Text(_vehicleLabel(v))),
                ),
              ],
              onChanged: (id) => setState(() => _selectedVehicleId = id),
            ),
            const SizedBox(height: 12),
            Text('Utstyrskontroll-mal', style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            ...VehicleInspectionTemplate.items.map(_fieldWidget),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Avvik registrert'),
          subtitle: const Text('Krever beskrivelse og oppfølging'),
          value: _hasDeviation || _checklistImpliesDeviation(),
          onChanged: (v) => setState(() => _hasDeviation = v),
        ),
        if (_hasDeviation || _checklistImpliesDeviation()) ...[
          TextField(
            controller: _deviationNotes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Avvik — beskrivelse *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Oppfølging innen'),
            subtitle: Text(
              _followUpDue != null
                  ? '${_followUpDue!.day}.${_followUpDue!.month}.${_followUpDue!.year}'
                  : 'Velg dato',
            ),
            trailing: const Icon(Icons.event),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _followUpDue ?? DateTime.now().add(const Duration(days: 14)),
                firstDate: DateTime.now(),
                lastDate: DateTime(2040),
              );
              if (d != null) setState(() => _followUpDue = d);
            },
          ),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Neste planlagte kontroll'),
          subtitle: Text(
            _nextInspection != null
                ? '${_nextInspection!.day}.${_nextInspection!.month}.${_nextInspection!.year}'
                : 'Valgfritt',
          ),
          trailing: const Icon(Icons.calendar_month),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _nextInspection ?? DateTime.now().add(const Duration(days: 90)),
              firstDate: DateTime.now(),
              lastDate: DateTime(2040),
            );
            if (d != null) setState(() => _nextInspection = d);
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _saveInspection,
          style: FilledButton.styleFrom(
            backgroundColor: DriftProTheme.primaryGreen,
            minimumSize: const Size(double.infinity, 48),
          ),
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Lagre og arkiver kontroll'),
        ),
          ],
        ),
        PartnerSectionCard(
          icon: Icons.inventory_2_outlined,
          title: 'Arkiv',
          trailing: PartnerStatusBadge(
            label: '${_archive.length}',
            color: DriftProTheme.accentBlue,
          ),
          children: [
            if (_archive.isEmpty)
              PartnerEmptyState(
                icon: Icons.archive_outlined,
                title: 'Ingen kontroller arkivert',
                subtitle: 'Lagrede kontroller vises her med status og avvik.',
              )
            else
              ..._archive.take(20).map((a) {
                    final notCheckedCount = _countNotChecked(a);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
                  ),
                  child: ListTile(
                    title: Text(
                      '${a.registrationNumber ?? a.unitCode ?? "Bil"} · '
                      '${a.inspectedAt.day}.${a.inspectedAt.month}.${a.inspectedAt.year}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                          a.hasDeviation
                              ? 'Avvik: ${a.deviationNotes ?? "—"}'
                              : notCheckedCount > 0
                                  ? 'Kan ikke sjekkes: $notCheckedCount felt'
                                  : 'OK — ingen avvik',
                    ),
                    trailing: a.hasDeviation
                        ? Icon(Icons.warning_amber, color: Colors.orange.shade700)
                            : notCheckedCount > 0
                                ? const Icon(Icons.help_outline, color: Colors.grey)
                                : const Icon(Icons.check_circle, color: Colors.green),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _fieldWidget(VehicleInspectionField f) {
    switch (f.type) {
      case InspectionFieldType.okAvvik:
        final val = _checklistValues[f.key] as String? ?? 'ok';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text(f.label)),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ok', label: Text('OK')),
                  ButtonSegment(value: 'avvik', label: Text('Avvik')),
                  ButtonSegment(value: 'not_checked', label: Text('Kan ikke sjekkes')),
                ],
                selected: {val},
                onSelectionChanged: (s) {
                  setState(() {
                    _checklistValues[f.key] = s.first;
                    if (_checklistImpliesDeviation()) _hasDeviation = true;
                  });
                },
              ),
            ],
          ),
        );
      case InspectionFieldType.number:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: f.label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              setState(() {
                _checklistValues[f.key] = v;
                if (_checklistImpliesDeviation()) _hasDeviation = true;
              });
            },
          ),
        );
      case InspectionFieldType.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            maxLines: 2,
            decoration: InputDecoration(
              labelText: f.label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _checklistValues[f.key] = v,
          ),
        );
    }
  }
}
