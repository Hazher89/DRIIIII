import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/permissions/user_access.dart';
import '../../../core/services/hms/equipment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';
import 'equipment_service_entry_sheet.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Digitalt servicehefte — all historikk, registrering og SMS-planlegging.
class EquipmentServiceBookScreen extends StatefulWidget {
  final String equipmentId;
  final UserProfile profile;
  final Map<String, String> profileNames;

  const EquipmentServiceBookScreen({
    super.key,
    required this.equipmentId,
    required this.profile,
    this.profileNames = const {},
  });

  @override
  State<EquipmentServiceBookScreen> createState() =>
      _EquipmentServiceBookScreenState();
}

class _EquipmentServiceBookScreenState extends State<EquipmentServiceBookScreen> {
  Equipment? _equipment;
  EquipmentServiceBook? _book;
  List<EquipmentMaintenanceLog> _logs = [];
  List<EquipmentServiceReminder> _reminders = [];
  EquipmentNotificationSettings _settings =
      const EquipmentNotificationSettings(companyId: '');
  bool _loading = true;

  UserAccess get _access => widget.profile.access;

  bool get _canWrite =>
      _access.canHmsEquipmentService ||
      _access.canHmsEquipmentAdmin ||
      widget.profile.role == UserRole.admin ||
      widget.profile.role == UserRole.superadmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _equipment = await EquipmentService.fetchById(widget.equipmentId);
      if (_equipment == null) return;
      _book = await EquipmentService.fetchServiceBook(widget.equipmentId) ??
          await EquipmentService.ensureServiceBook(widget.equipmentId);
      _logs = await EquipmentService.fetchMaintenanceLogs(widget.equipmentId);
      _reminders =
          await EquipmentService.fetchReminders(widget.equipmentId);
      if (widget.profile.companyId != null) {
        _settings = await EquipmentService.getNotificationSettings(
          widget.profile.companyId!,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEntry(MaintenanceType type) async {
    final e = _equipment;
    if (e == null) return;
    final ok = await EquipmentServiceEntrySheet.show(
      context,
      equipment: e,
      profile: widget.profile,
      type: type,
      profileNames: widget.profileNames,
      settings: _settings,
    );
    if (ok == true) _load();
  }

  Future<void> _scheduleOnly() async {
    final e = _equipment;
    if (e == null || widget.profile.companyId == null) return;

    DateTime due = e.nextService ?? DateTime.now().add(const Duration(days: 90));
    DateTime notifyOn = due.subtract(
      Duration(days: _settings.defaultNotifyDaysBefore),
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (notifyOn.isBefore(todayDate)) notifyOn = todayDate;

    final selected = <String>{
      if (e.responsibleUserId != null) e.responsibleUserId!,
    };
    final notesCtrl = TextEditingController();
    String rType = 'service';

    String fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';
    int notifyDaysBefore() {
      final dueDate = DateTime(due.year, due.month, due.day);
      final notifyDate = DateTime(notifyOn.year, notifyOn.month, notifyOn.day);
      return dueDate.difference(notifyDate).inDays.clamp(0, 365);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Planlegg neste frist + SMS'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: rType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'service', child: Text('Service')),
                    DropdownMenuItem(
                        value: 'water_fill', child: Text('Vann / batteri')),
                    DropdownMenuItem(
                        value: 'inspection', child: Text('Inspeksjon')),
                  ],
                  onChanged: (v) => setD(() => rType = v ?? 'service'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fristdato'),
                  subtitle: Text(fmt(due)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: due,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2035),
                    );
                    if (d != null) {
                      setD(() {
                        due = d;
                        notifyOn = d.subtract(
                          Duration(days: _settings.defaultNotifyDaysBefore),
                        );
                        if (notifyOn.isBefore(todayDate)) notifyOn = todayDate;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dato for varsel'),
                  subtitle: Text(fmt(notifyOn)),
                  trailing: const Icon(Icons.notifications_active_outlined),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: notifyOn,
                      firstDate: DateTime.now(),
                      lastDate: due,
                    );
                    if (d != null) setD(() => notifyOn = d);
                  },
                ),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notat'),
                ),
                const Divider(),
                Text('Varsle ansatt:', style: DriftProTheme.labelSm),
                ...widget.profileNames.entries.map((ent) {
                  final checked = selected.contains(ent.key);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(ent.value),
                    subtitle: checked ? Text('SMS ${fmt(notifyOn)}') : null,
                    value: checked,
                    onChanged: (on) {
                      setD(() {
                        if (on == true) {
                          selected.add(ent.key);
                        } else {
                          selected.remove(ent.key);
                        }
                      });
                    },
                  );
                }),
                if (selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${selected.length} ansatt(er) varsles ${fmt(notifyOn)} '
                      '(frist ${fmt(due)}).',
                      style: DriftProTheme.caption.copyWith(
                        color: DriftProTheme.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Lagre & planlegg SMS'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final remId = await EquipmentService.scheduleReminder(
      equipmentId: e.id,
      reminderType: rType,
      dueDate: due,
      notifyUserIds: selected.toList(),
      notifyDaysBefore: notifyDaysBefore(),
      notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Frist ${fmt(due)}. SMS til ${selected.length} ansatt(er) '
            'planlagt ${fmt(notifyOn)}.',
          ),
        ),
      );
    }
    _load();

