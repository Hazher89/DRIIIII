import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/session_sign_out.dart';
import '../../core/permissions/user_access.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_icons.dart';
import '../../models/user_profile.dart';
import '../more/driftpro_platform_catalog.dart';
import '../more/widgets/info_page_scaffold.dart';
import 'delete_own_account_dialog.dart';
import 'employee_change_password_sheet.dart';
import 'widgets/profile_children_under_12_card.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Profil — iOS-vennlig Settings-layout: konto, personvern/vilkår og sletting tydelig.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  String? _departmentName;
  bool _isLoading = true;

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      String? departmentName;
      if (profile?.departmentId != null) {
        final companyId =
            profile!.companyId ?? await SupabaseService.discoverBootstrapCompanyId();
        if (companyId != null) {
          final depts = await SupabaseService.fetchDepartments(companyId: companyId);
          for (final d in depts) {
            if (d.id == profile.departmentId) {
              departmentName = d.name;
              break;
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _departmentName = departmentName;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const DriftProLoadingPage();
    }

    if (_profile == null) {
      return const Scaffold(body: Center(child: Text('Kunne ikke laste profil')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF2F2F7),
      ),
      body: _buildProfileBody(),
    );
  }

  Widget _buildProfileBody() {
    final p = _profile!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _ProfileHeader(profile: p),
        const SizedBox(height: 20),
        if (p.partnerId == null) ...[
          ProfileChildrenUnder12Card(
            profile: p,
            onSaved: _loadProfile,
          ),
          const SizedBox(height: 20),
        ],
        _SectionLabel('Konto'),
        _SettingsGroup(
          children: [
            _InfoRow(
              icon: AppIcons.profile,
              label: 'E-post',
              value: p.email,
            ),
            _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Telefon',
              value: p.phone ?? 'Ikke satt',
            ),
            _InfoRow(
              icon: Icons.badge_rounded,
              label: 'Ansattnummer',
              value: p.employeeNumber ?? 'Ikke satt',
            ),
            _InfoRow(
              icon: AppIcons.department,
              label: 'Avdeling',
              value: _departmentName ??
                  (p.departmentId != null ? 'Ukjent avdeling' : 'Ingen avdeling'),
              showDivider: false,
            ),
          ],
        ),
        if (p.partnerId == null) ...[
          const SizedBox(height: 24),
          _SectionLabel('Sikkerhet'),
          _SettingsGroup(
            children: [
              _ActionRow(
                icon: Icons.lock_outline_rounded,
                title: 'Bytt passord',
                subtitle: 'SMS-bekreftelse kreves',
                onTap: () => showEmployeeChangePasswordSheet(context),
                showDivider: false,
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _SectionLabel('Personvern og vilkår'),
        _SettingsGroup(
          children: [
            _ActionRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Personvernerklæring',
              subtitle: 'Åpner hazher.no',
              onTap: () => launchInfoUrl(DriftProPlatformCatalog.privacyPolicyUrl),
            ),
            _ActionRow(
              icon: Icons.description_outlined,
              title: 'Vilkår for bruk',
              subtitle: 'Åpner hazher.no',
              onTap: () => launchInfoUrl(DriftProPlatformCatalog.termsOfUseUrl),
            ),
            _ActionRow(
              icon: Icons.shield_outlined,
              title: 'Personvern i appen',
              subtitle: 'Rettigheter, lagring og kontakt',
              onTap: () => context.push(AppPaths.morePersonvern),
              showDivider: false,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionLabel('Kontoen din'),
        _SettingsGroup(
          children: [
            _ActionRow(
              icon: Icons.delete_forever_outlined,
              title: 'Slett konto',
              subtitle: 'Fjern innlogging og personopplysninger',
              titleColor: DriftProTheme.error,
              iconColor: DriftProTheme.error,
              onTap: () => showDeleteOwnAccountDialog(context),
              showDivider: false,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(
            'DriftPro er kun for ${DriftProPlatformCatalog.companyName}. '
            'Bedriften kan fortsatt være lovpålagt å beholde enkelte HMS-/HR-data '
            'uten din identitet.',
            style: DriftProTheme.caption.copyWith(
              color: Colors.grey[600],
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () async => signOutFromPortal(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: DriftProTheme.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: const Text(
              'Logg ut',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
          backgroundImage: profile.avatarUrl != null
              ? NetworkImage(profile.avatarUrl!)
              : null,
          child: profile.avatarUrl == null
              ? Text(
                  profile.initials,
                  style: DriftProTheme.headingXl.copyWith(
                    color: DriftProTheme.primaryGreen,
                    fontSize: 28,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Text(profile.fullName, style: DriftProTheme.headingLg),
        const SizedBox(height: 4),
        Text(
          profile.jobTitle ?? 'Ansatt',
          style: DriftProTheme.bodyMd.copyWith(color: Colors.grey[600]),
        ),
        if (profile.isSuperAdmin) ...[
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.admin_panel_settings, size: 18),
            label: const Text('Superadmin'),
            backgroundColor: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: DriftProTheme.caption.copyWith(
          color: Colors.grey[600],
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: DriftProTheme.primaryGreen, size: 22),
          title: Text(label, style: DriftProTheme.caption),
          subtitle: Text(
            value,
            style: DriftProTheme.bodyMd.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 56, color: Colors.grey.shade200),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.titleColor,
    this.iconColor,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? titleColor;
  final Color? iconColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          leading: Icon(
            icon,
            color: iconColor ?? Colors.grey[700],
            size: 22,
          ),
          title: Text(
            title,
            style: DriftProTheme.bodyMd.copyWith(
              fontWeight: FontWeight.w500,
              color: titleColor,
            ),
          ),
          subtitle: subtitle != null
              ? Text(subtitle!, style: DriftProTheme.caption)
              : null,
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey[400],
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 56, color: Colors.grey.shade200),
      ],
    );
  }
}
