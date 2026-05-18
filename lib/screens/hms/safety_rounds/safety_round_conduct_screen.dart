import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/hms/safety_round_templates.dart';
import '../../../models/department.dart';
import '../../../core/services/hms/safety_round_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/safety_round.dart';
import '../../../core/permissions/user_access.dart';
import '../../../models/user_profile.dart';
import 'safety_round_detail_screen.dart';

/// Gjennomfør vernerunde med norsk lov-mal, signatur og arkivering.
class SafetyRoundConductScreen extends StatefulWidget {
  final SafetyRoundTemplateDef template;
  final SafetyRound? existing;

  const SafetyRoundConductScreen({
    super.key,
    required this.template,
    this.existing,
  });

  @override
  State<SafetyRoundConductScreen> createState() =>
      _SafetyRoundConductScreenState();
}

class _SafetyRoundConductScreenState extends State<SafetyRoundConductScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  late List<Map<String, dynamic>> _checklist;
  final List<Map<String, dynamic>> _findings = [];
  DateTime _scheduledDate = DateTime.now();
  DateTime? _nextRoundDate;
  String _signerRole = 'Verneombud';
  bool _submitting = false;
  bool _includeVerksted = false;
  UserProfile? _profile;
  List<UserProfile> _employees = [];
  List<Department> _departments = [];
  final Set<String> _participantIds = {};
  String? _roundDepartmentId;

  static const _roles = [
    'Verneombud',
    'Avdelingsleder',
    'Superadmin',
    'HMS-ansvarlig',
    'Annen leder',
  ];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _title.text = ex.title;
      _location.text = ex.location ?? '';
      _notes.text = ex.roundNotes ?? '';
      _checklist = List.from(ex.checklist);
      _findings.addAll(ex.findings);
      _scheduledDate = ex.scheduledDate ?? DateTime.now();
      _nextRoundDate = ex.nextRoundDate;
      _signerRole = ex.signerRole ?? 'Verneombud';
      _roundDepartmentId = ex.departmentId;
      _participantIds.addAll(ex.participantIds);
    } else {
      _title.text = widget.template.title;
      _checklist = widget.template.toChecklistItems();
    }
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final p = await SupabaseService.fetchCurrentUserProfile();
    final companyId = p?.companyId;
    if (companyId == null) {
      if (mounted) setState(() => _profile = p);
      return;
    }
    final users = await SupabaseService.fetchProfiles(companyId: companyId);
    final depts = await SupabaseService.fetchDepartments(companyId: companyId);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _employees = users.where((u) => u.isApproved && u.isActive).toList();
      _departments = depts;
      _roundDepartmentId ??= p?.departmentId;
      if (_participantIds.isEmpty && p != null) {
        _participantIds.add(p.id);
      }
    });
  }

  void _applyVerkstedMerge() {
    if (!_includeVerksted) return;
    final extra = SafetyRoundTemplates.verksted.toChecklistItems();
    final existing = _checklist.map((e) => e['task']).toSet();
    for (final item in extra) {
      if (!existing.contains(item['task'])) _checklist.add(item);
    }
  }

  bool get _canConduct {
    if (_profile == null) return false;
    if (_profile!.role == UserRole.superadmin ||
        _profile!.role == UserRole.admin ||
        _profile!.role == UserRole.leder) {
      return true;
    }
    return _profile!.access.canHmsSafetyRound;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> get _participantNames {
    final names = <String>[];
    for (final id in _participantIds) {
      for (final e in _employees) {
        if (e.id == id) {
          names.add(e.fullName);
          break;
        }
      }
    }
    return names;
  }

  String _archiveNumber() {
    final now = DateTime.now();
    return 'VR-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecond % 10000}';
  }

  Map<String, dynamic> _buildSignature({bool draft = false}) {
    final now = DateTime.now();
    if (draft) {
      return {
        'draft': true,
        'participant_ids': _participantIds.toList(),
        'participant_names': _participantNames,
        'notes': _notes.text.trim(),
      };
    }
    return {
      'signed_at': now.toIso8601String(),
      'signed_by_id': _profile!.id,
      'signed_by_name': _profile!.fullName,
      'signer_role': _signerRole,
      'stamp':
          'STEMPELT ${now.day}.${now.month}.${now.year} ${now.hour}:${now.minute.toString().padLeft(2, "0")}',
      'participant_ids': _participantIds.toList(),
      'participant_names': _participantNames,
      'notes': _notes.text.trim(),
    };
  }

  Future<void> _saveDraft() async {
    if (_title.text.trim().isEmpty || _profile?.companyId == null) return;
    setState(() => _submitting = true);
    try {
      final round = SafetyRound(
        id: widget.existing?.id ?? const Uuid().v4(),
        companyId: _profile!.companyId!,
        departmentId: _roundDepartmentId,
        conductedBy: _profile!.id,
        title: _title.text.trim(),
        templateId: widget.template.id,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        archiveNumber: widget.existing?.archiveNumber ?? _archiveNumber(),
        checklist: _checklist,
        findings: _findings,
        overallStatus: 'utkast',
        scheduledDate: _scheduledDate,
        nextRoundDate: _nextRoundDate,
        signature: _buildSignature(draft: true),
        conductorName: _profile!.fullName,
      );
      await SafetyRoundService.save(round, id: widget.existing?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utkast lagret – du finner den i arkivet')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _finish() async {
    if (_title.text.trim().isEmpty) return;
    if (!_canConduct) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Du har ikke tilgang til å fullføre vernerunde'),
        ),
      );
      return;
    }
    final pending = _checklist.where((e) => e['status'] == 'pending').length;
    if (pending > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uferdige punkter'),
          content: Text('$pending punkter er ikke besvart. Fullføre likevel?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Fullfør')),
          ],
        ),
      );
      if (go != true) return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Signer og arkiver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Utført av: ${_profile?.fullName ?? "—"}'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _signerRole,
              decoration: const InputDecoration(labelText: 'Rolle ved signering'),
              items: _roles
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _signerRole = v ?? _signerRole),
            ),
            const SizedBox(height: 12),
            const Text(
              'Vernerunden stemplés med dato/tid og lagres permanent i arkiv. PDF kan lastes ned etterpå.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Signer & lagre'),
          ),
        ],
      ),
    );
    if (confirm != true || _profile?.companyId == null) return;

    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Velg minst én deltaker i vernerunden')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      _applyVerkstedMerge();
      final now = DateTime.now();

      var round = SafetyRound(
        id: widget.existing?.id ?? const Uuid().v4(),
        companyId: _profile!.companyId!,
        departmentId: _roundDepartmentId,
        conductedBy: _profile!.id,
        title: _title.text.trim(),
        templateId: widget.template.id,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        archiveNumber: widget.existing?.archiveNumber ?? _archiveNumber(),
        checklist: _checklist,
        findings: _findings,
        overallStatus: 'fullført',
        scheduledDate: _scheduledDate,
        completedAt: now,
        nextRoundDate: _nextRoundDate,
        signature: _buildSignature(),
        conductorName: _profile!.fullName,
      );

      round = await SafetyRoundService.save(
        round,
        id: widget.existing?.id,
      );
      round = await SafetyRoundService.finalizeWithPdf(round);

      if (!mounted) return;
      final roundId = round.id;
      Navigator.pop(context, roundId);
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SafetyRoundDetailScreen(roundId: roundId),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Feil: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _setStatus(Map<String, dynamic> item, String status) {
    setState(() {
      item['status'] = status;
      item['checked_at'] = DateTime.now().toIso8601String();
    });
  }

  void _editComment(Map<String, dynamic> item) {
    final c = TextEditingController(text: item['comment'] as String? ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item['task'] as String? ?? 'Kommentar'),
        content: TextField(
          controller: c,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Kommentar / tiltak'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Lukk')),
          ElevatedButton(
            onPressed: () {
              setState(() => item['comment'] = c.text);
              Navigator.pop(ctx);
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
  }

  void _addFinding() {
    final desc = TextEditingController();
    var severity = 'Middels';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrer avvik/funn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: desc,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Beskrivelse'),
            ),
            DropdownButtonFormField<String>(
              value: severity,
              items: ['Lav', 'Middels', 'Høy', 'Kritisk']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => severity = v ?? severity,
              decoration: const InputDecoration(labelText: 'Alvorlighet'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          ElevatedButton(
            onPressed: () {
              if (desc.text.isNotEmpty) {
                setState(() => _findings.add({
                      'description': desc.text,
                      'severity': severity,
                      'registered_at': DateTime.now().toIso8601String(),
                    }));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Legg til'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final item in _checklist) {
      final key = item['section_title'] as String? ?? 'Annet';
      sections.putIfAbsent(key, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vernerunde'),
            Text(
              widget.template.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: _submitting ? null : _saveDraft,
                child: const Text('LAGRE UTKAST'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _submitting || !_canConduct ? null : _finish,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: DriftProTheme.primaryGreen,
                ),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('SIGNER, STEMPEL & ARKIVER'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _banner(),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Tittel / periode'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Sted (kontor, lager, avdeling)',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dato for runde'),
            subtitle: Text(
              '${_scheduledDate.day}.${_scheduledDate.month}.${_scheduledDate.year}',
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _scheduledDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (d != null) setState(() => _scheduledDate = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Neste vernerunde (påminnelse)'),
            subtitle: Text(
              _nextRoundDate == null
                  ? 'Ikke satt'
                  : '${_nextRoundDate!.day}.${_nextRoundDate!.month}.${_nextRoundDate!.year}',
            ),
            trailing: const Icon(Icons.event_repeat),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _nextRoundDate ?? DateTime.now().add(const Duration(days: 90)),
                firstDate: DateTime.now(),
                lastDate: DateTime(2035),
              );
              if (d != null) setState(() => _nextRoundDate = d);
            },
          ),
          if (_departments.isNotEmpty)
            DropdownButtonFormField<String?>(
              value: _roundDepartmentId,
              decoration: const InputDecoration(labelText: 'Avdeling / område'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Hele bedriften')),
                ..._departments.map(
                  (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                ),
              ],
              onChanged: (v) => setState(() => _roundDepartmentId = v),
            ),
          const SizedBox(height: 8),
          Text('Deltakere i vernerunden', style: DriftProTheme.headingSm),
          const SizedBox(height: 4),
          Text(
            'Velg hvem som er med (verneombud, leder, ansatte).',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _employees.map((e) {
              final sel = _participantIds.contains(e.id);
              return FilterChip(
                label: Text(e.fullName),
                selected: sel,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _participantIds.add(e.id);
                    } else {
                      _participantIds.remove(e.id);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Merknader / fokus for denne runden',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Legg til verksted & produksjon'),
            subtitle: const Text('Ekstra sjekkpunkter for maskiner og kjemikalier'),
            value: _includeVerksted,
            onChanged: (v) => setState(() => _includeVerksted = v),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sjekkliste (${_checklist.length} punkter)',
                  style: DriftProTheme.headingSm),
              Text(
                'OK ${_checklist.where((e) => e['status'] == 'ok').length} · '
                'Avvik ${_checklist.where((e) => e['status'] == 'avvik').length}',
                style: DriftProTheme.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...sections.entries.map((entry) {
            final legal = entry.value.first['legal_ref'] as String?;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? DriftProTheme.cardDark
                        : DriftProTheme.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (legal != null)
                        Text(legal, style: DriftProTheme.caption),
                    ],
                  ),
                ),
                ...entry.value.map((item) => _checkTile(item, isDark)),
              ],
            );
          }),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Avvik / funn', style: DriftProTheme.headingSm),
              TextButton.icon(
                onPressed: _addFinding,
                icon: const Icon(Icons.add),
                label: const Text('Legg til'),
              ),
            ],
          ),
          ..._findings.map(
            (f) => Card(
              child: ListTile(
                title: Text(f['description'] as String),
                subtitle: Text('Alvorlighet: ${f['severity']}'),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.success.withValues(alpha: 0.9),
            Colors.teal.shade700,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Norsk lov – kontor, lager, rømning, brann, ansatte og organisering. '
        'Kan utføres av verneombud, leder eller superadmin.',
        style: TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _checkTile(Map<String, dynamic> item, bool isDark) {
    final status = item['status'] as String? ?? 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          ListTile(
            title: Text(item['task'] as String? ?? ''),
            subtitle: (item['comment'] as String?)?.isNotEmpty == true
                ? Text(item['comment'] as String)
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.comment_outlined, size: 20),
                  onPressed: () => _editComment(item),
                ),
                _statusBtn(item, 'ok', Icons.check_circle, Colors.green, status),
                _statusBtn(item, 'avvik', Icons.warning_amber, Colors.orange, status),
                _statusBtn(item, 'n/a', Icons.remove_circle_outline, Colors.grey, status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBtn(
    Map<String, dynamic> item,
    String value,
    IconData icon,
    Color color,
    String current,
  ) {
    final sel = current == value;
    return IconButton(
      icon: Icon(icon, color: sel ? color : color.withValues(alpha: 0.25)),
      onPressed: () => _setStatus(item, value),
    );
  }
}
