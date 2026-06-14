import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/services/time_clock/time_clock_service.dart';
import '../../../models/time_clock/time_overtime_summary.dart';
import '../../../models/user_profile.dart';
import '../widgets/stempling_save_bar.dart';

class TimeClockSettingsTab extends StatefulWidget {
  const TimeClockSettingsTab({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<TimeClockSettingsTab> createState() => _TimeClockSettingsTabState();
}

class _TimeClockSettingsTabState extends State<TimeClockSettingsTab> {
  final _slugCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _resetCtrl = TextEditingController(text: '4');
  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _kioskUrl;
  String? _kioskUrlLegacy;
  List<UserProfile> _employees = [];
  String? _pinProfileId;
  final _pinCtrl = TextEditingController();
  bool _grantMobile = false;
  TimeOvertimeSettings _overtime = TimeClockService.defaultOvertimeSettings();
  String _overtimeRegime = 'standard';

  @override
  void initState() {
    super.initState();
    _slugCtrl.addListener(_markDirty);
    _nameCtrl.addListener(_markDirty);
    _resetCtrl.addListener(_markDirty);
    _pinCtrl.addListener(_markDirty);
    _load();
  }

  @override
  void dispose() {
    _slugCtrl.dispose();
    _nameCtrl.dispose();
    _resetCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_loading && mounted) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _dirty = false;
    });
    try {
      final res = await TimeClockService.getSettings();
      if (res['ok'] == true) {
        _slugCtrl.text = res['kiosk_slug'] as String? ?? '';
        _nameCtrl.text = res['display_name'] as String? ?? '';
        _resetCtrl.text = '${res['punch_reset_seconds'] ?? 4}';
        _enabled = res['kiosk_enabled'] as bool? ?? true;
        _kioskUrl = res['kiosk_url'] as String? ?? '/stemple';
        _kioskUrlLegacy = res['kiosk_url_legacy'] as String?;
        _overtime = TimeClockService.parseOvertimeSettings(
          res['overtime'] as Map<String, dynamic>?,
        );
        _overtimeRegime = _overtime.overtimeRegime;
      }
      final companyId = widget.profile.companyId;
      if (companyId != null) {
        final emps = await SupabaseService.fetchProfiles(companyId: companyId);
        _employees = emps.where((e) => e.partnerId == null).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _dirty = false;
        });
      }
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      await TimeClockService.updateSettings({
        'kiosk_slug': _slugCtrl.text.trim(),
        'display_name': _nameCtrl.text.trim(),
        'kiosk_enabled': _enabled,
        'punch_reset_seconds': int.tryParse(_resetCtrl.text) ?? 4,
        'overtime': _overtime.copyWithRegime(_overtimeRegime).toPayload(),
      });

      if (_pinProfileId != null && _pinCtrl.text.isNotEmpty) {
        if (_pinCtrl.text.length > 8) {
          throw Exception('PIN kan være maks 8 siffer');
        }
        await TimeClockService.setPin(_pinProfileId!, _pinCtrl.text);
        await TimeClockService.grantMobile(_pinProfileId!, _grantMobile);
        _pinCtrl.clear();
      }

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Endringer lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lagring feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncAllPins() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sett standard-PIN for alle?'),
        content: const Text(
          'Alle ansatte med ansattnummer får PIN-kode 0. '
          'Eksisterende PIN-er overskrives.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bekreft')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final count = await TimeClockService.syncDefaultPins();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PIN 0 satt for $count ansatte')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synkronisering feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final fullUrl = '${Uri.base.origin}${_kioskUrl ?? '/stemple'}';
    final legacyUrl = _kioskUrlLegacy != null ? '${Uri.base.origin}$_kioskUrlLegacy' : null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kiosk-innstillinger',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Åpne kiosk-URL på dedikert skjerm. Ansatte logger inn med ansattnummer. '
                  'Standard PIN er 0 for alle.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Visningsnavn på kiosk',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _slugCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kiosk-slug (alternativ URL)',
                    border: OutlineInputBorder(),
                    helperText: 'Hoved-URL er /stemple — slug brukes som /stemple/{slug}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _resetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Sekunder før neste ansatt (2–30)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kiosk aktivert'),
                  value: _enabled,
                  onChanged: (v) => setState(() {
                    _enabled = v;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 16),
                const Text('Kiosk-URL', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SelectableText(fullUrl, style: const TextStyle(color: Colors.blue)),
                if (legacyUrl != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(legacyUrl, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL kopiert')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Kopier URL'),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Ansatt-PIN og mobiltilgang',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Standard PIN er 0. Endringer lagres med «Lagre endringer» nederst.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _pinProfileId,
                  decoration: const InputDecoration(
                    labelText: 'Velg ansatt (valgfritt)',
                    border: OutlineInputBorder(),
                  ),
                  items: _employees
                      .map((e) => DropdownMenuItem(value: e.id, child: Text(e.fullName)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _pinProfileId = v;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Egendefinert PIN (1–8 siffer, standard 0)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tillat mobilstempling'),
                  subtitle: const Text('Uten dette må ansatt bruke kiosk'),
                  value: _grantMobile,
                  onChanged: (v) => setState(() {
                    _grantMobile = v;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _syncAllPins,
                  icon: const Icon(Icons.pin_outlined),
                  label: const Text('Sett PIN 0 for alle ansatte'),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Overtid — arbeidsmiljøloven',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '§10-4 alminnelig arbeidstid og §10-6 overtidsregler. '
                  '40 % tillegg er lovpålagt minimum og kan ikke avspaseres.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _overtimeRegime,
                  decoration: const InputDecoration(
                    labelText: 'Overtidsregime',
                    border: OutlineInputBorder(),
                    helperText: 'Standard eller tariffavtale (§10-6 fjerde/femte ledd)',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'standard',
                      child: Text('Standard — 10/25/200 timer'),
                    ),
                    DropdownMenuItem(
                      value: 'tariff',
                      child: Text('Tariffavtale — 20/50/300 timer'),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _overtimeRegime = v ?? 'standard';
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _overtime.dailyWorkLimitHours.toStringAsFixed(0),
                        decoration: const InputDecoration(
                          labelText: 'Daglig grense (§10-4)',
                          suffixText: 't',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) {
                          final n = double.tryParse(v.replaceAll(',', '.'));
                          if (n != null) {
                            _overtime = TimeOvertimeSettings(
                              dailyWorkLimitHours: n,
                              weeklyWorkLimitHours: _overtime.weeklyWorkLimitHours,
                              overtimeSupplementPct: _overtime.overtimeSupplementPct,
                              overtimeRegime: _overtimeRegime,
                              overtimeWeeklyMax: _overtime.overtimeWeeklyMax,
                              overtimeFourWeekMax: _overtime.overtimeFourWeekMax,
                              overtimeAnnualMax: _overtime.overtimeAnnualMax,
                            );
                            _dirty = true;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: _overtime.weeklyWorkLimitHours.toStringAsFixed(0),
                        decoration: const InputDecoration(
                          labelText: 'Ukentlig grense (§10-4)',
                          suffixText: 't',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) {
                          final n = double.tryParse(v.replaceAll(',', '.'));
                          if (n != null) {
                            _overtime = TimeOvertimeSettings(
                              dailyWorkLimitHours: _overtime.dailyWorkLimitHours,
                              weeklyWorkLimitHours: n,
                              overtimeSupplementPct: _overtime.overtimeSupplementPct,
                              overtimeRegime: _overtimeRegime,
                              overtimeWeeklyMax: _overtime.overtimeWeeklyMax,
                              overtimeFourWeekMax: _overtime.overtimeFourWeekMax,
                              overtimeAnnualMax: _overtime.overtimeAnnualMax,
                            );
                            _dirty = true;
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _overtime.overtimeSupplementPct.toStringAsFixed(0),
                  decoration: const InputDecoration(
                    labelText: 'Overtidstillegg (§10-6 (11))',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    helperText: 'Minimum 40 % etter lov — kan ikke avtales lavere',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = double.tryParse(v.replaceAll(',', '.'));
                    if (n != null && n >= 40) {
                      _overtime = TimeOvertimeSettings(
                        dailyWorkLimitHours: _overtime.dailyWorkLimitHours,
                        weeklyWorkLimitHours: _overtime.weeklyWorkLimitHours,
                        overtimeSupplementPct: n,
                        overtimeRegime: _overtimeRegime,
                        overtimeWeeklyMax: _overtime.overtimeWeeklyMax,
                        overtimeFourWeekMax: _overtime.overtimeFourWeekMax,
                        overtimeAnnualMax: _overtime.overtimeAnnualMax,
                      );
                      _dirty = true;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        StemplingSaveBar(
          dirty: _dirty,
          saving: _saving,
          onSave: _saveAll,
        ),
      ],
    );
  }
}
