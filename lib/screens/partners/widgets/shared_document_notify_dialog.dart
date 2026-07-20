import 'package:flutter/material.dart';

import '../../../core/layout/mobile_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';

enum SharedDocumentNotifyChannel { none, sms, email, both }

class SharedDocumentNotifyPlan {
  final SharedDocumentNotifyChannel channel;
  final Set<String> partnerIds;

  const SharedDocumentNotifyPlan({
    required this.channel,
    required this.partnerIds,
  });

  bool get willNotify =>
      channel != SharedDocumentNotifyChannel.none && partnerIds.isNotEmpty;
}

/// Velg varselkanal og hvilke samarbeidspartnere som skal varsles.
Future<SharedDocumentNotifyPlan?> showSharedDocumentNotifyDialog(
  BuildContext context, {
  required List<Partner> partners,
  required int fileCount,
}) async {
  if (partners.isEmpty) {
    return const SharedDocumentNotifyPlan(
      channel: SharedDocumentNotifyChannel.none,
      partnerIds: {},
    );
  }

  var channel = SharedDocumentNotifyChannel.both;
  final selected = partners.map((p) => p.id).toSet();

  return showDialog<SharedDocumentNotifyPlan>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        String channelLabel(SharedDocumentNotifyChannel c) {
          switch (c) {
            case SharedDocumentNotifyChannel.none:
              return 'Ingen';
            case SharedDocumentNotifyChannel.sms:
              return 'SMS';
            case SharedDocumentNotifyChannel.email:
              return 'E-post';
            case SharedDocumentNotifyChannel.both:
              return 'Begge';
          }
        }

        final needsRecipients = channel != SharedDocumentNotifyChannel.none;

        return AlertDialog(
          title: Text(fileCount == 1 ? 'Varsel om nytt dokument' : 'Varsel om $fileCount dokumenter'),
          content: MobileDialogBody(
            maxWidth: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Fellesmappe deles med alle samarbeidspartnere. '
                    'Velg kanal og hvilke bedrifter som skal varsles — kun valgte får beskjed.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  Text('Varselkanal', style: DriftProTheme.labelMd),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SharedDocumentNotifyChannel.values.map((c) {
                      final selected = channel == c;
                      return ChoiceChip(
                        label: Text(channelLabel(c)),
                        selected: selected,
                        onSelected: (_) => setSt(() => channel = c),
                      );
                    }).toList(),
                  ),
                  if (needsRecipients) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Varsle bedrifter', style: DriftProTheme.labelMd),
                        const Spacer(),
                        TextButton(
                          onPressed: selected.length == partners.length
                              ? null
                              : () => setSt(() => selected.addAll(partners.map((p) => p.id))),
                          child: const Text('Velg alle'),
                        ),
                        TextButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => setSt(() => selected.clear()),
                          child: const Text('Fjern alle'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...partners.map((p) {
                      final on = selected.contains(p.id);
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (p.tradeName != null && p.tradeName!.trim().isNotEmpty) p.tradeName,
                            if (p.orgNumber != null && p.orgNumber!.trim().isNotEmpty)
                              'Org.nr ${p.orgNumber}',
                          ].whereType<String>().join(' · '),
                        ),
                        value: on,
                        onChanged: (v) {
                          setSt(() {
                            if (v == true) {
                              selected.add(p.id);
                            } else {
                              selected.remove(p.id);
                            }
                          });
                        },
                      );
                    }),
                    if (selected.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Velg minst én bedrift for å sende varsel.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${selected.length} av ${partners.length} bedrift(er) valgt.',
                          style: DriftProTheme.caption.copyWith(
                            color: DriftProTheme.primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: needsRecipients && selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                        ctx,
                        SharedDocumentNotifyPlan(
                          channel: channel,
                          partnerIds: Set<String>.from(selected),
                        ),
                      ),
              child: Text(needsRecipients ? 'Last opp og varsle' : 'Last opp uten varsel'),
            ),
          ],
        );
      },
    ),
  );
}

String sharedDocumentNotifyChannelDb(SharedDocumentNotifyChannel channel) {
  switch (channel) {
    case SharedDocumentNotifyChannel.none:
      return 'none';
    case SharedDocumentNotifyChannel.sms:
      return 'sms';
    case SharedDocumentNotifyChannel.email:
      return 'email';
    case SharedDocumentNotifyChannel.both:
      return 'both';
  }
}