    if (_canWrite && mounted) {
      final sendNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Send SMS nå?'),
          content: const Text(
            'Vil du sende påminnelse til valgte ansatte med en gang (test/ekstra varsel)?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nei')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Send SMS')),
          ],
        ),
      );
      if (sendNow == true) {
        final n = await EquipmentService.sendReminderSmsNow(remId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$n SMS lagt i kø')),
          );
        }
      }
    }
  }

  IconData _iconForType(MaintenanceType t) {
    switch (t) {
      case MaintenanceType.waterFill:
        return Icons.water_drop_outlined;
      case MaintenanceType.wash:
        return Icons.local_car_wash_outlined;
      case MaintenanceType.storage:
        return Icons.warehouse_outlined;
      case MaintenanceType.repair:
        return Icons.build_circle_outlined;
      case MaintenanceType.inspection:
        return Icons.fact_check_outlined;
      case MaintenanceType.service:
        return Icons.engineering_outlined;
      default:
        return Icons.note_alt_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: const DriftProLoadingCenter(),
      );
    }
    final e = _equipment;
    final book = _book;
    if (e == null || book == null) {
      return const Scaffold(body: Center(child: Text('Fant ikke servicehefte')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicehefte'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openEntry(MaintenanceType.service),
              icon: const Icon(Icons.add),
              label: const Text('Registrer'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _header(book, e),
            const SizedBox(height: 20),
            if (_canWrite) ...[
              Text('Hurtigregistrering', style: DriftProTheme.headingSm),
              const SizedBox(height: 10),
              _quickActions(),
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Planlagte SMS-varsler', style: DriftProTheme.headingSm),
                if (_canWrite)
                  TextButton(
                    onPressed: _scheduleOnly,
                    child: const Text('Planlegg'),
                  ),
              ],
            ),
            if (_reminders.isEmpty)
              Text('Ingen planlagte varsler.', style: DriftProTheme.caption)
            else
              ..._reminders.map(_reminderCard),
            const SizedBox(height: 24),
            Text('Hele arkivet (${_logs.length})',
                style: DriftProTheme.headingSm),
            const SizedBox(height: 8),
            ..._logs.map(_logCard),
            if (e.serviceManualUrls.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Vedlegg / PDF', style: DriftProTheme.headingSm),
              ...e.serviceManualUrls.map(
                (url) => ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('Servicehefte PDF'),
                  onTap: () => launchUrl(Uri.parse(url)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(EquipmentServiceBook book, Equipment e) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blueGrey.shade800,
            DriftProTheme.primaryGreen.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            book.bookNumber,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            e.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              if (e.nextService != null)
                _chip('Service: ${e.nextService!.day}.${e.nextService!.month}.${e.nextService!.year}'),
              if (e.nextWaterCheck != null)
                _chip('Vann: ${e.nextWaterCheck!.day}.${e.nextWaterCheck!.month}.${e.nextWaterCheck!.year}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String t) => Chip(
        label: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11)),
        backgroundColor: Colors.white24,
      );

  Widget _quickActions() {
    final actions = [
      (MaintenanceType.service, 'Service', Icons.engineering),
      (MaintenanceType.waterFill, 'Vann', Icons.water_drop),
      (MaintenanceType.repair, 'Fikset', Icons.build),
      (MaintenanceType.wash, 'Vasket', Icons.local_car_wash),
      (MaintenanceType.storage, 'Lagret', Icons.warehouse),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((a) {
        return ActionChip(
          avatar: Icon(a.$3, size: 18, color: DriftProTheme.primaryGreen),
          label: Text(a.$2),
          onPressed: () => _openEntry(a.$1),
        );
      }).toList(),
    );
  }

  Widget _reminderCard(EquipmentServiceReminder r) {
    final names = r.notifyUserIds
        .map((id) => widget.profileNames[id] ?? id.substring(0, 8))
        .join(', ');
    final notifyDate = r.dueDate.subtract(Duration(days: r.notifyDaysBefore));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.sms_outlined,
          color: r.smsSentAt != null ? Colors.grey : DriftProTheme.warning,
        ),
        title: Text('${r.typeLabel} – ${r.dueDate.day}.${r.dueDate.month}.${r.dueDate.year}'),
        subtitle: Text(
          'SMS til: $names\n'
          'Varsel: ${notifyDate.day}.${notifyDate.month}.${notifyDate.year}\n'
          '${r.smsSentAt != null ? 'Sendt ${r.smsSentAt!.day}.${r.smsSentAt!.month}' : 'Venter på varseldato'}',
        ),
        trailing: _canWrite && r.smsSentAt == null
            ? IconButton(
                icon: const Icon(Icons.send),
                tooltip: 'Send SMS nå',
                onPressed: () async {
                  final n =
                      await EquipmentService.sendReminderSmsNow(r.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$n SMS i kø')),
                    );
                    _load();
                  }
                },
              )
            : null,
      ),
    );
  }

  Widget _logCard(EquipmentMaintenanceLog log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.15),
          child: Icon(_iconForType(log.type), color: DriftProTheme.primaryGreen),
        ),
        title: Text(log.type.label),
        subtitle: Text(
          '${log.performedAt.day}.${log.performedAt.month}.${log.performedAt.year} '
          '${log.performedAt.hour}:${log.performedAt.minute.toString().padLeft(2, '0')}'
          '${log.odometerOrHours != null ? '\n${log.odometerOrHours}' : ''}'
          '${log.notes != null ? '\n${log.notes}' : ''}'
          '${log.nextDueAt != null ? '\nNeste: ${log.nextDueAt!.day}.${log.nextDueAt!.month}.${log.nextDueAt!.year}' : ''}',
        ),
        trailing: log.documentUrls.isNotEmpty
            ? const Icon(Icons.attach_file, size: 18)
            : null,
        onTap: log.documentUrls.isNotEmpty
            ? () => launchUrl(Uri.parse(log.documentUrls.first))
            : null,
      ),
    );
  }
}
