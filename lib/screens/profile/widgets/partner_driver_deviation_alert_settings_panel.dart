import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_driver_deviation_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/partner/partner_driver_deviation.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

class PartnerDriverDeviationAlertSettingsPanel extends StatefulWidget {
  const PartnerDriverDeviationAlertSettingsPanel({super.key});

  @override
  State<PartnerDriverDeviationAlertSettingsPanel> createState() =>
      _PartnerDriverDeviationAlertSettingsPanelState();
}

class _PartnerDriverDeviationAlertSettingsPanelState
    extends State<PartnerDriverDeviationAlertSettingsPanel> {
  UserProfile? _profile;
  String? _companyId;
  bool _enabled = true;
  List<String> _emails = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      final companyId =
          profile?.companyId ?? await SupabaseService.getCurrentCompanyId();
      if (companyId == null) throw StateError('Fant ikke bedriften.');
      PartnerDriverDeviationAlertSettings? settings;
      if (profile?.role == UserRole.superadmin) {
        settings = await PartnerDriverDeviationService.loadAlertSettings(
          companyId,
        );
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _companyId = companyId;
        _enabled = settings?.enabled ?? true;
        _emails = [...?settings?.emails];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _addEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Legg til mottaker'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-postadresse',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Legg til'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty) return;
    final normalized = email.toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      _message('Skriv inn en gyldig e-postadresse.', error: true);
      return;
    }
    if (!_emails.contains(normalized)) {
      setState(() => _emails.add(normalized));
    }
  }

  Future<void> _save() async {
    final companyId = _companyId;
    if (companyId == null) return;
    setState(() => _saving = true);
    try {
      await PartnerDriverDeviationService.saveAlertSettings(
        PartnerDriverDeviationAlertSettings(
          companyId: companyId,
          enabled: _enabled,
          emails: _emails,
        ),
      );
      if (mounted) _message('Varselinnstillingene er lagret.');
    } catch (e) {
      if (mounted) _message('Kunne ikke lagre: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingCenter();
    if (_error != null) return Center(child: Text(_error!));
    if (_profile?.role != UserRole.superadmin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Kun superadmin kan endre varsler for sjåføravvik.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Sjåføravvik (partner/rute)',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'E-post ved nye rute-/kundeavvik fra partner-sjåfører. '
          'Gjelder ikke HMS-avvik for MAVI-ansatte (fanen Avvik i hovedmenyen).',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        Card(
          child: SwitchListTile(
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
            secondary: const Icon(Icons.notification_important_outlined),
            title: const Text(
              'Varsle ved nye sjåføravvik',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Kun partner-sjåføravvik — ikke MAVI HMS-avvik.',
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ekstra e-postmottakere',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: _addEmail,
              icon: const Icon(Icons.add),
              label: const Text('Legg til'),
            ),
          ],
        ),
        if (_emails.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Ingen ekstra mottakere er lagt til.'),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final email in _emails)
                InputChip(
                  label: Text(email),
                  onDeleted: () => setState(() => _emails.remove(email)),
                ),
            ],
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Lagrer…' : 'Lagre innstillinger'),
        ),
      ],
    );
  }
}
