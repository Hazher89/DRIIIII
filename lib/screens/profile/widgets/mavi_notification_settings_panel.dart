import 'package:flutter/material.dart';

import '../../../core/services/notification/mavi_notification_settings_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/mavi_notification_settings.dart';
import '../../../models/user_profile.dart';
import 'notification_channel_picker.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Kun MAVI-ansatte — tydelig adskilt fra samarbeid.
class MaviNotificationSettingsPanel extends StatefulWidget {
  const MaviNotificationSettingsPanel({super.key});

  @override
  State<MaviNotificationSettingsPanel> createState() =>
      _MaviNotificationSettingsPanelState();
}

class _MaviNotificationSettingsPanelState extends State<MaviNotificationSettingsPanel> {
  MaviNotificationSettings? _s;
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
    final settings = await MaviNotificationSettingsService.fetch(cid);
    if (mounted) setState(() { _s = settings; _loading = false; });
  }

  Future<void> _save() async {
    if (_s == null || _me == null) return;
    setState(() => _saving = true);
    try {
      await MaviNotificationSettingsService.save(_s!, _me!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MAVI-varsel lagret')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _s == null) {
      return const DriftProLoadingCenter();
    }
    final s = _s!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(
                'MAVI-ansatte',
                'Fravær, avvik, utstyr og interne varsler om samarbeid. '
                'SMS fra Mavi · e-post fra ikkesvar@driftpro.no',
                Icons.badge_outlined,
              ),
              const SizedBox(height: 16),
              Text('Fravær & ferie', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Ny søknad → leder',
                value: s.chAbsenceRequest,
                onChanged: (v) => setState(() => _s = s.copyWith(chAbsenceRequest: v)),
              ),
              NotificationChannelTile(
                title: 'Godkjent / avvist → ansatt',
                value: s.chAbsenceDecision,
                onChanged: (v) => setState(() => _s = s.copyWith(chAbsenceDecision: v)),
              ),
              const Divider(height: 28),
              Text('Avvik (HMS)', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Nytt avvik → ledere',
                value: s.chTicketNew,
                onChanged: (v) => setState(() => _s = s.copyWith(chTicketNew: v)),
              ),
              NotificationChannelTile(
                title: 'Statusendring → melder',
                value: s.chTicketStatus,
                onChanged: (v) => setState(() => _s = s.copyWith(chTicketStatus: v)),
              ),
              NotificationChannelTile(
                title: 'Kritiske avvik',
                value: s.chTicketCritical,
                onChanged: (v) => setState(() => _s = s.copyWith(chTicketCritical: v)),
              ),
              const Divider(height: 28),
              Text('Brukere & drift', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Ny ansatt venter godkjenning',
                value: s.chUserApproval,
                onChanged: (v) => setState(() => _s = s.copyWith(chUserApproval: v)),
              ),
              NotificationChannelTile(
                title: 'Utstyr / truck',
                value: s.chEquipment,
                onChanged: (v) => setState(() => _s = s.copyWith(chEquipment: v)),
              ),
              NotificationChannelTile(
                title: 'Øvrige varsler',
                value: s.chGeneral,
                onChanged: (v) => setState(() => _s = s.copyWith(chGeneral: v)),
              ),
              const Divider(height: 28),
              Text('Intern oversikt — samarbeid', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Partner avviste rute (intern)',
                subtitle: 'Kun ved avvisning — ikke ved aksept',
                value: s.chPartnerRouteAckInternal,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerRouteAckInternal: v)),
              ),
              NotificationChannelTile(
                title: 'Ruter som venter på aksept (daglig)',
                subtitle: 'Oppsummering til ledere',
                value: s.chPartnerRoutePendingInternal,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerRoutePendingInternal: v)),
              ),
              NotificationChannelTile(
                title: 'SAP rute-PDF mottatt',
                subtitle: 'Ny fil i SAP-innboks',
                value: s.chSapRouteReceived,
                onChanged: (v) => setState(() => _s = s.copyWith(chSapRouteReceived: v)),
              ),
              NotificationChannelTile(
                title: 'Bilutleie-hendelser',
                value: s.chPartnerRentalInternal,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerRentalInternal: v)),
              ),
              NotificationChannelTile(
                title: 'Dokument lastet opp til partner',
                subtitle: 'Valgfritt internt varsel',
                value: s.chPartnerDocumentInternal,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerDocumentInternal: v)),
              ),
              NotificationChannelTile(
                title: 'Bedrift deaktivert',
                value: s.chPartnerDeactivatedInternal,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerDeactivatedInternal: v)),
              ),
              const SizedBox(height: 72),
            ],
          ),
        ),
        _saveBar(_saving, _save),
      ],
    );
  }
}

Widget _header(String title, String body, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: DriftProTheme.primaryGreen.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: DriftProTheme.primaryGreen),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DriftProTheme.headingSm),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _saveBar(bool saving, VoidCallback onSave) {
  return Material(
    elevation: 8,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: saving ? null : onSave,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: DriftProTheme.primaryGreen,
        ),
        child: saving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('LAGRE MAVI-VARSEL'),
      ),
    ),
  );
}
