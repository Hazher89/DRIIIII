import 'package:flutter/material.dart';

import '../../core/services/employee_auth_service.dart';
import '../../core/theme/app_theme.dart';

/// Bytt passord for MAVI-ansatt — nytt passord sendes på SMS.
Future<void> showEmployeeChangePasswordSheet(BuildContext context) async {
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
              20 + MediaQuery.of(ctx).viewInsets.bottom,
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
                  'Nytt passord lagres i Supabase og sendes på SMS til mobilnummeret på profilen din. '
                  'Minst 6 tegn.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
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
                            final result = await EmployeeAuthService.changePasswordAndNotifySms(
                              newPassword: a,
                            );
                            await EmployeeAuthService.flushSmsOutbox();
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result['message']?.toString() ??
                                        'Passord oppdatert.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('$e'),
                                  backgroundColor: DriftProTheme.error,
                                ),
                              );
                            }
                          } finally {
                            if (ctx.mounted) setLocal(() => loading = false);
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Lagre og send SMS', style: TextStyle(fontWeight: FontWeight.w800)),
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
