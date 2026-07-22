import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/hms/hms_pdf_export_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/vehicle_inspection_pdf.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'partner_modern_ui.dart';
import 'partner_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

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
  final _archiveSearch = TextEditingController();
  final _checklistValues = <String, dynamic>{};
  bool _hasDeviation = false;
  DateTime? _nextInspection;
  DateTime? _followUpDue;
  bool _saving = false;
  String? _inspectorName;
  String? _lastSavedInspectionId;

  static final _stampFmt = DateFormat('dd.MM.yyyy HH:mm');

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
    _loadInspectorName();
    _load();
  }

  Future<void> _loadInspectorName() async {
    final profile = await SupabaseService.fetchCurrentUserProfile();
    if (mounted) setState(() => _inspectorName = profile?.fullName);
  }

  String _formatStamp(DateTime at, {String? name}) {
    final who = name?.trim().isNotEmpty == true ? name! : 'Bruker';
    return 'Kontroll stempling · $who · ${_stampFmt.format(at.toLocal())}';
  }

  @override
  void dispose() {
    _deviationNotes.dispose();
    _archiveSearch.dispose();
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
      final stampedAt = DateTime.now();
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
        inspectedAt: stampedAt,
        checklist: Map<String, dynamic>.from(_checklistValues),
        hasDeviation: _hasDeviation || implied,
        deviationNotes: _deviationNotes.text.trim().isEmpty ? null : _deviationNotes.text.trim(),
        deviationAssignee: (_hasDeviation || implied) ? uid : null,
        nextInspectionAt: _nextInspection,
        followUpDueAt: (_hasDeviation || implied) ? _followUpDue : null,
        createdAt: DateTime.now(),
      );
      final saved = await PartnerService.saveVehicleInspection(
        draft,
        partner: widget.partner,
        inspectorName: _inspectorName,
      );
      if (!mounted) return;
      setState(() {
        _resetChecklist();
        _selectedVehicleId = null;
        _lastSavedInspectionId = saved.id;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kontroll arkivert med PDF. ${_formatStamp(stampedAt, name: _inspectorName)}',
          ),
          action: SnackBarAction(
            label: 'Last ned PDF',
            onPressed: () => _exportPdf(saved),
          ),
        ),
      );
      await _offerPdfExport(saved);
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

  Future<void> _exportPdf(PartnerVehicleInspection inspection) async {
    await HmsPdfExportService.runWithFeedback(
      context,
      fileName: VehicleInspectionPdf.fileNameFor(inspection),
      generate: () async {
        final stored = inspection.pdfStoragePath?.trim();
        if (stored != null && stored.isNotEmpty) {
          final bytes = await PartnerService.downloadInspectionPdfBytes(
            stored,
            companyId: inspection.companyId,
          );
          if (bytes != null && bytes.isNotEmpty) return bytes;
        }
        return VehicleInspectionPdf.generate(
          inspection: inspection,
          partner: widget.partner,
          inspectorName: inspection.inspectedByName ?? _inspectorName,
        );
      },
    );
  }

  Future<void> _offerPdfExport(PartnerVehicleInspection inspection) async {
    if (!mounted) return;
    final export = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontroll arkivert'),
        content: const Text(
          'PDF-rapporten er registrert for denne bilen og datoen, '
          'og kan lastes ned når som helst under Arkiv.\n\n'
          'Vil du laste den ned nå?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Senere'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Last ned PDF'),
          ),
        ],
      ),
    );
    if (export == true && mounted) {
      await _exportPdf(inspection);
    }
  }

  Future<void> _ackFollowUp(PartnerVehicleInspection ins) async {
    await PartnerService.acknowledgeInspectionFollowUp(ins.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DriftProLoadingCenter();
    }

    final vehicleOptions = [..._maviVehicles, ..._regVehicles];
    final lastByVehicle =
        PartnerVehicleInspection.latestByVehicleId(widget.vehicles, _archive);
    final deviationCount = _archive.where((a) => a.hasDeviation).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      children: [
        PartnerModernPageHeader(
          title: 'Bilkontroll',
          subtitle: [
            widget.partner.tradeName?.trim().isNotEmpty == true
                ? widget.partner.tradeName!.trim()
                : widget.partner.name,
            '${vehicleOptions.length} bil${vehicleOptions.length == 1 ? '' : 'er'}',
          ].join(' · '),
          trailing: IconButton(
            tooltip: 'Oppdater',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: _load,
          ),
        ),
        PartnerModernKpiGrid(
          items: [
            ('Kontroller', '${_archive.length}'),
            ('Avvik', '$deviationCount'),
            ('Oppfølging', _followUps.isEmpty ? 'Ingen' : '${_followUps.length}'),
            ('Biler', '${vehicleOptions.length}'),
          ],
        ),
        const SizedBox(height: 8),
        if (_followUps.isNotEmpty) _followUpSection(context),
        PartnerModernSection(
          title: 'Velg bil',
          subtitle: vehicleOptions.isEmpty
              ? 'Registrer MAVI eller reg.nr under Oversikt først'
              : 'Trykk bilen du skal kontrollere — sist kontroll vises til høyre',
          initiallyExpanded: true,
          children: [
            if (vehicleOptions.isEmpty)
              PartnerEmptyState(
                icon: Icons.directions_car_outlined,
                title: 'Ingen biler registrert',
                subtitle: 'Legg til MAVI eller skiltnummer under fanen Oversikt.',
              )
            else
              _vehiclePicker(context, vehicleOptions, lastByVehicle),
          ],
        ),
        if (_selectedVehicle != null) ...[
          PartnerModernSection(
            title: 'Kontrollskjema',
            subtitle: _vehicleLabel(_selectedVehicle!),
            initiallyExpanded: true,
            children: [
              ...VehicleInspectionTemplate.items.map(_fieldWidget),
              const SizedBox(height: 8),
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
                  trailing: const Icon(Icons.event_outlined),
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
                trailing: const Icon(Icons.calendar_month_outlined),
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
              const SizedBox(height: 12),
              _stampPreview(),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _saveInspection,
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  minimumSize: const Size(double.infinity, 48),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: DriftProLoadingIndicator(size: 18),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Lagre og arkiver kontroll'),
              ),
            ],
          ),
        ],
        PartnerModernSection(
          title: 'Arkiv',
          subtitle: 'Alle lagrede kontroller for bedriften',
          trailing: Text(
            '${_archive.length}',
            style: TextStyle(fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context)),
          ),
          children: [
            if (_archive.isEmpty)
              PartnerEmptyState(
                icon: Icons.archive_outlined,
                title: 'Ingen kontroller ennå',
                subtitle: 'Lagrede kontroller vises her med status, dato og PDF.',
              )
            else ...[
              TextField(
                controller: _archiveSearch,
                decoration: InputDecoration(
                  hintText: 'Søk reg.nr, MAVI, kontrollør…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _archiveSearch.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _archiveSearch.clear();
                            setState(() {});
                          },
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              ..._archiveCards(context),
            ],
          ],
        ),
      ],
    );
  }

  Widget _followUpSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: DriftProTheme.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DriftProTheme.warning.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: DriftProTheme.warning, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Åpne avvik (${_followUps.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            ..._followUps.map((f) {
              final overdue = f.followUpOverdue;
              return Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                decoration: BoxDecoration(
                  color: PartnerModernUi.surface(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (overdue ? DriftProTheme.error : DriftProTheme.warning)
                        .withValues(alpha: 0.35),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    f.vehicleLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${f.deviationNotes ?? "Avvik"}\n'
                    'Frist: ${f.followUpDueAt!.day}.${f.followUpDueAt!.month}.${f.followUpDueAt!.year}'
                    '${overdue ? " · Forfalt" : ""}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: FilledButton(
                    onPressed: () => _ackFollowUp(f),
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Utført'),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _vehiclePicker(
    BuildContext context,
    List<PartnerVehicle> vehicles,
    Map<String, PartnerVehicleInspection> lastByVehicle,
  ) {
    return Column(
      children: vehicles.map((v) {
        final selected = _selectedVehicleId == v.id;
        final last = lastByVehicle[v.id];
        final isMavi = !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode) &&
            v.vehicleKind != 'registration';
        final code = isMavi ? MaviUnitCodes.compactLabel(MaviUnitCodes.normalize(v.unitCode)) : null;
        final statusLabel = _lastInspectionLabel(last);
        final statusColor = _lastInspectionColor(last);

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: selected
                ? DriftProTheme.primaryGreen.withValues(alpha: 0.08)
                : PartnerModernUi.border(context).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _selectedVehicleId = v.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? DriftProTheme.primaryGreen.withValues(alpha: 0.5)
                        : PartnerModernUi.border(context),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    if (code != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF15803D).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Color(0xFF15803D),
                          ),
                        ),
                      )
                    else
                      Icon(Icons.pin_outlined, size: 18, color: PartnerModernUi.muted(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vehicleLabel(v),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: PartnerModernUi.textPrimary(context),
                            ),
                          ),
                          if (v.driverName?.trim().isNotEmpty == true)
                            Text(
                              v.driverName!.trim(),
                              style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle, size: 18, color: DriftProTheme.primaryGreen),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _lastInspectionLabel(PartnerVehicleInspection? last) {
    if (last == null) return 'Ikke kontrollert';
    final d = last.inspectedAt.toLocal();
    final stamp =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    if (last.hasDeviation) return 'Avvik · $stamp';
    return 'OK · $stamp';
  }

  Color _lastInspectionColor(PartnerVehicleInspection? last) {
    if (last == null) return const Color(0xFFD97706);
    if (last.hasDeviation) return const Color(0xFFDC2626);
    return const Color(0xFF15803D);
  }

  List<Widget> _archiveCards(BuildContext context) {
    final q = _archiveSearch.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _archive
        : _archive.where((a) {
            final hay = [
              a.registrationNumber ?? '',
              a.unitCode ?? '',
              a.inspectedByName ?? '',
              a.deviationNotes ?? '',
              a.stampLine,
            ].join(' ').toLowerCase();
            return hay.contains(q);
          }).toList();
    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Ingen treff i arkivet for «${_archiveSearch.text.trim()}».',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ];
    }
    return filtered.map((a) {
      final notCheckedCount = _countNotChecked(a);
      final statusColor = a.hasDeviation
          ? const Color(0xFFDC2626)
          : notCheckedCount > 0
              ? const Color(0xFF9CA3AF)
              : const Color(0xFF15803D);
      final statusText = a.hasDeviation
          ? 'Avvik'
          : notCheckedCount > 0
              ? '$notCheckedCount ikke sjekket'
              : 'OK';

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: a.id == _lastSavedInspectionId
              ? DriftProTheme.primaryGreen.withValues(alpha: 0.1)
              : PartnerModernUi.border(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: a.id == _lastSavedInspectionId
                ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
                : PartnerModernUi.border(context),
            width: a.id == _lastSavedInspectionId ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          dense: true,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  a.vehicleLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
              ),
              if (a.pdfStoragePath?.trim().isNotEmpty == true)
                Tooltip(
                  message: 'PDF arkivert',
                  child: Icon(
                    Icons.verified_outlined,
                    size: 16,
                    color: DriftProTheme.primaryGreen,
                  ),
                ),
            ],
          ),
          subtitle: Text(
            '${a.stampLine}\n${a.hasDeviation ? a.deviationNotes ?? "Avvik registrert" : "Ingen avvik"}',
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor),
                ),
              ),
              IconButton(
                tooltip: 'Last ned PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                onPressed: () => _exportPdf(a),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _stampPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_outlined, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Datostempling ved lagring', style: DriftProTheme.labelSm),
                const SizedBox(height: 2),
                Text(
                  _formatStamp(DateTime.now(), name: _inspectorName),
                  style: DriftProTheme.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldWidget(VehicleInspectionField f) {
    switch (f.type) {
      case InspectionFieldType.okAvvik:
        final val = _checklistValues[f.key] as String? ?? 'ok';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: PartnerModernUi.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _checkOptionChip('OK', 'ok', val, f.key),
                  _checkOptionChip('Avvik', 'avvik', val, f.key),
                  _checkOptionChip('Kan ikke sjekkes', 'not_checked', val, f.key),
                ],
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

  Widget _checkOptionChip(String label, String value, String selected, String fieldKey) {
    final sel = value == selected;
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) {
        setState(() {
          _checklistValues[fieldKey] = value;
          if (_checklistImpliesDeviation()) _hasDeviation = true;
        });
      },
      selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
      checkmarkColor: DriftProTheme.primaryGreen,
    );
  }
}
