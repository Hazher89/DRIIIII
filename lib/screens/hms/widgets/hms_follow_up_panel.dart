import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/hms/hms_follow_up_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hms/hms_follow_up.dart';

/// Viser åpne HMS-oppfølginger og lar involverte lukke (stopper purring).
class HmsFollowUpPanel extends StatelessWidget {
  final List<HmsFollowUp> items;
  final bool canClose;
  final VoidCallback? onChanged;

  const HmsFollowUpPanel({
    super.key,
    required this.items,
    this.canClose = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final open = items.where((e) => e.isOpen).toList();
    if (open.isEmpty) return const SizedBox.shrink();
    final df = DateFormat('dd.MM.yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Åpen oppfølging', style: DriftProTheme.labelLg),
        const SizedBox(height: 8),
        ...open.map((f) {
          final overdue = f.followUpDueAt != null &&
              f.followUpDueAt!.isBefore(
                DateTime.now().subtract(const Duration(days: 1)),
              );
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (f.deviationCount > 1)
                        '${f.deviationCount} punkter',
                      if (f.followUpDueAt != null)
                        'Frist ${df.format(f.followUpDueAt!)}',
                      '${f.recipientIds.length} mottakere',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: overdue ? Colors.red.shade700 : Colors.grey.shade700,
                    ),
                  ),
                  if ((f.summary ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(f.summary!.trim(), style: const TextStyle(fontSize: 13)),
                  ],
                  if (canClose) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () => _close(context, f),
                        child: const Text('Lukk oppfølging'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _close(BuildContext context, HmsFollowUp f) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lukk oppfølging'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Hva er gjort? (valgfritt)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lukk'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await HmsFollowUpService.close(
        followUpId: f.id,
        notes: notes.text.trim(),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Oppfølging lukket — ingen flere påminnelser.'),
        ),
      );
      onChanged?.call();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunne ikke lukke: $e')),
      );
    }
  }
}
