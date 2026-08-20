import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_paths.dart';
import '../../core/theme/app_theme.dart';

/// Vises når innlogget bruker åpner en lenke uten tilgang.
/// Innholdet bak lenken lastes ikke — kun dette skjermbildet.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, this.attemptedPath});

  final String? attemptedPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      size: 36,
                      color: DriftProTheme.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ingen tilgang',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Du er innlogget, men har ikke rettighet til denne funksjonen i DriftPro. '
                    'Be en administrator om tilgang hvis du trenger den.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: () => context.go(AppPaths.dashboard),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Gå til dashboard'),
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppPaths.dashboard);
                      }
                    },
                    child: const Text('Tilbake'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
