import 'package:flutter/material.dart';

import '../../../core/services/partner/partner_service.dart';
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
  final routeTitle = route.title ?? 'Ruten';
  final shouldContinue = accepted
      ? await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aksepter rute?',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  routeTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  onBehalfOfDriver
                      ? 'Du bekrefter på vegne av sjåfør. MAVI får beskjed med én gang.'
                      : 'Du bekrefter at du tar ruten. MAVI får beskjed med én gang.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Kommentar (valgfritt)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Ja — aksepter ruten'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Avbryt'),
                ),
              ],
            ),
          ),
        )
      : await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Avvis rute'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Avvisning i portalen er stengt. Ring kjørekontoret i stedet.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('OK'),
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
