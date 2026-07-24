import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/hms/hms_pdf_export_service.dart';
import '../../../core/services/native_permissions_service.dart';
import '../../../core/services/partner/mavi_unit_codes.dart';
import '../../../core/services/partner/partner_service.dart';
import '../../../core/services/partner/vehicle_inspection_pdf.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/bytes_download.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/vehicle_inspection.dart';
import 'partner_modern_ui.dart';
import 'partner_ui.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../../../widgets/resolved_storage_image.dart';

class _PendingInspectionPhoto {
  const _PendingInspectionPhoto({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

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
  List<PartnerVehicle> _vehicles = [];
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
  final List<_PendingInspectionPhoto> _pendingPhotos = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _archiveSelectMode = false;
  final Set<String> _selectedArchiveIds = {};
  bool _massDownloading = false;

  static final _stampFmt = DateFormat('dd.MM.yyyy HH:mm');
  static final _zipStampFmt = DateFormat('yyyyMMdd_HHmm');

  int _countNotChecked(PartnerVehicleInspection ins) {
    var c = 0;
    for (final f in VehicleInspectionTemplate.items) {
      if (f.type != InspectionFieldType.okAvvik) continue;
      final raw = ins.checklist[f.key];
      if (raw is String && raw == 'not_checked') c++;
    }
    return c;
  }

  List<PartnerVehicle> get _regVehicles => _vehicles
      .where((v) =>
          v.vehicleKind == 'registration' || MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .toList();

  List<PartnerVehicle> get _maviVehicles => _vehicles
      .where((v) =>
          v.vehicleKind != 'registration' && !MaviUnitCodes.isRegistrationOnlyUnit(v.unitCode))
      .toList();

  bool _vehicleListsDiffer(List<PartnerVehicle> a, List<PartnerVehicle> b) {
    if (a.length != b.length) return true;
    final aKeys = a.map((v) => '${v.id}|${v.unitCode}').toSet();
    final bKeys = b.map((v) => '${v.id}|${v.unitCode}').toSet();
    return aKeys.length != bKeys.length || !aKeys.containsAll(bKeys);
  }

  @override
  void initState() {
    super.initState();
    _vehicles = List<PartnerVehicle>.from(widget.vehicles);
    _resetChecklist();
    _loadInspectorName();
    _load();
  }

  @override
  void didUpdateWidget(covariant PartnerVehicleInspectionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partner.id != widget.partner.id ||
        _vehicleListsDiffer(oldWidget.vehicles, widget.vehicles)) {
      _load();
    }
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
    _pendingPhotos.clear();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vehicles = await PartnerService.fetchVehicles(widget.partner.id);
    final archive = await PartnerService.fetchVehicleInspections(widget.partner.id);
    final followUps = archive.where((i) => i.followUpOpen).toList()
      ..sort(
        (a, b) => (a.followUpDueAt ?? DateTime(2100))
            .compareTo(b.followUpDueAt ?? DateTime(2100)),
      );
    if (mounted) {
      setState(() {
        _vehicles = vehicles;
        if (_selectedVehicleId != null &&
            !vehicles.any((v) => v.id == _selectedVehicleId)) {
          _selectedVehicleId = null;
        }
        _archive = archive;
        _followUps = followUps;
        _loading = false;
      });
    }
  }

  PartnerVehicle? get _selectedVehicle {
    if (_selectedVehicleId == null) return null;
    for (final v in _vehicles) {
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
        pendingPhotos: _pendingPhotos.map((p) => p.bytes).toList(),
      );
      if (!mounted) return;
      setState(() {
        _resetChecklist();
        _selectedVehicleId = null;
        _lastSavedInspectionId = saved.id;
      });
      await _load();
      if (!mounted) return;
      await _offerPostSaveActions(saved);
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
      generate: () => _pdfBytesFor(inspection),
    );
  }

  Future<Uint8List> _pdfBytesFor(PartnerVehicleInspection inspection) async {
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
      photoBytes: await _photoBytesForExport(inspection),
    );
  }

