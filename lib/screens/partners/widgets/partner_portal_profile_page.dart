import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_sign_out.dart';
import '../../../core/config/driftpro_client.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../more/driftpro_platform_catalog.dart';
import '../../more/widgets/info_page_scaffold.dart';
import '../../profile/delete_own_account_dialog.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import '../widgets/partner_portal_page_shell.dart';
import '../widgets/partner_push_status_card.dart';
import '../widgets/partner_ui.dart';

/// Apple App Store-klar profil for bil-eier, sjåfør og ansatt.
class PartnerPortalProfilePage extends StatefulWidget {
  const PartnerPortalProfilePage({
    super.key,
    required this.profile,
    required this.roleLabel,
    this.partnerName,
    this.staffPortal = false,
    this.onProfileUpdated,
  });

  final UserProfile profile;
  final String roleLabel;
  final String? partnerName;
  final bool staffPortal;
  final ValueChanged<UserProfile>? onProfileUpdated;

  @override
  State<PartnerPortalProfilePage> createState() => _PartnerPortalProfilePageState();
}

class _PartnerPortalProfilePageState extends State<PartnerPortalProfilePage> {
  late UserProfile _profile;
  final _picker = ImagePicker();
  bool _saving = false;

  bool get _canEdit => !_profile.isRecoverySession;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  @override
  void didUpdateWidget(PartnerPortalProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.fullName != widget.profile.fullName ||
        oldWidget.profile.avatarUrl != widget.profile.avatarUrl) {
      _profile = widget.profile;
    }
  }

  void _notifyProfile(UserProfile updated) {
    setState(() => _profile = updated);
    widget.onProfileUpdated?.call(updated);
  }

  Future<void> _refresh() async {
    final fresh = await SupabaseService.fetchCurrentUserProfile();
    if (!mounted || fresh == null) return;
    _notifyProfile(fresh);
  }

  Future<void> _editName() async {
    if (!_canEdit || _saving) return;
    final controller = TextEditingController(text: _profile.fullName);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Endre navn', style: DriftProTheme.headingMd),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Visningsnavn',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Lagre'),
              ),
            ],
          ),
        );
      },
    );
    if (saved != true || !mounted) {
      controller.dispose();
      return;
    }
    final name = controller.text.trim();
    controller.dispose();
    if (name == _profile.fullName) return;

    setState(() => _saving = true);
    try {
      await SupabaseService.updateOwnProfile(fullName: name);
      _notifyProfile(_profile.copyWith(fullName: name));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navn oppdatert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre navn: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (!_canEdit || _saving) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Velg fra bibliotek'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (DriftProClient.isMobile)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Ta bilde'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final safeExt = {'jpg', 'jpeg', 'png', 'webp'}.contains(ext) ? ext : 'jpg';
      final contentType = switch (safeExt) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final url = await SupabaseService.uploadUserAvatar(
        Uint8List.fromList(bytes),
        extension: safeExt == 'jpeg' ? 'jpg' : safeExt,
        contentType: contentType,
      );
      await SupabaseService.updateOwnProfile(avatarUrl: url);
      _notifyProfile(_profile.copyWith(avatarUrl: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profilbilde oppdatert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke laste opp bilde: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PartnerPortalPageShell(
      title: widget.staffPortal ? null : 'Profil',
      showMobileBackButton: !widget.staffPortal,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, widget.staffPortal ? 8 : 0, 20, 32),
              children: [
                _ProfileHero(
                  profile: _profile,
                  partnerName: widget.partnerName,
                  roleLabel: widget.roleLabel,
                  canEdit: _canEdit,
                  onEditAvatar: _pickAvatar,
                  onEditName: _editName,
                ),
                const SizedBox(height: 16),
                _sectionLabel('Konto'),
                _sectionCard(
                  children: [
                    _infoTile(
                      icon: Icons.badge_outlined,
                      title: 'Rolle',
                      value: widget.roleLabel,
                    ),
                    if (_profile.phone != null && _profile.phone!.trim().isNotEmpty) ...[
                      const Divider(height: 1, indent: 56),
                      _infoTile(
                        icon: Icons.phone_outlined,
                        title: 'Telefon',
                        value: _profile.phone!,
                      ),
                    ],
                    if (_canEdit) ...[
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.drive_file_rename_outline, color: DriftProTheme.primaryGreen),
                        title: const Text('Visningsnavn'),
                        subtitle: Text(_profile.fullName),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: _editName,
                      ),
                    ],
                  ],
                ),
                if (DriftProClient.isMobile) ...[
                  const SizedBox(height: 14),
                  const PartnerPushStatusCard(),
                ],
                const SizedBox(height: 18),
                _sectionLabel('Hjelp & juridisk'),
                _sectionCard(
                  children: [
                    _linkTile(
                      icon: Icons.support_agent_outlined,
                      title: 'Kundesupport',
                      subtitle: DriftProPlatformCatalog.supportEmail,
                      onTap: _mailSupport,
                      chevron: true,
                    ),
                    const Divider(height: 1, indent: 56),
                    _linkTile(
                      icon: Icons.help_outline,
                      title: 'Hjelpesider',
                      onTap: () => launchInfoUrl(DriftProPlatformCatalog.supportUrl),
                      external: true,
                    ),
                    const Divider(height: 1, indent: 56),
                    _linkTile(
                      icon: Icons.description_outlined,
                      title: 'Vilkår for bruk',
                      onTap: () => launchInfoUrl(DriftProPlatformCatalog.termsOfUseUrl),
                      external: true,
                    ),
                    const Divider(height: 1, indent: 56),
                    _linkTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Personvernerklæring',
                      onTap: () => launchInfoUrl(DriftProPlatformCatalog.privacyPolicyUrl),
                      external: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.info_outline, color: DriftProTheme.primaryGreen.withValues(alpha: 0.9)),
                      title: const Text('Om DriftPro'),
                      subtitle: Text(
                        '${DriftProPlatformCatalog.versionLabel}\n'
                        'Kun for ${DriftProPlatformCatalog.companyName}',
                      ),
                      isThreeLine: true,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _sectionLabel('Sesjon'),
                _sectionCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.logout, color: isDark ? Colors.white70 : Colors.grey.shade800),
                      title: const Text('Logg ut'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => signOutFromPortal(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.delete_outline, color: DriftProTheme.error),
                      title: const Text(
                        'Slett konto',
                        style: TextStyle(color: DriftProTheme.error, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Fjern innlogging og personopplysninger',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20, color: DriftProTheme.error),
                      onTap: () => showDeleteOwnAccountDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(child: DriftProLoadingIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: PartnerUi.mutedText(context),
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, color: DriftProTheme.primaryGreen),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool chevron = false,
    bool external = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: DriftProTheme.primaryGreen),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Icon(
        external ? Icons.open_in_new : Icons.chevron_right,
        size: external ? 18 : 20,
        color: external ? Colors.grey : null,
      ),
      onTap: onTap,
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.roleLabel,
    this.partnerName,
    required this.canEdit,
    required this.onEditAvatar,
    required this.onEditName,
  });

  final UserProfile profile;
  final String roleLabel;
  final String? partnerName;
  final bool canEdit;
  final VoidCallback onEditAvatar;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  DriftProTheme.primaryGreen.withValues(alpha: 0.35),
                  DriftProTheme.accentBlue.withValues(alpha: 0.28),
                ]
              : [
                  DriftProTheme.primaryGreen.withValues(alpha: 0.12),
                  DriftProTheme.accentBlue.withValues(alpha: 0.08),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : DriftProTheme.primaryGreen.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white.withValues(alpha: isDark ? 0.12 : 0.9),
                backgroundImage:
                    profile.avatarUrl != null ? NetworkImage(profile.avatarUrl!) : null,
                child: profile.avatarUrl == null
                    ? Text(
                        profile.initials,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: DriftProTheme.primaryGreen.withValues(alpha: 0.95),
                        ),
                      )
                    : null,
              ),
              if (canEdit)
                Material(
                  color: DriftProTheme.primaryGreen,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEditAvatar,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: canEdit ? onEditName : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      profile.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: PartnerUi.mutedText(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.email,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: PartnerUi.mutedText(context)),
          ),
          if (partnerName != null && partnerName!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isDark ? 0.1 : 0.75),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                partnerName!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            roleLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DriftProTheme.primaryGreen.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
