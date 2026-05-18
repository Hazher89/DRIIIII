import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/hms/truck_inspection_templates.dart';
import '../../../core/permissions/user_access.dart';
import '../../../core/services/hms/equipment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import 'equipment_form_screen.dart';
import 'equipment_service_book_screen.dart';

/// Truck-profil: mal (gaffel/klem), bilder, kontroll og SMS-planlegging.
class EquipmentTruckProfileScreen extends StatefulWidget {
  final String equipmentId;
  final UserProfile profile;
  final Map<String, String> profileNames;

  const EquipmentTruckProfileScreen({
    super.key,
    required this.equipmentId,
    required this.profile,
    this.profileNames = const {},
  });

  @override
  State<EquipmentTruckProfileScreen> createState() =>
      _EquipmentTruckProfileScreenState();
}

class _EquipmentTruckProfileScreenState extends State<EquipmentTruckProfileScreen>
    with SingleTickerProviderStateMixin {
  Equipment? _equipment;
  List<EquipmentServiceReminder> _reminders = [];
  bool _loading = true;
  late TabController _tabs;
  TruckSubtype _subtype = TruckSubtype.fork;
  Map<String, dynamic> _checklist = {};
  List<String> _imageUrls = [];
  bool _controlEnabled = true;
  bool _saving = false;

  UserAccess get _access => widget.profile.access;

  bool get _canEdit =>
      _access.canHmsEquipmentAdmin || _access.dataScopeCompany;

  bool get _canService =>
      _access.canHmsEquipmentService ||
      _access.canHmsEquipmentAdmin ||
      widget.profile.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _equipment = await EquipmentService.fetchById(widget.equipmentId);
      if (_equipment != null) {
        _subtype = TruckSubtypeExtension.fromDb(_equipment!.truckSubtype);
        _checklist = Map<String, dynamic>.from(_equipment!.truckChecklistData);
        _imageUrls = List.from(_equipment!.imageUrls);
        _controlEnabled = _equipment!.controlEnabled;
        _reminders =
            await EquipmentService.fetchReminders(widget.equipmentId);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveEquipment(Equipment updated) async {
    setState(() => _saving = true);
    try {
      await EquipmentService.save(updated, id: updated.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _persistTruckFields() async {
    final e = _equipment;
    if (e == null) return;
    await _saveEquipment(e.copyWithTruck(
      truckSubtype: _subtype.dbValue,
      truckChecklistData: _checklist,
      imageUrls: _imageUrls,
      controlEnabled: _controlEnabled,
    ));
  }

  Future<void> _pickImages() async {
    final companyId = widget.profile.companyId;
    if (companyId == null) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.image,
    );
    if (result == null) return;
    setState(() => _saving = true);
    try {
      for (final f in result.files) {
        if (f.bytes == null) continue;
        final url = await EquipmentService.uploadDocument(
          companyId: companyId,
          fileName: f.name,
          bytes: f.bytes!,
          subfolder: 'truck_images',
        );
        _imageUrls.add(url);
      }
      await _persistTruckFields();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _completeInspection() async {
    final e = _equipment;
    if (e == null || widget.profile.companyId == null) return;

    final items = TruckInspectionTemplates.itemsFor(_subtype);
    final missing = items.where((i) {
      if (!i.critical) return false;
      return _checklist[i.id] != true;
    }).toList();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kritiske punkter må være OK: ${missing.map((m) => m.label).join(', ')}',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final interval =
        TruckInspectionTemplates.defaultInspectionIntervalDays(_subtype);
    final nextInspection = DateTime.now().add(Duration(days: interval));
    final notifyIds = <String>{
      if (e.responsibleUserId != null) e.responsibleUserId!,
      if (e.assignedTo != null) e.assignedTo!,
    };

    final scheduleSms = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontroll fullført'),
        content: Text(
          'Neste kontroll foreslås ${nextInspection.day}.${nextInspection.month}.${nextInspection.year}.\n\n'
          'Planlegge SMS-varsel?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nei')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja, planlegg SMS')),
        ],
      ),
    );

    setState(() => _saving = true);
    try {
      _checklist['last_inspection_at'] = DateTime.now().toIso8601String();
      _checklist['last_inspection_by'] = widget.profile.id;

      final updated = e.copyWithTruck(
        truckSubtype: _subtype.dbValue,
        truckChecklistData: _checklist,
        imageUrls: _imageUrls,
        controlEnabled: _controlEnabled,
        nextInspection: nextInspection,
        lastService: DateTime.now(),
      );
      await EquipmentService.save(updated, id: updated.id);

      await EquipmentService.addServiceBookEntry(
        equipment: updated,
        type: MaintenanceType.inspection,
        performedBy: widget.profile.id,
        notes: 'Truck-kontroll (${_subtype.label}) — ${_checkedCount()}/${items.length} punkter',
        nextDueAt: nextInspection,
        smsNotifyUserIds: scheduleSms == true ? notifyIds.toList() : null,
        notifyDaysBefore: e.notifyDaysBefore,
      );

      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _checkedCount() {
    final items = TruckInspectionTemplates.itemsFor(_subtype);
    return items.where((i) => _checklist[i.id] == true).length;
  }

  @override
  Widget build(BuildContext context) {
    final e = _equipment;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (e == null) {
      return const Scaffold(body: Center(child: Text('Fant ikke utstyr')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EquipmentFormScreen(
                      profile: widget.profile,
                      existing: e,
                      profileNames: widget.profileNames,
                    ),
                  ),
                );
                if (ok == true) _load();
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Oversikt'),
            Tab(text: 'Kontrollmal'),
            Tab(text: 'Bilder'),
            Tab(text: 'Service'),
          ],
        ),
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _overviewTab(e),
                _checklistTab(),
                _imagesTab(),
                _serviceTab(e),
              ],
            ),
    );
  }

  Widget _overviewTab(Equipment e) {
    final responsible = widget.profileNames[e.responsibleUserId];
    final assigned = widget.profileNames[e.assignedTo];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusBanner(e),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Truck-type', style: DriftProTheme.labelMd),
                const SizedBox(height: 8),
                SegmentedButton<TruckSubtype>(
                  segments: TruckSubtype.values.map((s) {
                    return ButtonSegment(
                      value: s,
                      label: Text(s.label, style: const TextStyle(fontSize: 11)),
                    );
                  }).toList(),
                  selected: {_subtype},
                  onSelectionChanged: _canEdit
                      ? (v) {
                          setState(() => _subtype = v.first);
                          _persistTruckFields();
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Periodisk kontroll aktiv'),
                  subtitle: const Text('Når av, ingen varsler for truck-kontroll'),
                  value: _controlEnabled,
                  onChanged: _canEdit
                      ? (v) {
                          setState(() => _controlEnabled = v);
                          _persistTruckFields();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _infoRow('Merke / modell', '${e.brand ?? '—'} / ${e.model ?? '—'}'),
        _infoRow('Serienr.', e.serialNumber ?? '—'),
        _infoRow('Skilt', e.licensePlate ?? '—'),
        _infoRow('Plassering', e.location ?? '—'),
        _infoRow('Ansvarlig', responsible ?? '—'),
        _infoRow('Bruker', assigned ?? '—'),
        _infoRow(
          'Neste vann/batteri',
          e.nextWaterCheck != null
              ? '${e.nextWaterCheck!.day}.${e.nextWaterCheck!.month}.${e.nextWaterCheck!.year}'
              : '—',
        ),
        _infoRow(
          'Neste service',
          e.nextService != null
              ? '${e.nextService!.day}.${e.nextService!.month}.${e.nextService!.year}'
              : '—',
        ),
        _infoRow(
          'Neste kontroll',
          e.nextInspection != null
              ? '${e.nextInspection!.day}.${e.nextInspection!.month}.${e.nextInspection!.year}'
              : '—',
        ),
        if (_reminders.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Planlagte SMS', style: DriftProTheme.headingSm),
          ..._reminders.map((r) => ListTile(
                dense: true,
                leading: const Icon(Icons.sms_outlined),
                title: Text('${r.reminderType} — ${r.dueDate.day}.${r.dueDate.month}.${r.dueDate.year}'),
                subtitle: Text(r.notes ?? ''),
              )),
        ],
      ],
    );
  }

  Widget _statusBanner(Equipment e) {
    Color bg;
    String msg;
    if (e.isOverdue) {
      bg = DriftProTheme.error;
      msg = 'Forfalt vedlikehold eller kontroll';
    } else if (e.isDueSoon) {
      bg = DriftProTheme.warning;
      msg = 'Snart frist — sjekk service/vann/kontroll';
    } else {
      bg = DriftProTheme.primaryGreen;
      msg = 'Truck i orden — kontroll ${_checkedCount()}/${TruckInspectionTemplates.itemsFor(_subtype).length}';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg),
      ),
      child: Text(msg, style: TextStyle(color: bg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: DriftProTheme.caption)),
          Expanded(child: Text(value, style: DriftProTheme.bodyMd)),
        ],
      ),
    );
  }

  Widget _checklistTab() {
    final items = TruckInspectionTemplates.itemsFor(_subtype);
    final groups = <String, List<TruckChecklistItem>>{};
    for (final i in items) {
      groups.putIfAbsent(i.group, () => []).add(i);
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Daglig / periodisk kontroll — ${_subtype.label}',
                style: DriftProTheme.headingSm,
              ),
              const SizedBox(height: 4),
              Text(
                '${_checkedCount()} av ${items.length} punkter markert OK',
                style: DriftProTheme.caption,
              ),
              const SizedBox(height: 12),
              ...groups.entries.map((g) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(g.key, style: DriftProTheme.labelMd),
                    ),
                    ...g.value.map((item) {
                      final ok = _checklist[item.id] == true;
                      final fail = _checklist[item.id] == false;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          title: Text(item.label),
                          subtitle: item.critical
                              ? const Text('Kritisk', style: TextStyle(color: Colors.red))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.check_circle,
                                  color: ok ? DriftProTheme.primaryGreen : Colors.grey,
                                ),
                                onPressed: _canService
                                    ? () {
                                        setState(() => _checklist[item.id] = true);
                                        _persistTruckFields();
                                      }
                                    : null,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.cancel,
                                  color: fail ? DriftProTheme.error : Colors.grey,
                                ),
                                onPressed: _canService
                                    ? () {
                                        setState(() => _checklist[item.id] = false);
                                        _persistTruckFields();
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
        if (_canService)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _completeInspection,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Fullfør kontroll og planlegg neste'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
      ],
    );
  }

  Widget _imagesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_canService)
          OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Last opp bilde (skade, ID, truck)'),
          ),
        const SizedBox(height: 16),
        if (_imageUrls.isEmpty)
          const Center(child: Text('Ingen bilder ennå'))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _imageUrls.length,
            itemBuilder: (_, i) {
              final url = _imageUrls[i];
              return Stack(
                fit: StackFit.expand,
                children: [
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(url)),
                    child: Image.network(url, fit: BoxFit.cover),
                  ),
                  if (_canEdit)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        icon: const Icon(Icons.close, color: Colors.white, size: 18),
                        onPressed: () {
                          setState(() => _imageUrls.removeAt(i));
                          _persistTruckFields();
                        },
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _serviceTab(Equipment e) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book_outlined, size: 56, color: DriftProTheme.primaryGreen),
            const SizedBox(height: 16),
            const Text(
              'Digitalt servicehefte med historikk, vann/batteri, reparasjon og SMS.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EquipmentServiceBookScreen(
                      equipmentId: e.id,
                      profile: widget.profile,
                      profileNames: widget.profileNames,
                    ),
                  ),
                ).then((_) => _load());
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Åpne servicehefte'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _EquipmentTruckCopy on Equipment {
  Equipment copyWithTruck({
    String? truckSubtype,
    Map<String, dynamic>? truckChecklistData,
    List<String>? imageUrls,
    bool? controlEnabled,
    DateTime? nextInspection,
    DateTime? lastService,
  }) {
    return Equipment(
      id: id,
      companyId: companyId,
      name: name,
      category: category,
      brand: brand,
      model: model,
      serialNumber: serialNumber,
      description: description,
      location: location,
      internalNumber: internalNumber,
      licensePlate: licensePlate,
      status: status,
      lastService: lastService ?? this.lastService,
      nextService: nextService,
      nextWaterCheck: nextWaterCheck,
      nextInspection: nextInspection ?? this.nextInspection,
      purchaseDate: purchaseDate,
      purchasePrice: purchasePrice,
      warrantyUntil: warrantyUntil,
      supplier: supplier,
      assignedTo: assignedTo,
      responsibleUserId: responsibleUserId,
      registeredBy: registeredBy,
      departmentId: departmentId,
      imageUrls: imageUrls ?? this.imageUrls,
      receiptUrls: receiptUrls,
      serviceManualUrls: serviceManualUrls,
      maintenanceIntervalDays: maintenanceIntervalDays,
      notifyDaysBefore: notifyDaysBefore,
      notes: notes,
      truckSubtype: truckSubtype ?? this.truckSubtype,
      truckChecklistData: truckChecklistData ?? this.truckChecklistData,
      controlEnabled: controlEnabled ?? this.controlEnabled,
    );
  }
}
