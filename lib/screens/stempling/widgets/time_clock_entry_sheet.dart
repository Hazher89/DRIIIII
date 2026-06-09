import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/time_clock/time_timesheet_entry.dart';
import '../../../models/time_clock/time_work_type.dart';

/// Avansert skjema for å legge til eller redigere timeregistrering.
class TimeClockEntrySheet extends StatefulWidget {
  const TimeClockEntrySheet({
    super.key,
    this.entry,
    required this.workDate,
    required this.profileId,
    required this.companyId,
    required this.workTypes,
  });

  final TimeTimesheetEntry? entry;
  final DateTime workDate;
  final String profileId;
  final String companyId;
  final List<TimeWorkType> workTypes;

  static Future<TimeTimesheetEntry?> show(
    BuildContext context, {
    TimeTimesheetEntry? entry,
    required DateTime workDate,
    required String profileId,
    required String companyId,
    required List<TimeWorkType> workTypes,
  }) {
    return showModalBottomSheet<TimeTimesheetEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: TimeClockEntrySheet(
          entry: entry,
          workDate: workDate,
          profileId: profileId,
          companyId: companyId,
          workTypes: workTypes,
        ),
      ),
    );
  }

  @override
  State<TimeClockEntrySheet> createState() => _TimeClockEntrySheetState();
}

class _TimeClockEntrySheetState extends State<TimeClockEntrySheet> {
  late String _workTypeId;
  TimeOfDay? _start;
  TimeOfDay? _end;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _projectCtrl;
  late final TextEditingController _activityCtrl;
  late final TextEditingController _noteCtrl;
  bool _manualHours = false;

  bool get _isEdit => widget.entry != null;
  bool get _isLocked => widget.entry?.isLocked ?? false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final defaultType = widget.workTypes.firstWhere(
      (t) => t.isDefaultPunch,
      orElse: () => widget.workTypes.first,
    );
    _workTypeId = e?.workTypeId ?? defaultType.id;
    _start = _parseTime(e?.startTime);
    _end = _parseTime(e?.endTime);
    _hoursCtrl = TextEditingController(
      text: (e?.hours ?? 0).toStringAsFixed(2).replaceAll('.', ','),
    );
    _projectCtrl = TextEditingController(text: e?.project ?? '');
    _activityCtrl = TextEditingController(text: e?.activity ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _manualHours = e != null && (_start == null || _end == null);
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _projectCtrl.dispose();
    _activityCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String? _formatTime(TimeOfDay? t) =>
      t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  void _recalcHours() {
    if (_manualHours || _start == null || _end == null) return;
    final startMin = _start!.hour * 60 + _start!.minute;
    var endMin = _end!.hour * 60 + _end!.minute;
    if (endMin <= startMin) endMin += 24 * 60;
    final hours = (endMin - startMin) / 60.0;
    _hoursCtrl.text = hours.toStringAsFixed(2).replaceAll('.', ',');
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 8, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _recalcHours();
    });
  }

  void _submit() {
    final hours = double.tryParse(_hoursCtrl.text.replaceAll(',', '.')) ?? 0;
    if (hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Angi timer større enn 0')),
      );
      return;
    }

    final base = widget.entry;
    Navigator.pop(
      context,
      TimeTimesheetEntry(
        id: base?.id ?? '',
        profileId: widget.profileId,
        companyId: widget.companyId,
        workDate: widget.workDate,
        workTypeId: _workTypeId,
        startTime: _formatTime(_start),
        endTime: _formatTime(_end),
        hours: hours,
        project: _projectCtrl.text.trim().isEmpty ? null : _projectCtrl.text.trim(),
        activity: _activityCtrl.text.trim().isEmpty ? null : _activityCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        isLocked: base?.isLocked ?? false,
        isApproved: base?.isApproved ?? false,
        source: base?.source ?? 'manual',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wt = widget.workTypes.cast<TimeWorkType?>().firstWhere(
          (t) => t?.id == _workTypeId,
          orElse: () => widget.workTypes.isNotEmpty ? widget.workTypes.first : null,
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isEdit ? 'Rediger registrering' : 'Legg til timer',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.workDate.day}.${widget.workDate.month}.${widget.workDate.year}',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _workTypeId,
            decoration: InputDecoration(
              labelText: 'Arbeidstype',
              prefixIcon: Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: wt?.color ?? DriftProTheme.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
              border: const OutlineInputBorder(),
            ),
            items: widget.workTypes
                .map((t) => DropdownMenuItem(value: t.id, child: Text(t.label)))
                .toList(),
            onChanged: _isLocked ? null : (v) => setState(() => _workTypeId = v!),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timeField(
                  label: 'Fra',
                  value: _start,
                  onTap: _isLocked ? null : () => _pickTime(start: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeField(
                  label: 'Til',
                  value: _end,
                  onTap: _isLocked ? null : () => _pickTime(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _hoursCtrl,
            readOnly: _isLocked,
            decoration: InputDecoration(
              labelText: 'Timer',
              suffixText: 't',
              border: const OutlineInputBorder(),
              helperText: _manualHours ? null : 'Beregnes automatisk fra fra/til',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
            onChanged: (_) => _manualHours = true,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _projectCtrl,
            readOnly: _isLocked,
            decoration: const InputDecoration(
              labelText: 'Prosjekt',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _activityCtrl,
            readOnly: _isLocked,
            decoration: const InputDecoration(
              labelText: 'Aktivitet',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.task_alt_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteCtrl,
            readOnly: _isLocked,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notat',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Avbryt'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isLocked ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                  ),
                  child: const Text('Lagre'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeField({
    required String label,
    required TimeOfDay? value,
    required VoidCallback? onTap,
  }) {
    final text = value == null
        ? '—'
        : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.schedule, size: 20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
