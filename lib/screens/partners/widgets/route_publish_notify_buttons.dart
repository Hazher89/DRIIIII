import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/route_notify_prefs.dart';

/// Knapper for å publisere rute med valgt varselkanal.
class RoutePublishNotifyButtons extends StatelessWidget {
  const RoutePublishNotifyButtons({
    super.key,
    required this.busy,
    required this.onPublish,
    this.showWithoutNotify = true,
    this.compact = false,
  });

  final bool busy;
  final Future<void> Function(RouteNotifyPrefs? prefs) onPublish;
  final bool showWithoutNotify;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pad = compact
        ? const EdgeInsets.symmetric(vertical: 10)
        : const EdgeInsets.symmetric(vertical: 12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWithoutNotify) ...[
          OutlinedButton(
            onPressed: busy ? null : () => onPublish(null),
            child: const Text('Publiser uten varsel'),
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        FilledButton.icon(
          onPressed: busy ? null : () => onPublish(RouteNotifyPrefs.smsOnly),
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen, padding: pad),
          icon: const Icon(Icons.sms_outlined),
          label: const Text('Varsle med SMS'),
        ),
        SizedBox(height: compact ? 6 : 8),
        FilledButton.icon(
          onPressed: busy ? null : () => onPublish(RouteNotifyPrefs.pushOnly),
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen, padding: pad),
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Varsle med push (app)'),
        ),
        SizedBox(height: compact ? 6 : 8),
        FilledButton.icon(
          onPressed: busy ? null : () => onPublish(RouteNotifyPrefs.smsAndPush),
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen, padding: pad),
          icon: const Icon(Icons.send_outlined),
          label: const Text('Varsle med SMS + push'),
        ),
      ],
    );
  }
}
