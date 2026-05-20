import 'package:flutter/material.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../widgets/partner_ui.dart';

class DriverPortalProfilePage extends StatelessWidget {
  final UserProfile profile;

  const DriverPortalProfilePage({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Logg ut',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutFromPortal(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.2),
              child: Text(profile.initials, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(profile.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          Center(child: Text(profile.email, style: TextStyle(color: PartnerUi.mutedText(context)))),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, color: DriftProTheme.primaryGreen),
              title: const Text('Rolle'),
              subtitle: const Text('Sjåfør (MAVI-bil)'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Du forblir innlogget på denne enheten til du trykker «Logg ut» nedenfor.',
            style: TextStyle(fontSize: 13, color: PartnerUi.mutedText(context), height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => signOutFromPortal(context),
            icon: const Icon(Icons.logout),
            label: const Text('Logg ut'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
