import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_sign_out.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// App Store: slett egen konto (krever bekreftelse SLETT).
Future<void> showDeleteOwnAccountDialog(BuildContext context) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Slett konto permanent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dette sletter innloggingen din og personopplysninger i DriftPro. '
              'HMS-/HR-data som bedriften er lovpålagt å oppbevare kan beholdes '
              'uten din identitet der det er nødvendig.\n\n'
              'Skriv SLETT for å bekrefte:',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Bekreftelse',
                border: OutlineInputBorder(),
                hintText: 'SLETT',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DriftProTheme.error),
            onPressed: () {
              if (controller.text.trim().toUpperCase() == 'SLETT') {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Slett konto'),
          ),
        ],
      );
    },
  );

  if (ok != true || !context.mounted) {
    controller.dispose();
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: DriftProLoadingIndicator()),
  );

  try {
    await SupabaseService.deleteOwnAccount();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // loading
      await signOutFromPortal(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kontoen er slettet.')),
        );
        context.go(AppPaths.login);
      }
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunne ikke slette konto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    controller.dispose();
  }
}
