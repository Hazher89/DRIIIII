import 'package:flutter/material.dart';

import '../../../core/services/notification/push_notification_service.dart';
import '../../../core/services/native_permissions_service.dart';
import '../../../core/theme/app_theme.dart';

/// Viser om push er registrert og lar brukeren aktivere på nytt.
class PartnerPushStatusCard extends StatefulWidget {
  const PartnerPushStatusCard({super.key});

  @override
  State<PartnerPushStatusCard> createState() => _PartnerPushStatusCardState();
}

class _PartnerPushStatusCardState extends State<PartnerPushStatusCard> {
  bool _busy = false;
  bool _registered = PushNotificationService.lastRegistrationOk;

  Future<void> _refresh({bool request = false}) async {
    setState(() => _busy = true);
    final ok = request
        ? await NativePermissionsService.ensureNotifications(context: context)
        : await PushNotificationService.syncRegistration();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _registered = ok || PushNotificationService.lastRegistrationOk;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _registered;
    return Card(
      child: ListTile(
        leading: Icon(
          active ? Icons.notifications_active : Icons.notifications_off_outlined,
          color: active ? DriftProTheme.primaryGreen : Colors.orange.shade800,
        ),
        title: Text(active ? 'Push-varsler er aktive' : 'Push-varsler er ikke aktive'),
        subtitle: Text(
          active
              ? 'Denne enheten mottar varsler i appen.'
              : 'Trykk for å aktivere varsler — kreves for bot, ruter og bilkontroll.',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                tooltip: 'Oppdater push-registrering',
                icon: const Icon(Icons.refresh),
                onPressed: () => _refresh(request: !active),
              ),
        onTap: _busy ? null : () => _refresh(request: !active),
      ),
    );
  }
}
