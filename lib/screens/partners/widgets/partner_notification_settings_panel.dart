import 'package:flutter/material.dart';

import '../../../core/services/notification/partner_notification_settings_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner_notification_settings.dart';
import '../../../models/user_profile.dart';
import '../../profile/widgets/notification_channel_picker.dart';

/// Kun samarbeidspartnere — adskilt fra MAVI-ansatte.
class PartnerNotificationSettingsPanel extends StatefulWidget {
  const PartnerNotificationSettingsPanel({super.key});

  @override
  State<PartnerNotificationSettingsPanel> createState() =>
      _PartnerNotificationSettingsPanelState();
}

class _PartnerNotificationSettingsPanelState
    extends State<PartnerNotificationSettingsPanel> {
  PartnerNotificationSettings? _s;
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
    final settings = await PartnerNotificationSettingsService.fetch(cid);
    if (mounted) setState(() { _s = settings; _loading = false; });
  }

  Future<void> _save() async {
    if (_s == null || _me == null) return;
    setState(() => _saving = true);
    try {
      await PartnerNotificationSettingsService.save(_s!, _me!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Samarbeid-varsel lagret')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _s!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.handshake_outlined, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Varsler til bil-eiere og sjåfører (samarbeid). '
                        'Gjelder ikke MAVI-ansattes fravær/avvik.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Purring rute uten aksept (timer)'),
                subtitle: Text('Første påminnelse etter ${s.routeAckReminderHours} timer'),
                trailing: SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: '${s.routeAckReminderHours}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      suffixText: 't',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final h = int.tryParse(v);
                      if (h != null && h >= 1 && h <= 168) {
                        setState(() => _s = s.copyWith(routeAckReminderHours: h));
                      }
                    },
                  ),
                ),
              ),
              const Divider(height: 24),
              Text('Ruter', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Ny rute → sjåfør',
                value: s.chPartnerRoute,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerRoute: v)),
              ),
              NotificationChannelTile(
                title: 'Ny rute → bil-eier',
                value: s.chPartnerRouteOwner,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerRouteOwner: v)),
              ),
              NotificationChannelTile(
                title: 'Purring: rute ikke akseptert',
                value: s.chPartnerRouteReminder,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerRouteReminder: v)),
              ),
              NotificationChannelTile(
                title: 'Rute godkjent (bekreftelse)',
                value: s.chPartnerRouteAccepted,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerRouteAccepted: v)),
              ),
              NotificationChannelTile(
                title: 'Rute avvist (bekreftelse)',
                value: s.chPartnerRouteRejected,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerRouteRejected: v)),
              ),
              NotificationChannelTile(
                title: 'MASS / masseutsendelse ruter',
                value: s.chPartnerMassRoute,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerMassRoute: v)),
              ),
              const Divider(height: 24),
              Text('Dokumenter & portal', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Nytt dokument delt',
                subtitle: 'Opplasting til partner-mappe',
                value: s.chPartnerDocument,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerDocument: v)),
              ),
              NotificationChannelTile(
                title: 'Ny dokumentmappe',
                value: s.chPartnerDocumentFolder,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerDocumentFolder: v)),
              ),
              NotificationChannelTile(
                title: 'Felles rutine/prosedyre (alle partnere)',
                value: s.chPartnerSharedRoutine,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerSharedRoutine: v)),
              ),
              NotificationChannelTile(
                title: 'Portal bruker / passord',
                value: s.chPartnerPortal,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerPortal: v)),
              ),
              NotificationChannelTile(
                title: 'Ukesoppsummering økonomi',
                value: s.chPartnerWeeklySummary,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerWeeklySummary: v)),
              ),
              const Divider(height: 24),
              Text('Møte, SMS-hub, bilutleie', style: DriftProTheme.headingSm),
              NotificationChannelTile(
                title: 'Møte / oppfølging',
                value: s.chPartnerMeeting,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerMeeting: v)),
              ),
              NotificationChannelTile(
                title: 'Manuell SMS fra hub',
                value: s.chPartnerCompose,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerCompose: v)),
              ),
              NotificationChannelTile(
                title: 'Bilutleie — ny forespørsel',
                value: s.chVehicleRental,
                onChanged: (v) => setState(() => _s = s.copyWith(chVehicleRental: v)),
              ),
              NotificationChannelTile(
                title: 'Bilutleie — status / purring retur',
                value: s.chVehicleRentalStatus,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chVehicleRentalStatus: v)),
              ),
              NotificationChannelTile(
                title: 'Bil deaktivert / endring',
                value: s.chPartnerVehicleInactive,
                onChanged: (v) =>
                    setState(() => _s = s.copyWith(chPartnerVehicleInactive: v)),
              ),
              NotificationChannelTile(
                title: 'Øvrig samarbeid',
                value: s.chPartnerGeneral,
                onChanged: (v) => setState(() => _s = s.copyWith(chPartnerGeneral: v)),
              ),
              const SizedBox(height: 72),
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
                backgroundColor: Colors.orange.shade800,
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('LAGRE SAMARBEID-VARSEL'),
            ),
          ),
        ),
      ],
    );
  }
}
