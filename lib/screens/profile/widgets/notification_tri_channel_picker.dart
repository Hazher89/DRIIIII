import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Tre uavhengige brytere: SMS, e-post og push i appen.
class NotificationTriChannelPicker extends StatelessWidget {
  const NotificationTriChannelPicker({
    super.key,
    required this.smsEnabled,
    required this.emailEnabled,
    required this.pushEnabled,
    required this.onSmsChanged,
    required this.onEmailChanged,
    required this.onPushChanged,
    this.enabled = true,
  });

  final bool smsEnabled;
  final bool emailEnabled;
  final bool pushEnabled;
  final ValueChanged<bool> onSmsChanged;
  final ValueChanged<bool> onEmailChanged;
  final ValueChanged<bool> onPushChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _channelSwitch(
          icon: Icons.sms_outlined,
          label: 'SMS',
          value: smsEnabled,
          onChanged: onSmsChanged,
        ),
        _channelSwitch(
          icon: Icons.email_outlined,
          label: 'E-post',
          value: emailEnabled,
          onChanged: onEmailChanged,
        ),
        _channelSwitch(
          icon: Icons.phone_iphone_outlined,
          label: 'Push i appen',
          value: pushEnabled,
          onChanged: onPushChanged,
        ),
      ],
    );
  }

  Widget _channelSwitch({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: Icon(icon, size: 20, color: DriftProTheme.primaryGreen),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}
