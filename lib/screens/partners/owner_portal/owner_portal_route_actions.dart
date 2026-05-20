import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_links.dart';

/// Bil-eier kan akseptere/avvise ruter på vegne av sjåfør (med kommentar).
Future<bool> ownerPortalSetRouteAck(
  BuildContext context,
  PartnerRouteShare route, {
  required bool accepted,
  required Future<void> Function() onDone,
  bool onBehalfOfDriver = true,
}) async {
  final noteCtrl = TextEditingController();
  final shouldContinue = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(accepted ? 'Godkjenn rute' : 'Avvis rute'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            onBehalfOfDriver
                ? (accepted
                    ? 'Du godkjenner på vegne av sjåfør. Kommentar er valgfri.'
                    : 'Du avviser på vegne av sjåfør. Begrunnelse er påkrevd.')
                : (accepted
                    ? 'Bekreft at du tar ruten. Kommentar er valgfri.'
                    : 'Du avviser ruten. Begrunnelse sendes til MAVI.'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: accepted ? 'Kommentar (valgfritt)' : 'Begrunnelse *',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
        FilledButton(
          onPressed: () {
            if (!accepted && noteCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Skriv en begrunnelse når du avviser ruten.')),
              );
              return;
            }
            Navigator.pop(ctx, true);
          },
          style: FilledButton.styleFrom(
            backgroundColor: accepted ? Colors.green : DriftProTheme.error,
          ),
          child: Text(accepted ? 'Godkjenn' : 'Avvis'),
        ),
      ],
    ),
  );
  if (shouldContinue != true) {
    noteCtrl.dispose();
    return false;
  }
  final comment = noteCtrl.text.trim();
  noteCtrl.dispose();
  if (!accepted && comment.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skriv en begrunnelse når du avviser ruten.')),
      );
    }
    return false;
  }
  try {
    await PartnerService.updateRouteAcknowledgement(
      routeShareId: route.id,
      accepted: accepted,
      comment: comment.isEmpty ? null : comment,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            onBehalfOfDriver
                ? (accepted
                    ? 'Ruten er godkjent. Sjåfør og MAVI er varslet.'
                    : 'Ruten er avvist med begrunnelse.')
                : (accepted
                    ? 'Ruten er akseptert. MAVI er varslet.'
                    : 'Ruten er avvist. Begrunnelsen er sendt til MAVI.'),
          ),
        ),
      );
    }
    await onDone();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lagre: $e'), backgroundColor: Colors.red),
      );
    }
    return false;
  }
}
