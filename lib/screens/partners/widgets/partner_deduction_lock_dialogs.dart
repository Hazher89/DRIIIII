import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Bekreftelsesdialoger for opplåsing og soft-slett av fakturerte saker.
abstract final class PartnerDeductionLockDialogs {
  static Future<bool> confirmUnlock(
    BuildContext context, {
    required String caseNumber,
  }) async {
    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_open_rounded, color: Colors.orange),
        title: const Text('Lås opp fakturert sak?'),
        content: Text(
          'Sak $caseNumber er låst etter fakturering. '
          'Opplåsing gjør at saken kan endres eller slettes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fortsett')),
        ],
      ),
    );
    if (step1 != true || !context.mounted) return false;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: DriftProTheme.error),
        title: const Text('Er du helt sikker?'),
        content: Text(
          'Du er i ferd med å låse opp $caseNumber. '
          'Dette skal kun gjøres ved feilregistrering. Handlingen logges.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nei, avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ja, lås opp'),
          ),
        ],
      ),
    );
    return step2 == true;
  }

  static Future<String?> confirmDelete(
    BuildContext context, {
    required String caseNumber,
  }) async {
    final commentCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.archive_outlined, color: DriftProTheme.error),
        title: const Text('Slett til arkiv'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sak $caseNumber flyttes til slettet-arkiv. Sporings-ID beholdes permanent. '
                'Du må oppgi begrunnelse.',
                style: TextStyle(fontSize: 13, height: 1.4, color: Theme.of(ctx).hintColor),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: commentCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Kommentar (påkrevd)',
                  hintText: 'Hvorfor slettes saken?',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  if ((v ?? '').trim().length < 8) {
                    return 'Skriv minst 8 tegn';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Slett til arkiv'),
          ),
        ],
      ),
    );

    if (ok != true) return null;
    return commentCtrl.text.trim();
  }
}
