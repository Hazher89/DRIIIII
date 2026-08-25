import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../more/driftpro_platform_catalog.dart';
import '../../more/widgets/info_page_scaffold.dart';
import '../../profile/delete_own_account_dialog.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_ui.dart';

/// Apple App Store-klar profil for bil-eier, sjåfør og ansatt.
/// Samler vilkår, personvern, support og slett konto — ikke på hovedsiden.
class PartnerPortalProfilePage extends StatelessWidget {
  const PartnerPortalProfilePage({
    super.key,
    required this.profile,
    required this.roleLabel,
    this.partnerName,
    this.staffPortal = false,
  });

  final UserProfile profile;
  final String roleLabel;
  final String? partnerName;
  final bool staffPortal;

  Future<void> _mailSupport() async {
    final uri = Uri.parse(
      'mailto:${DriftProPlatformCatalog.supportEmail}'
      '?subject=${Uri.encodeComponent('DriftPro portal — support')}',
    );
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final muted = PartnerUi.mutedText(context);

    return PartnerPortalPageShell(
      title: staffPortal ? null : 'Profil',
      showMobileBackButton: !staffPortal,
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, staffPortal ? 12 : 4, 20, 40),
          children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
              child: Text(
                profile.initials,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: DriftProTheme.primaryGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              profile.fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          if (partnerName != null && partnerName!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(
                partnerName!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: muted, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Center(
            child: Text(
              profile.email,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
          const SizedBox(height: 20),
          _sectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: DriftProTheme.primaryGreen),
                title: const Text('Rolle'),
                subtitle: Text(roleLabel),
              ),
              if (profile.phone != null && profile.phone!.trim().isNotEmpty) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.phone_outlined, color: DriftProTheme.primaryGreen),
                  title: const Text('Telefon'),
                  subtitle: Text(profile.phone!),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Hjelp & juridisk',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: muted,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          _sectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.support_agent_outlined),
                title: const Text('Kundesupport'),
                subtitle: Text(DriftProPlatformCatalog.supportEmail),
                trailing: const Icon(Icons.chevron_right),
                onTap: _mailSupport,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Hjelpesider'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchInfoUrl(DriftProPlatformCatalog.supportUrl),
              ),
              const Divider(height: 1),
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
          const SizedBox(height: 12),
          _sectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Om DriftPro'),
                subtitle: Text(
                  '${DriftProPlatformCatalog.versionLabel}\n'
                  'Kun for ${DriftProPlatformCatalog.companyName}',
                ),
                isThreeLine: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => signOutFromPortal(context),
            icon: const Icon(Icons.logout),
            label: const Text('Logg ut'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DriftProTheme.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
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
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'DriftPro er kun for ${DriftProPlatformCatalog.companyName}. '
                  'Du kan slette innloggingen og personopplysninger her '
                  '(App Store-krav).',
                  style: TextStyle(fontSize: 13, height: 1.4, color: muted),
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
          const SizedBox(height: 16),
          Text(
            'Du forblir innlogget på denne enheten til du trykker «Logg ut».',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
        ],
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(children: children),
    );
  }
}
