import 'package:flutter/material.dart';

import '../../../core/services/employee_auth_service.dart';
import '../../../core/theme/app_theme.dart';

/// Partner bytter eget portalpassord. Standard ved opprettelse er 000000.
Future<void> showPortalChangePasswordSheet(BuildContext context) async {
  if (!context.mounted) return;
  final newPw = TextEditingController();
  final confirmPw = TextEditingController();
  var obscure = true;
  var loading = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bytt passord',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Startpassordet er 000000. Velg et nytt passord med minst 6 tegn. '
                  'Det nye passordet lagres sikkert og fungerer neste gang du logger inn '
                  'med brukernavnet ditt.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPw,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Nytt passord',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setLocal(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPw,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Gjenta passord',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
                  onPressed: loading
                      ? null
                      : () async {
                          final a = newPw.text.trim();
                          final b = confirmPw.text.trim();
                          if (a.length < 6) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Passord må være minst 6 tegn')),
                            );
                            return;
                          }
                          if (a != b) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Passordene er ikke like')),
                            );
                            return;
                          }
                          setLocal(() => loading = true);
                          try {
                            await EmployeeAuthService.changePassword(newPassword: a);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Passordet er byttet')),
                              );
                            }
                          } catch (e) {
                            setLocal(() => loading = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Kunne ikke bytte passord: $e')),
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Lagre nytt passord'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  newPw.dispose();
  confirmPw.dispose();
}
