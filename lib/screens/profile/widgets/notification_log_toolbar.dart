import 'package:flutter/material.dart';

import '../../../core/services/notification/notification_log_admin_service.dart';
import '../../../core/services/notification/notification_outbox_service.dart';
import '../../../core/theme/app_theme.dart';

/// Felles verktøylinje for varsel-logg: tøm logg + send kø.
class NotificationLogToolbar extends StatelessWidget {
  final int totalCount;
  final VoidCallback onRefresh;
  final bool partnerScopeOnly;
  final bool showQueueHelp;
  final String? queueFilterActive;

  const NotificationLogToolbar({
    super.key,
    required this.totalCount,
    required this.onRefresh,
    this.partnerScopeOnly = false,
    this.showQueueHelp = true,
    this.queueFilterActive,
  });

  Future<void> _confirmClear(BuildContext context, {required bool queuedOnly}) async {
    final label = queuedOnly ? 'tømme sendingskøen' : 'slette all valgt logg';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(queuedOnly ? 'Tøm kø?' : 'Tøm logg?'),
        content: Text(
          queuedOnly
              ? 'Fjerner SMS/e-post som venter på sending (status «I kø»). '
                  'Sendte meldinger beholdes.'
              : 'Dette sletter loggoppføringer permanent for '
                  '${partnerScopeOnly ? 'samarbeid' : 'hele bedriften'}. '
                  'Kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: queuedOnly ? DriftProTheme.warning : Colors.red.shade700,
            ),
            child: Text(queuedOnly ? 'Tøm kø' : 'Slett logg'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final result = await NotificationLogAdminService.clearLogs(
        sms: true,
        email: true,
        audit: !queuedOnly,
        queuedOnly: queuedOnly,
        partnerScopeOnly: partnerScopeOnly,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queuedOnly
                ? 'Kø tømt (${result.total} rader fjernet)'
                : 'Logg tømt (${result.total} rader fjernet)',
          ),
        ),
      );
      onRefresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke $label: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _flushQueue(BuildContext context) async {
    try {
      final res = await NotificationOutboxService.flushAll();
      if (!context.mounted) return;
      final sms = res['sms'];
      final email = res['email'];
      final smsSent = sms is Map ? sms['sent'] : null;
      final emailSent = email is Map ? email['sent'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kø kjørt — SMS: ${smsSent ?? '?'} sendt, '
            'e-post: ${emailSent ?? '?'} sendt',
          ),
        ),
      );
      onRefresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke sende kø: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('$totalCount i utvalg', style: DriftProTheme.labelMd),
            ),
            IconButton(
              tooltip: 'Send kø nå (SMS + e-post)',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => _flushQueue(context),
            ),
            PopupMenuButton<String>(
              tooltip: 'Logg-handlinger',
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                switch (v) {
                  case 'clear_queue':
                    _confirmClear(context, queuedOnly: true);
                  case 'clear_all':
                    _confirmClear(context, queuedOnly: false);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clear_queue',
                  child: ListTile(
                    leading: Icon(Icons.hourglass_empty),
                    title: Text('Tøm kø'),
                    subtitle: Text('Fjern «I kø» uten å slette sendte'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear_all',
                  child: ListTile(
                    leading: Icon(Icons.delete_sweep_outlined, color: Colors.red),
                    title: Text('Tøm all logg'),
                    subtitle: Text('Slett valgt logg permanent'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
          ],
        ),
        if (showQueueHelp &&
            (queueFilterActive == 'i_ko' || queueFilterActive == null)) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DriftProTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DriftProTheme.warning.withValues(alpha: 0.35)),
            ),
            child: Text(
              queueFilterActive == 'i_ko'
                  ? '«I kø» betyr at utsending ikke er ferdig ennå (sjelden). '
                      'Varsler sendes automatisk ved opprettelse. '
                      'Bruk ▶ kun ved feilsøking.'
                  : 'Varsler sendes automatisk (e-post via Resend, SMS via Sveve). '
                      '«I kø» = venter eller retry — oppdater loggen etter noen sekunder.',
              style: DriftProTheme.caption,
            ),
          ),
        ],
      ],
    );
  }
}