  List<PartnerVehicleInspection> _filteredArchive() {
    final q = _archiveSearch.text.trim().toLowerCase();
    if (q.isEmpty) return List<PartnerVehicleInspection>.from(_archive);
    return _archive.where((a) {
      final hay = [
        a.registrationNumber ?? '',
        a.unitCode ?? '',
        a.inspectedByName ?? '',
        a.deviationNotes ?? '',
        a.stampLine,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _toggleArchiveSelectMode() {
    setState(() {
      _archiveSelectMode = !_archiveSelectMode;
      if (!_archiveSelectMode) _selectedArchiveIds.clear();
    });
  }

  void _selectAllFilteredArchive() {
    setState(() {
      _selectedArchiveIds
        ..clear()
        ..addAll(_filteredArchive().map((a) => a.id));
    });
  }

  Future<void> _exportSelectedPdfs() async {
    final selected = _filteredArchive()
        .where((a) => _selectedArchiveIds.contains(a.id))
        .toList();
    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én kontroll først.')),
      );
      return;
    }
    await _exportPdfZip(selected);
  }

  Future<void> _exportAllFilteredPdfs() async {
    final list = _filteredArchive();
    if (list.isEmpty) return;
    await _exportPdfZip(list);
  }

  Future<void> _exportPdfZip(List<PartnerVehicleInspection> items) async {
    if (_massDownloading || items.isEmpty) return;
    setState(() => _massDownloading = true);
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Pakker PDF-er…'),
                ],
              ),
            ),
          ),
        ),
      );

      final archive = Archive();
      var ok = 0;
      final usedNames = <String>{};
      for (final ins in items) {
        try {
          final bytes = await _pdfBytesFor(ins);
          var name = '${VehicleInspectionPdf.fileNameFor(ins)}.pdf';
          if (usedNames.contains(name)) {
            name = '${VehicleInspectionPdf.fileNameFor(ins)}_${ins.id.substring(0, 6)}.pdf';
          }
          usedNames.add(name);
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
          ok++;
        } catch (_) {
          // Skip failed single PDF; continue with the rest.
        }
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (ok == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kunne ikke hente PDF-er.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final zipped = ZipEncoder().encode(archive);
      if (zipped == null || zipped.isEmpty) {
        throw Exception('ZIP feilet');
      }
      final partnerLabel = widget.partner.tradeName?.trim().isNotEmpty == true
          ? widget.partner.tradeName!.trim()
          : widget.partner.name;
      final partnerSafe = partnerLabel
          .replaceAll(RegExp(r'[^A-Za-z0-9ÆØÅæøå\-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final zipName =
          'Bilkontroller_${partnerSafe.isEmpty ? 'partner' : partnerSafe}_${_zipStampFmt.format(DateTime.now())}.zip';
      await downloadBytes(
        Uint8List.fromList(zipped),
        zipName,
        mime: 'application/zip',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$ok PDF-er lastet ned ($zipName)')),
      );
      setState(() {
        _archiveSelectMode = false;
        _selectedArchiveIds.clear();
      });
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Massenedlasting feilet: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _massDownloading = false);
    }
  }

  Future<List<Uint8List>> _photoBytesForExport(PartnerVehicleInspection inspection) async {
    final out = <Uint8List>[];
    for (final path in inspection.photoPaths) {
      final bytes = await PartnerService.downloadInspectionPdfBytes(
        path,
        companyId: inspection.companyId,
      );
      if (bytes != null && bytes.isNotEmpty) out.add(bytes);
    }
    return out;
  }

  Future<void> _pickInspectionCamera() async {
    if (!await NativePermissionsService.ensureCamera(context: context)) return;
    final shot = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (shot == null) return;
    final bytes = await shot.readAsBytes();
    if (!mounted) return;
    setState(() => _pendingPhotos.add(_PendingInspectionPhoto(bytes: bytes, name: shot.name)));
  }

  Future<void> _pickInspectionGallery() async {
    if (!await NativePermissionsService.ensurePhotos(context: context)) return;
    final picked = await _imagePicker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;
    final added = <_PendingInspectionPhoto>[];
    for (final file in picked) {
      added.add(_PendingInspectionPhoto(bytes: await file.readAsBytes(), name: file.name));
    }
    if (!mounted) return;
    setState(() => _pendingPhotos.addAll(added));
  }

  void _removePendingPhoto(int index) {
    setState(() => _pendingPhotos.removeAt(index));
  }

  Widget _photoPickerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bilder (valgfritt)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: PartnerModernUi.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Ta bilde eller last opp — dokumenterer utstyr, avvik eller bil.',
          style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
        ),
        if (_pendingPhotos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _pendingPhotos.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _pendingPhotos[i].bytes,
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Material(
                        color: Colors.black87,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _removePendingPhoto(i),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickInspectionCamera,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Ta bilde'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickInspectionGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Last opp'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showSavedPhotos(PartnerVehicleInspection inspection) async {
    if (inspection.photoPaths.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bilder — ${inspection.vehicleLabel}'),
        content: SizedBox(
          width: 320,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: inspection.photoPaths.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ResolvedStorageImage(
                storageRef: inspection.photoPaths[i],
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
        ],
      ),
    );
  }

  Future<void> _offerPostSaveActions(PartnerVehicleInspection inspection) async {
    if (!mounted) return;
    var downloadPdf = false;
    // 0 = ingen, 1 = SMS, 2 = push, 3 = begge — ingen auto-send.
    var notifyChoice = 0;
    final plateHint = [
      if ((inspection.registrationNumber ?? '').trim().isNotEmpty &&
          inspection.registrationNumber!.trim() != '—')
        inspection.registrationNumber!.trim().toUpperCase(),
      if ((inspection.unitCode ?? '').trim().isNotEmpty) inspection.unitCode!.trim(),
    ].join(' · ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Kontroll arkivert'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plateHint.isEmpty
                      ? 'PDF er lagret i arkivet. Velg hva du vil gjøre:'
                      : 'Kontroll lagret for $plateHint. Velg hva du vil gjøre:',
                  style: TextStyle(color: PartnerModernUi.textPrimary(ctx)),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Last ned PDF nå'),
                  subtitle: const Text('Eller last ned senere fra Arkiv'),
                  value: downloadPdf,
                  onChanged: (v) => setLocal(() => downloadPdf = v ?? false),
                ),
                const Divider(height: 20),
                Text(
                  'Varsle bedriftsansvarlig',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: PartnerModernUi.textPrimary(ctx),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  inspection.hasDeviation
                      ? 'SMS/push varsler om avvik og inkluderer skiltnummer. Ingenting sendes før du velger og trykker Utfør.'
                      : 'Ved OK-kontroll får bedriftsansvarlig en profesjonell bekreftelse: bilen har vært i kontroll og alt ser bra ut. Ingenting sendes før du velger og trykker Utfør.',
                  style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(ctx)),
                ),
                RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Ikke varsle'),
                  value: 0,
                  groupValue: notifyChoice,
                  onChanged: (v) => setLocal(() => notifyChoice = v ?? 0),
                ),
                RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Kun SMS'),
                  value: 1,
                  groupValue: notifyChoice,
                  onChanged: (v) => setLocal(() => notifyChoice = v ?? 0),
                ),
                RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Kun push-varsel'),
                  value: 2,
                  groupValue: notifyChoice,
                  onChanged: (v) => setLocal(() => notifyChoice = v ?? 0),
                ),
                RadioListTile<int>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('SMS og push (begge)'),
                  value: 3,
                  groupValue: notifyChoice,
                  onChanged: (v) => setLocal(() => notifyChoice = v ?? 0),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Senere'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
              child: const Text('Utfør'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || confirmed != true) return;

    final sendSms = notifyChoice == 1 || notifyChoice == 3;
    final sendPush = notifyChoice == 2 || notifyChoice == 3;

    if (downloadPdf) {
      await _exportPdf(inspection);
    }
    if (sendSms || sendPush) {
      final summary = await PartnerService.notifyVehicleInspectionOwners(
        inspection.id,
        sms: sendSms,
        push: sendPush,
        email: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(summary), duration: const Duration(seconds: 5)),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            downloadPdf ? 'Kontroll arkivert. PDF lastet ned.' : 'Kontroll arkivert.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _offerNotifyOwners(PartnerVehicleInspection inspection) async {
    if (!mounted) return;
    var notifyChoice = 3; // SMS + push as suggested when opening from archive
    final plateHint = [
      if ((inspection.registrationNumber ?? '').trim().isNotEmpty &&
          inspection.registrationNumber!.trim() != '—')
        inspection.registrationNumber!.trim().toUpperCase(),
      if ((inspection.unitCode ?? '').trim().isNotEmpty) inspection.unitCode!.trim(),
    ].join(' · ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Varsle bedriftsansvarlig'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plateHint.isEmpty
                    ? (inspection.hasDeviation
                        ? 'Velg hvordan bedriftsansvarlig skal varsles om avvik.'
                        : 'Velg hvordan bedriftsansvarlig skal varsles. Ved OK sendes en positiv bekreftelse.')
                    : (inspection.hasDeviation
                        ? 'Varsel om avvik på $plateHint. SMS/push inkluderer skiltnummer.'
                        : 'Varsel om OK-kontroll på $plateHint: bilen har vært i kontroll og alt ser bra ut.'),
                style: TextStyle(color: PartnerModernUi.textPrimary(ctx)),
              ),
              RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Kun SMS'),
                value: 1,
                groupValue: notifyChoice,
                onChanged: (v) => setLocal(() => notifyChoice = v ?? 1),
              ),
              RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Kun push-varsel'),
                value: 2,
                groupValue: notifyChoice,
                onChanged: (v) => setLocal(() => notifyChoice = v ?? 2),
              ),
              RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('SMS og push (begge)'),
                value: 3,
                groupValue: notifyChoice,
                onChanged: (v) => setLocal(() => notifyChoice = v ?? 3),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || confirmed != true) return;

    await _sendOwnerNotify(
      inspection,
      sms: notifyChoice == 1 || notifyChoice == 3,
      push: notifyChoice == 2 || notifyChoice == 3,
    );
  }

  Future<void> _sendOwnerNotify(
    PartnerVehicleInspection inspection, {
    required bool sms,
    required bool push,
  }) async {
    final summary = await PartnerService.notifyVehicleInspectionOwners(
      inspection.id,
      sms: sms,
      push: push,
      email: false,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary), duration: const Duration(seconds: 5)),
    );
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
        PartnerVehicleInspection.latestByVehicleId(_vehicles, _archive);
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
              const SizedBox(height: 12),
              _photoPickerSection(context),
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_archive.isNotEmpty) ...[
                IconButton(
                  tooltip: _archiveSelectMode ? 'Avbryt valg' : 'Velg for massenedlasting',
                  onPressed: _massDownloading ? null : _toggleArchiveSelectMode,
                  icon: Icon(
                    _archiveSelectMode ? Icons.close : Icons.checklist_rtl,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Last ned alle PDF-er (ZIP)',
                  onPressed: _massDownloading || _archive.isEmpty
                      ? null
                      : _exportAllFilteredPdfs,
                  icon: _massDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: DriftProLoadingIndicator(size: 18),
                        )
                      : const Icon(Icons.folder_zip_outlined, size: 20),
                ),
              ],
              Text(
                '${_archive.length}',
                style: TextStyle(fontWeight: FontWeight.w600, color: PartnerModernUi.muted(context)),
              ),
            ],
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
              if (_archiveSelectMode) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_selectedArchiveIds.length} valgt',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _selectAllFilteredArchive,
                        child: const Text('Velg alle'),
                      ),
                      FilledButton.icon(
                        onPressed: _massDownloading || _selectedArchiveIds.isEmpty
                            ? null
                            : _exportSelectedPdfs,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Last ned ZIP'),
                        style: FilledButton.styleFrom(
                          backgroundColor: DriftProTheme.primaryGreen,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    final filtered = _filteredArchive();
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
      final selected = _selectedArchiveIds.contains(a.id);

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: a.id == _lastSavedInspectionId
              ? DriftProTheme.primaryGreen.withValues(alpha: 0.1)
              : PartnerModernUi.border(context).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? DriftProTheme.primaryGreen
                : a.id == _lastSavedInspectionId
                    ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
                    : PartnerModernUi.border(context),
            width: selected || a.id == _lastSavedInspectionId ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          dense: true,
          leading: _archiveSelectMode
              ? Checkbox(
                  value: selected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedArchiveIds.add(a.id);
                      } else {
                        _selectedArchiveIds.remove(a.id);
                      }
                    });
                  },
                )
              : null,
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
              if (a.photoPaths.isNotEmpty)
                IconButton(
                  tooltip: 'Vis bilder',
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  onPressed: () => _showSavedPhotos(a),
                ),
            ],
          ),
          subtitle: Text(
            '${a.stampLine}\n${a.hasDeviation ? a.deviationNotes ?? "Avvik registrert" : "Ingen avvik"}'
            '${a.photoPaths.isNotEmpty ? "\n${a.photoPaths.length} bilde(r)" : ""}',
            style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
          ),
          onTap: _archiveSelectMode
              ? () {
                  setState(() {
                    if (selected) {
                      _selectedArchiveIds.remove(a.id);
                    } else {
                      _selectedArchiveIds.add(a.id);
                    }
                  });
                }
              : a.photoPaths.isNotEmpty
                  ? () => _showSavedPhotos(a)
                  : null,
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
              if (!_archiveSelectMode) ...[
                PopupMenuButton<String>(
                  tooltip: 'Varsle bedriftsansvarlig',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.campaign_outlined, size: 20),
                  onSelected: (choice) async {
                    switch (choice) {
                      case 'sms':
                        await _sendOwnerNotify(a, sms: true, push: false);
                      case 'push':
                        await _sendOwnerNotify(a, sms: false, push: true);
                      case 'both':
                        await _sendOwnerNotify(a, sms: true, push: true);
                      case 'choose':
                        await _offerNotifyOwners(a);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'sms', child: Text('Send SMS')),
                    PopupMenuItem(value: 'push', child: Text('Send push-varsel')),
                    PopupMenuItem(value: 'both', child: Text('Send SMS + push')),
                    PopupMenuItem(value: 'choose', child: Text('Velg…')),
                  ],
                ),
                IconButton(
                  tooltip: 'Last ned PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                  onPressed: () => _exportPdf(a),
                ),
              ],
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
