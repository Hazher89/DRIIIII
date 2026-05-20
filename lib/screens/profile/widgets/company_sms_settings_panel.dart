import 'package:flutter/material.dart';

import '../../../core/services/sms/company_sms_settings.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';

/// SMS-innstillinger (innhold uten egen Scaffold).
class CompanySmsSettingsPanel extends StatefulWidget {
  const CompanySmsSettingsPanel({super.key});

  @override
  State<CompanySmsSettingsPanel> createState() => _CompanySmsSettingsPanelState();
}

class _CompanySmsSettingsPanelState extends State<CompanySmsSettingsPanel> {
  CompanySmsSettings? _settings;
  UserProfile? _me;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _me = await SupabaseService.fetchCurrentUserProfile();
    final cid = _me?.companyId;
    if (cid == null) return;
    final s = await CompanySmsSettingsService.fetch(cid);
    if (mounted) {
      setState(() {
        _settings = s;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null || _me == null) return;
    setState(() => _saving = true);
    try {
      await CompanySmsSettingsService.save(_settings!, _me!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS-innstillinger lagret. Avsender: Mavi (Sveve).'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _patch(CompanySmsSettings Function(CompanySmsSettings) fn) {
    setState(() => _settings = fn(_settings!));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _settings!;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DriftProTheme.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Alle utgående SMS sendes fra avsender «Mavi» via Sveve. '
                  'Standard er PÅ for alle hendelsestyper. Kun superadmin ser full logg.',
                ),
              ),
              const SizedBox(height: 20),
              Text('Fravær & ferie', style: DriftProTheme.headingSm),
              SwitchListTile(
                title: const Text('Ny søknad → leder'),
                subtitle: const Text(
                  'Går til avdelingsleder. Er leder på ferie → superadmin.',
                ),
                value: s.smsAbsenceRequest,
                onChanged: (v) => _patch((x) => x.copyWith(smsAbsenceRequest: v)),
              ),
              SwitchListTile(
                title: const Text('Godkjent / avvist → ansatt'),
                value: s.smsAbsenceDecision,
                onChanged: (v) => _patch((x) => x.copyWith(smsAbsenceDecision: v)),
              ),
              const Divider(height: 32),
              Text('Avvik', style: DriftProTheme.headingSm),
              SwitchListTile(
                title: const Text('Nytt avvik → ledere'),
                value: s.smsTicketNew,
                onChanged: (v) => _patch((x) => x.copyWith(smsTicketNew: v)),
              ),
              SwitchListTile(
                title: const Text('Statusendring → den som meldte'),
                value: s.smsTicketStatus,
                onChanged: (v) => _patch((x) => x.copyWith(smsTicketStatus: v)),
              ),
              SwitchListTile(
                title: const Text('Kritiske avvik → ledere'),
                value: s.smsTicketCritical,
                onChanged: (v) => _patch((x) => x.copyWith(smsTicketCritical: v)),
              ),
              const Divider(height: 32),
              Text('Brukere', style: DriftProTheme.headingSm),
              SwitchListTile(
                title: const Text('Ny ansatt venter godkjenning → superadmin'),
                subtitle: const Text(
                  'Sendes når ansatt har fullført onboarding og venter på godkjenning.',
                ),
                value: s.smsUserApproval,
                onChanged: (v) => _patch((x) => x.copyWith(smsUserApproval: v)),
              ),
              const Divider(height: 32),
              SwitchListTile(
                title: const Text('Utstyr / truck-påminnelser'),
                value: s.smsEquipment,
                onChanged: (v) => _patch((x) => x.copyWith(smsEquipment: v)),
              ),
              SwitchListTile(
                title: const Text('Øvrige varsler til ansatte'),
                value: s.smsGeneral,
                onChanged: (v) => _patch((x) => x.copyWith(smsGeneral: v)),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: DriftProTheme.primaryGreen,
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('LAGRE SMS-INNSTILLINGER'),
            ),
          ),
        ),
      ],
    );
  }
}
