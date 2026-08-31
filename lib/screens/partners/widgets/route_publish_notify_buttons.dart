import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';
import '../../../models/partner/route_notify_prefs.dart';

/// Knapper for å publisere rute med valgt varselkanal — tydelige valgkort.
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

  static const _options = [
    _NotifyOption(
      prefs: RouteNotifyPrefs.smsOnly,
      icon: Icons.sms_outlined,
      title: 'SMS',
      subtitle: 'Tekstmelding til sjåfør/eier',
      color: DriftProTheme.primaryGreen,
    ),
    _NotifyOption(
      prefs: RouteNotifyPrefs.smsAndEmail,
      icon: Icons.mark_email_read_outlined,
      title: 'SMS + e-post',
      subtitle: 'Melding og e-post med PDF-lenke',
      color: DriftProTheme.accentBlue,
    ),
    _NotifyOption(
      prefs: RouteNotifyPrefs.pushOnly,
      icon: Icons.notifications_active_outlined,
      title: 'Push i appen',
      subtitle: 'Varsel direkte på mobilen',
      color: Color(0xFF6A1B9A),
    ),
    _NotifyOption(
      prefs: RouteNotifyPrefs.smsAndPush,
      icon: Icons.send_outlined,
      title: 'SMS + push',
      subtitle: 'Både tekst og app-varsel',
      color: DriftProTheme.primaryGreenDark,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hvordan vil du varsle?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 13 : 14,
            color: drift.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Velg kanal — du kan alltid sende purring senere.',
          style: TextStyle(fontSize: 11, color: drift.textMuted),
        ),
        SizedBox(height: compact ? 10 : 12),
        if (showWithoutNotify) ...[
          _NotifyTile(
            enabled: !busy,
            icon: Icons.visibility_off_outlined,
            title: 'Lagre uten varsel',
            subtitle: 'Kun i kalender — send senere',
            color: Colors.blueGrey,
            onTap: () => onPublish(null),
            compact: compact,
          ),
          SizedBox(height: compact ? 8 : 10),
        ],
        ..._options.map(
          (o) => Padding(
            padding: EdgeInsets.only(bottom: compact ? 8 : 10),
            child: _NotifyTile(
              enabled: !busy,
              icon: o.icon,
              title: o.title,
              subtitle: o.subtitle,
              color: o.color,
              onTap: () => onPublish(o.prefs),
              compact: compact,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotifyOption {
  const _NotifyOption({
    required this.prefs,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final RouteNotifyPrefs prefs;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _NotifyTile extends StatelessWidget {
  const _NotifyTile({
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.compact,
  });

  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: drift.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.07),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: compact ? 18 : 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 13 : 14,
                          color: drift.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: drift.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
