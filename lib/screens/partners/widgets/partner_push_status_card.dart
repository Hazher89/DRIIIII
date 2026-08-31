import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/services/native_permissions_service.dart';
import '../../../core/services/notification/push_notification_service.dart';
import '../../../core/theme/app_theme.dart';

/// Viser varsel-status fra enheten og lenker til iOS/Android-innstillinger (Apple HIG).
class PartnerPushStatusCard extends StatefulWidget {
  const PartnerPushStatusCard({super.key});

  @override
  State<PartnerPushStatusCard> createState() => _PartnerPushStatusCardState();
}

class _PartnerPushStatusCardState extends State<PartnerPushStatusCard>
    with WidgetsBindingObserver {
  NotificationAuthState _state = NotificationAuthState.notConfigured;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!DriftProClient.isMobile) return;
    final state = await NativePermissionsService.readNotificationState();
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
    if (state == NotificationAuthState.enabled) {
      unawaited(PushNotificationService.syncRegistration());
    }
  }

  Future<void> _openSettings() async {
    await NativePermissionsService.openNotificationSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!DriftProClient.isMobile) return const SizedBox.shrink();

    final enabled = _state == NotificationAuthState.enabled;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              enabled ? Icons.notifications_outlined : Icons.notifications_off_outlined,
              color: enabled ? DriftProTheme.primaryGreen : Colors.orange.shade800,
            ),
            title: const Text('Push-varsler'),
            subtitle: _loading
                ? const Text('Sjekker enhet…', style: TextStyle(fontSize: 12))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        _state.subtitle,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
            trailing: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (enabled ? DriftProTheme.primaryGreen : Colors.orange.shade800)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _state.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: enabled ? DriftProTheme.primaryGreen : Colors.orange.shade900,
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              Platform.isIOS
                  ? 'Slå varsler av og på under Innstillinger → DriftPro → Varsler.'
                  : 'Slå varsler av og på under Innstillinger → Apper → DriftPro → Varsler.',
              style: TextStyle(fontSize: 12, color: muted, height: 1.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
              label: const Text('Åpne enhetsinnstillinger'),
            ),
          ),
        ],
      ),
    );
  }
}
