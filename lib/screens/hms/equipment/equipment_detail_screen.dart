import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/hms/equipment_service.dart';
import '../../../core/services/hms/hms_pdf_generators.dart';
import '../widgets/hms_pdf_export_button.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import 'equipment_form_screen.dart';
import 'equipment_service_book_screen.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class EquipmentDetailScreen extends StatefulWidget {
  final String equipmentId;
  final UserProfile profile;
  final Map<String, String> profileNames;

  const EquipmentDetailScreen({
    super.key,
    required this.equipmentId,
    required this.profile,
    this.profileNames = const {},
  });

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  Equipment? _item;
  List<EquipmentMaintenanceLog> _logs = [];
  List<EquipmentPurchase> _purchases = [];
  bool _loading = true;

  UserAccess get _access => widget.profile.access;

  bool get _canService =>
      _access.canHmsEquipmentService ||
      _access.canHmsEquipmentAdmin ||
      widget.profile.role == UserRole.admin ||
      widget.profile.role == UserRole.superadmin;

  bool get _canManuals =>
      _access.canHmsEquipmentManuals ||
      _canService ||
      _access.canHmsEquipmentAdmin;

  bool get _canEdit => _access.canHmsEquipmentAdmin || _access.dataScopeCompany;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _item = await EquipmentService.fetchById(widget.equipmentId);
      if (_item != null) {
        _logs = await EquipmentService.fetchMaintenanceLogs(widget.equipmentId);
        if (widget.profile.companyId != null) {
          _purchases = await EquipmentService.fetchPurchases(
            companyId: widget.profile.companyId!,
            equipmentId: widget.equipmentId,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _name(String? id) =>
      id == null ? null : widget.profileNames[id];

  Future<void> _logMaintenance(MaintenanceType type) async {
    final e = _item;
    if (e == null || widget.profile.companyId == null) return;

    final notesCtrl = TextEditingController();
    DateTime nextDue = DateTime.now();
    if (type == MaintenanceType.waterFill) {
      final settings = await EquipmentService.getNotificationSettings(
        widget.profile.companyId!,
      );
      nextDue = DateTime.now()
          .add(Duration(days: settings.truckWaterIntervalDays));
    } else if (type == MaintenanceType.service) {
      final settings = await EquipmentService.getNotificationSettings(
        widget.profile.companyId!,
      );
      nextDue = DateTime.now()
          .add(Duration(days: settings.truckServiceIntervalDays));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Logg ${type.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notat'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Text(
              'Neste frist foreslås: ${nextDue.day}.${nextDue.month}.${nextDue.year}',
              style: DriftProTheme.caption,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await EquipmentService.addMaintenanceLog(
      EquipmentMaintenanceLog(
        id: const Uuid().v4(),
        companyId: widget.profile.companyId!,
        equipmentId: e.id,
        type: type,
        performedAt: DateTime.now(),
        performedBy: widget.profile.id,
        nextDueAt: nextDue,
        notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${type.label} registrert')),
      );
      _load();
    }
  }

  Future<void> _uploadMaintDoc() async {
    final e = _item;
    if (e == null || widget.profile.companyId == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.single.bytes == null) return;
    final url = await EquipmentService.uploadDocument(
      companyId: widget.profile.companyId!,
      fileName: result.files.single.name,
      bytes: result.files.single.bytes!,
      subfolder: 'service',
    );
    await EquipmentService.addMaintenanceLog(
      EquipmentMaintenanceLog(
        id: const Uuid().v4(),
        companyId: widget.profile.companyId!,
        equipmentId: e.id,
        type: MaintenanceType.other,
        performedAt: DateTime.now(),
        performedBy: widget.profile.id,
        documentUrls: [url],
        notes: 'Vedlegg lastet opp',
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: const DriftProLoadingCenter(),
      );
    }
    final e = _item;
    if (e == null) {
      return const Scaffold(body: Center(child: Text('Fant ikke utstyr')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          HmsPdfExportButton(
            fileName: 'utstyr_${e.id.substring(0, 8)}',
            onGenerate: () => HmsPdfGenerators.equipment(
              e,
              logs: _logs,
              purchases: _purchases,
            ),
          ),
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit),
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
                if (ok == true) {
                  _load();
                  if (mounted) Navigator.pop(context, true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(e),
          if (e.isTruck) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('ÅPNE DIGITALT SERVICEHEFTE'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueGrey.shade800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _infoSection(e),
          if (_canManuals && e.serviceManualUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Servicehefter', style: DriftProTheme.headingSm),
            ...e.serviceManualUrls.map(
              (url) => ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Åpne servicehefte'),
                onTap: () => launchUrl(Uri.parse(url)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Servicearkiv', style: DriftProTheme.headingSm),
              if (_canService)
                TextButton.icon(
                  onPressed: _uploadMaintDoc,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Vedlegg'),
                ),
            ],
          ),
          if (_logs.isEmpty)
            Text('Ingen registreringer ennå.', style: DriftProTheme.caption)
          else
            ..._logs.map(_logTile),
          const SizedBox(height: 20),
          Text('Innkjøp / kvitteringer', style: DriftProTheme.headingSm),
          if (_purchases.isEmpty && e.receiptUrls.isEmpty)
            Text('Ingen kvitteringer.', style: DriftProTheme.caption),
          ..._purchases.map(
            (p) => ListTile(
              dense: true,
              leading: const Icon(Icons.receipt),
              title: Text(p.itemName),
              subtitle: Text(
                '${p.purchasedAt.day}.${p.purchasedAt.month}.${p.purchasedAt.year}',
              ),
            ),
          ),
          ...e.receiptUrls.map(
            (url) => ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file),
              title: const Text('Kvittering'),
              onTap: () => launchUrl(Uri.parse(url)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(Equipment e) {
    final color = e.isOverdue
        ? DriftProTheme.error
        : e.isDueSoon
            ? DriftProTheme.warning
            : DriftProTheme.success;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              e.isOverdue
                  ? 'Forfalt vedlikehold — varsle ansvarlig'
                  : e.isDueSoon
                      ? 'Forfaller snart (${e.notifyDaysBefore} dager varsel)'
                      : 'Status: ${e.status.label}',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoSection(Equipment e) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Kategori', e.category.label),
            if (e.serialNumber != null) _row('SN', e.serialNumber!),
            if (e.licensePlate != null) _row('Skilt', e.licensePlate!),
            if (_name(e.responsibleUserId) != null)
              _row('Ansvarlig', _name(e.responsibleUserId)!),
            if (_name(e.assignedTo) != null)
              _row('Bruker', _name(e.assignedTo)!),
            if (e.purchaseDate != null)
              _row(
                'Innkjøpt',
                '${e.purchaseDate!.day}.${e.purchaseDate!.month}.${e.purchaseDate!.year}',
              ),
            if (e.nextWaterCheck != null)
              _row(
                'Neste vann',
                '${e.nextWaterCheck!.day}.${e.nextWaterCheck!.month}.${e.nextWaterCheck!.year}',
              ),
            if (e.nextService != null)
              _row(
                'Neste service',
                '${e.nextService!.day}.${e.nextService!.month}.${e.nextService!.year}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: DriftProTheme.caption)),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Widget _logTile(EquipmentMaintenanceLog log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          log.type == MaintenanceType.waterFill
              ? Icons.water_drop
              : Icons.build,
          color: DriftProTheme.primaryGreen,
        ),
        title: Text(log.type.label),
        subtitle: Text(
          '${log.performedAt.day}.${log.performedAt.month}.${log.performedAt.year}'
          '${log.notes != null ? '\n${log.notes}' : ''}'
          '${log.nextDueAt != null ? '\nNeste: ${log.nextDueAt!.day}.${log.nextDueAt!.month}.${log.nextDueAt!.year}' : ''}',
        ),
      ),
    );
  }
}
