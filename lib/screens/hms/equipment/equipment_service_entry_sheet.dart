import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/hms/equipment_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/equipment.dart';
import '../../../models/user_profile.dart';

/// Registrer linje i servicehefte (service, vann, vask, reparasjon, lager).
class EquipmentServiceEntrySheet extends StatefulWidget {
  final Equipment equipment;
  final UserProfile profile;
  final MaintenanceType initialType;
  final Map<String, String> profileNames;
  final EquipmentNotificationSettings settings;

  const EquipmentServiceEntrySheet({
    super.key,
    required this.equipment,
    required this.profile,
    required this.initialType,
    required this.profileNames,
    required this.settings,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Equipment equipment,
    required UserProfile profile,
    required MaintenanceType type,
    required Map<String, String> profileNames,
    required EquipmentNotificationSettings settings,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EquipmentServiceEntrySheet(
          equipment: equipment,
          profile: profile,
          initialType: type,
          profileNames: profileNames,
          settings: settings,
        ),
      ),
    );
  }

  @override
  State<EquipmentServiceEntrySheet> createState() =>
      _EquipmentServiceEntrySheetState();
}

class _EquipmentServiceEntrySheetState extends State<EquipmentServiceEntrySheet> {
  late MaintenanceType _type;
  final _notes = TextEditingController();
  final _odometer = TextEditingController();
  final _cost = TextEditingController();
  DateTime? _nextDue;
  DateTime? _notifyOn;
  bool _scheduleSms = true;
  final Set<String> _notifyIds = {};
  List<String> _docs = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _suggestNextDue();
    if (widget.equipment.responsibleUserId != null) {
      _notifyIds.add(widget.equipment.responsibleUserId!);
    }
    if (widget.equipment.assignedTo != null) {
      _notifyIds.add(widget.equipment.assignedTo!);
    }
  }

  void _suggestNextDue() {
    final s = widget.settings;
    final days = _type == MaintenanceType.waterFill
        ? s.truckWaterIntervalDays
        : s.truckServiceIntervalDays;
    setState(() {
      _nextDue = DateTime.now().add(Duration(days: days));
      _syncNotifyOnFromDue();
    });
  }

  void _syncNotifyOnFromDue() {
    final due = _nextDue;
    if (due == null) return;
    var notify = due.subtract(
      Duration(days: widget.settings.defaultNotifyDaysBefore),
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (notify.isBefore(todayDate)) notify = todayDate;
    _notifyOn = notify;
  }

  int get _notifyDaysBefore {
    final due = _nextDue;
    final notify = _notifyOn;
    if (due == null || notify == null) {
      return widget.settings.defaultNotifyDaysBefore;
    }
    final dueDate = DateTime(due.year, due.month, due.day);
    final notifyDate = DateTime(notify.year, notify.month, notify.day);
    return dueDate.difference(notifyDate).inDays.clamp(0, 365);
  }

  String _fmt(DateTime d) => '${d.day}.${d.month}.${d.year}';

  Future<void> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (r == null || widget.profile.companyId == null) return;
    for (final f in r.files) {
      if (f.bytes == null) continue;
      final url = await EquipmentService.uploadDocument(
        companyId: widget.profile.companyId!,
        fileName: f.name,
        bytes: f.bytes!,
        subfolder: 'servicehefte',
      );
      setState(() => _docs.add(url));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await EquipmentService.addServiceBookEntry(
        equipment: widget.equipment,
        type: _type,
        performedBy: widget.profile.id,
        notes: _notes.text.isEmpty ? null : _notes.text,
        odometerOrHours: _odometer.text.isEmpty ? null : _odometer.text,
        cost: double.tryParse(_cost.text.replaceAll(',', '.')),
        documentUrls: _docs,
        nextDueAt: _nextDue,
        smsNotifyUserIds: _scheduleSms && _notifyIds.isNotEmpty
            ? _notifyIds.toList()
            : null,
        notifyDaysBefore: _notifyDaysBefore,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.profileNames.entries.toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ny registrering', style: DriftProTheme.headingSm),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                MaintenanceType.service,
                MaintenanceType.waterFill,
                MaintenanceType.repair,
                MaintenanceType.wash,
                MaintenanceType.storage,
                MaintenanceType.inspection,
              ].map((t) {
                return ChoiceChip(
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) {
                    setState(() {
                      _type = t;
                      _suggestNextDue();
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _odometer,
              decoration: const InputDecoration(
                labelText: 'Timer / km (valgfritt)',
              ),
            ),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beskrivelse'),
            ),
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kostnad (kr)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Neste frist'),
              subtitle: Text(
                _nextDue != null
                    ? '${_nextDue!.day}.${_nextDue!.month}.${_nextDue!.year}'
                    : '—',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _nextDue ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2035),
                );
                if (d != null) {
                  setState(() {
                    _nextDue = d;
                    _syncNotifyOnFromDue();
                  });
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('SMS-varsel til valgte ansatte'),
              subtitle: Text(
                _notifyOn != null && _nextDue != null
                    ? 'Planlagt varsel ${_fmt(_notifyOn!)} (frist ${_fmt(_nextDue!)})'
                    : 'Velg ansatt og varseldato',
              ),
              value: _scheduleSms,
              onChanged: (v) => setState(() => _scheduleSms = v),
            ),
            if (_scheduleSms) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dato for varsel'),
                subtitle: Text(
                  _notifyOn != null ? _fmt(_notifyOn!) : '—',
                ),
                trailing: const Icon(Icons.notifications_active_outlined),
                onTap: _nextDue == null
                    ? null
                    : () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _notifyOn ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: _nextDue!,
                        );
                        if (d != null) setState(() => _notifyOn = d);
                      },
              ),
              Text('Varsle ansatt:', style: DriftProTheme.labelSm),
              ...profiles.map((e) {
                final selected = _notifyIds.contains(e.key);
                return CheckboxListTile(
                  dense: true,
                  title: Text(e.value),
                  subtitle: selected && _notifyOn != null
                      ? Text('SMS ${_fmt(_notifyOn!)}')
                      : null,
                  value: selected,
                  onChanged: (on) {
                    setState(() {
                      if (on == true) {
                        _notifyIds.add(e.key);
                      } else {
                        _notifyIds.remove(e.key);
                      }
                    });
                  },
                );
              }),
              if (_notifyIds.isNotEmpty && _notifyOn != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    '${_notifyIds.length} ansatt(er) får varsel ${_fmt(_notifyOn!)} '
                    'om truck-service (frist ${_fmt(_nextDue!)}).',
                    style: DriftProTheme.caption.copyWith(
                      color: DriftProTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            OutlinedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.attach_file),
              label: Text('Vedlegg (${_docs.length})'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('LAGRE I SERVICEHEFTE'),
            ),
          ],
        ),
      ),
    );
  }
}
