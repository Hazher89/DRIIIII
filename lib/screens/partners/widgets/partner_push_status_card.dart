import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/config/driftpro_client.dart';
import '../../../core/services/native_permissions_service.dart';
import '../../../core/services/notification/push_notification_service.dart';
import '../../../core/theme/app_theme.dart';
import 'partner_ui.dart';

/// Push-status som vanlig profil-rad (samme stil som Konto / Hjelp).
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = PartnerUi.mutedText(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'VARSLER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: muted,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(
              enabled
                  ? Icons.notifications_outlined
                  : Icons.notifications_off_outlined,
              color: enabled
                  ? DriftProTheme.primaryGreen
                  : Colors.orange.shade800,
            ),
            title: const Text('Push-varsler'),
            subtitle: Text(
              _loading ? 'Sjekker enhet…' : _state.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _loading
                    ? muted
                    : (enabled
                        ? DriftProTheme.primaryGreen
                        : Colors.orange.shade900),
              ),
            ),
            trailing: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, size: 20),
            onTap: _loading ? null : _openSettings,
          ),
        ),
      ],
    );
  }
}
