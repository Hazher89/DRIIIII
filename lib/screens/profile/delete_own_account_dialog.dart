import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';
import '../more/driftpro_platform_catalog.dart';

const _nbMonths = <String>[
  'januar',
  'februar',
  'mars',
  'april',
  'mai',
  'juni',
  'juli',
  'august',
  'september',
  'oktober',
  'november',
  'desember',
];

/// Frist = lokal kalenderdato i dag + 15 dager (alltid, uansett år).
DateTime accountDeletionDueDate([DateTime? from]) {
  final now = from ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.add(const Duration(days: 15));
}

/// Norsk dato uten intl-locale (fungerer alltid).
String formatNbDate(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return '${d.day}. ${_nbMonths[d.month - 1]} ${d.year}';
}

DateTime? _parseDueBy(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) {
    return DateTime(raw.year, raw.month, raw.day);
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  // Postgres DATE: YYYY-MM-DD
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// App Store 5.1.1(v): bruker kan starte sletting i appen.
/// Faktisk sletting utføres av superadmin (innen 15 dager).
Future<void> showDeleteOwnAccountDialog(BuildContext context) async {
  final dueLabel = await showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _DeleteAccountRequestDialog(),
  );

  if (dueLabel == null || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Søknad sendt'),
      content: Text(
        'Søknaden din er sendt til superadmin.\n\n'
        'Kontoen blir slettet innen 15 dager (senest $dueLabel). '
        'Du kan bruke appen som vanlig til slettingen er gjennomført.\n\n'
        'Lovpålagte HMS-/HR-data kan beholdes uten din identitet der det er nødvendig.',
        style: const TextStyle(height: 1.4),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _DeleteAccountRequestDialog extends StatefulWidget {
  const _DeleteAccountRequestDialog();

  @override
  State<_DeleteAccountRequestDialog> createState() =>
      _DeleteAccountRequestDialogState();
}

class _DeleteAccountRequestDialogState
    extends State<_DeleteAccountRequestDialog> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final row = await SupabaseService.requestAccountDeletion();
      if (!mounted) return;
      final due = _parseDueBy(row['due_by']) ?? accountDeletionDueDate();
      Navigator.pop(context, formatNbDate(due));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = DriftProPlatformCatalog.companyName;
    final dueHint = formatNbDate(accountDeletionDueDate());

    return AlertDialog(
      title: const Text('Slett konto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DriftPro er arbeidsappen til $company.\n\n'
              'Du kan ikke slette kontoen selv med én gang. '
              'Når du sender søknad:\n\n'
              '• Superadmin får beskjed om at du vil slette deg\n'
              '• Kontoen slettes av superadmin innen 15 dager '
              '(senest $dueHint)\n'
              '• Lovpålagte HMS-/HR-data kan bli igjen uten din identitet '
              'der bedriften er pålagt å oppbevare dem\n\n'
              'Vil du sende søknad nå?',
              style: const TextStyle(height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, height: 1.3),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: DriftProLoadingIndicator(size: 22),
                )
              : const Text('Send søknad'),
        ),
      ],
    );
  }
}
