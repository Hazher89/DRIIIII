import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';

/// Vises når portal-konto er deaktivert (f.eks. MAVI-nummer fjernet) men bruker fortsatt er innlogget.
class PartnerPortalAccessRevoked extends StatelessWidget {
  const PartnerPortalAccessRevoked({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 56, color: Colors.orange),
              const SizedBox(height: 20),
              const Text(
                'Portal-tilgang er opphevet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Bilen eller portal-kontoen er fjernet fra samarbeidspartneren. '
                'Logg ut og kontakt MAVI hvis du trenger ny tilgang.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => signOutFromPortal(context),
                child: const Text('Logg ut'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
