import 'package:flutter/material.dart';

import '../widgets/partner_portal_page_shell.dart';
import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../more/driftpro_platform_catalog.dart';
import '../../more/widgets/info_page_scaffold.dart';
import '../../profile/delete_own_account_dialog.dart';
import '../widgets/partner_ui.dart';

class DriverPortalProfilePage extends StatelessWidget {
  final UserProfile profile;

  const DriverPortalProfilePage({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return PartnerPortalPageShell(
      title: 'Profil',
      actions: [
        IconButton(
          tooltip: 'Logg ut',
          icon: const Icon(Icons.logout),
          onPressed: () => signOutFromPortal(context),
        ),
      ],
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
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Vilkår for bruk'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => launchInfoUrl(DriftProPlatformCatalog.termsOfUseUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Personvernerklæring'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () =>
                      launchInfoUrl(DriftProPlatformCatalog.privacyPolicyUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DriftProTheme.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: DriftProTheme.error.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Slett konto',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: DriftProTheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'DriftPro er kun for ${DriftProPlatformCatalog.companyName}. '
                  'Du kan slette innloggingen og personopplysninger her.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: PartnerUi.mutedText(context),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => showDeleteOwnAccountDialog(context),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Slett konto permanent'),
                  style: FilledButton.styleFrom(
                    backgroundColor: DriftProTheme.error,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
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
