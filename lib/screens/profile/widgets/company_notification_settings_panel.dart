import 'package:flutter/material.dart';

import '../../../core/services/notification/company_notification_settings_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/company_notification_settings.dart';
import '../../../models/user_profile.dart';
import 'notification_channel_picker.dart';
import '../../../widgets/driftpro_loading_indicator.dart';

/// Firmavide varselkanaler (MAVI-ansatte + samarbeidspartnere).
class CompanyNotificationSettingsPanel extends StatefulWidget {
  const CompanyNotificationSettingsPanel({super.key});

  @override
  State<CompanyNotificationSettingsPanel> createState() =>
      _CompanyNotificationSettingsPanelState();
}

class _CompanyNotificationSettingsPanelState
    extends State<CompanyNotificationSettingsPanel> {
  CompanyNotificationSettings? _settings;
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
    final s = await CompanyNotificationSettingsService.fetch(cid);
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
      await CompanyNotificationSettingsService.save(_settings!, _me!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Varselinnstillinger lagret. SMS fra Mavi, e-post fra ikkesvar@driftpro.no.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _patch(CompanyNotificationSettings Function(CompanyNotificationSettings) fn) {
    setState(() => _settings = fn(_settings!));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const DriftProLoadingCenter();
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
                  'Per hendelse velger du: Kun SMS, Kun e-post, SMS + e-post, eller Av. '
                  'Ikke sendte varsler logges under «Ikke sendt».',
                ),
              ),
              const SizedBox(height: 20),
              Text('MAVI — fravær & ferie', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Ny søknad → leder',
                subtitle: 'Går til avdelingsleder (eller superadmin ved ferie).',
                value: s.chAbsenceRequest,
                onChanged: (v) => _patch((x) => x.copyWith(chAbsenceRequest: v)),
              ),
              NotificationChannelTile(
                title: 'Godkjent / avvist → ansatt',
                value: s.chAbsenceDecision,
                onChanged: (v) => _patch((x) => x.copyWith(chAbsenceDecision: v)),
              ),
              const Divider(height: 32),
              Text('MAVI — avvik', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Nytt avvik → ledere',
                value: s.chTicketNew,
                onChanged: (v) => _patch((x) => x.copyWith(chTicketNew: v)),
              ),
              NotificationChannelTile(
                title: 'Statusendring → melder',
                value: s.chTicketStatus,
                onChanged: (v) => _patch((x) => x.copyWith(chTicketStatus: v)),
              ),
              NotificationChannelTile(
                title: 'Kritiske avvik → ledere',
                value: s.chTicketCritical,
                onChanged: (v) => _patch((x) => x.copyWith(chTicketCritical: v)),
              ),
              const Divider(height: 32),
              Text('MAVI — øvrig', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Ny ansatt venter godkjenning',
                value: s.chUserApproval,
                onChanged: (v) => _patch((x) => x.copyWith(chUserApproval: v)),
              ),
              NotificationChannelTile(
                title: 'Utstyr / truck-påminnelser',
                value: s.chEquipment,
                onChanged: (v) => _patch((x) => x.copyWith(chEquipment: v)),
              ),
              NotificationChannelTile(
                title: 'Øvrige varsler til ansatte',
                value: s.chGeneral,
                onChanged: (v) => _patch((x) => x.copyWith(chGeneral: v)),
              ),
              const Divider(height: 32),
              Text('Samarbeid — partnere', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Rute varsling (sjåfør)',
                value: s.chPartnerRoute,
                onChanged: (v) => _patch((x) => x.copyWith(chPartnerRoute: v)),
              ),
              NotificationChannelTile(
                title: 'Rute varsling (bil-eier)',
                value: s.chPartnerRouteOwner,
                onChanged: (v) => _patch((x) => x.copyWith(chPartnerRouteOwner: v)),
              ),
              NotificationChannelTile(
                title: 'Møte / oppfølging',
                value: s.chPartnerMeeting,
                onChanged: (v) => _patch((x) => x.copyWith(chPartnerMeeting: v)),
              ),
              NotificationChannelTile(
                title: 'Portal (passord / innlogging)',
                value: s.chPartnerPortal,
                onChanged: (v) => _patch((x) => x.copyWith(chPartnerPortal: v)),
              ),
              NotificationChannelTile(
                title: 'Manuell SMS/e-post fra hub',
                value: s.chPartnerCompose,
                onChanged: (v) => _patch((x) => x.copyWith(chPartnerCompose: v)),
              ),
              NotificationChannelTile(
                title: 'Bilutleie — ny forespørsel',
                value: s.chVehicleRental,
                onChanged: (v) => _patch((x) => x.copyWith(chVehicleRental: v)),
              ),
              NotificationChannelTile(
                title: 'Bilutleie — status',
                value: s.chVehicleRentalStatus,
                onChanged: (v) => _patch((x) => x.copyWith(chVehicleRentalStatus: v)),
              ),
              NotificationChannelTile(
                title: 'Øvrig samarbeid',
                value: s.chPartnerGeneral,
                onChanged: (v) => _patch((x) => x.copyWith(chPartnerGeneral: v)),
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
                  : const Text('LAGRE VARSELINNSTILLINGER'),
            ),
          ),
        ),
      ],
    );
  }
}
