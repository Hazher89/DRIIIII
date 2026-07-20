import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/permissions/access_keys.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/permissions/user_access.dart';
import '../../core/layout/mobile_layout.dart';
import '../../core/layout/mobile_shell_scaffold.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/hms/hms_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_profile.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// HMS-hub — moduler for avvik, risiko, SJA, vernerunde m.m.
class HmsScreen extends StatefulWidget {
  const HmsScreen({super.key});

  @override
  State<HmsScreen> createState() => _HmsScreenState();
}

class _HmsScreenState extends State<HmsScreen> {
  UserProfile? _profile;
  HmsDashboardStats _stats = const HmsDashboardStats();
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SupabaseService.fetchCurrentUserProfile();
    if (!mounted) return;
    setState(() => _profile = p);
    if (p?.companyId != null) {
      setState(() => _statsLoading = true);
      final s = await HmsService.loadDashboardStats(p!.companyId!);
      if (mounted) {
        setState(() {
          _stats = s;
          _statsLoading = false;
        });
      }
    } else {
      setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = _profile?.access;
    final modules = <Widget>[];

    if (a?.canAvvik == true) {
      modules.add(_buildModuleCard(
        context,
        icon: Icons.report_problem_outlined,
        title: 'Avvik',
        subtitle: 'Hurtigmaler, GPS, media og lederoppfølging',
        color: DriftProTheme.error,
        isDark: isDark,
        onTap: () => context.push(AppPaths.hmsAvvik),
      ));
    }
    if (a?.canHmsRisk == true) {
      modules.add(_buildModuleCard(
        context,
        icon: AppIcons.riskAssessment,
        title: AppStrings.riskAssessment,
        subtitle: 'ROS med ISO-felter, behandling og vedlegg',
        color: DriftProTheme.riskHigh,
        isDark: isDark,
        badge: _statsLoading ? null : '${_stats.riskCount}',
        badgeColor: _stats.highRiskCount > 0 ? DriftProTheme.error : null,
        onTap: () => context.push(AppPaths.hmsRisiko),
      ));
    }
    if (a?.canHmsRiskMatrix == true) {
      modules.add(_buildModuleCard(
        context,
        icon: Icons.grid_view_rounded,
        title: 'Risikomatrise',
        subtitle: '5×5 matrise · sannsynlighet og konsekvens',
        color: DriftProTheme.warning,
        isDark: isDark,
        onTap: () => context.push(AppPaths.hmsRisikomatrise),
      ));
    }
    if (a?.canHmsSja == true) {
      modules.add(_buildModuleCard(
        context,
        icon: AppIcons.sja,
        title: AppStrings.sjaTitle,
        subtitle: 'SJA med maler, PPE og farepunkter',
        color: DriftProTheme.accentBlue,
        isDark: isDark,
        badge: _statsLoading ? null : '${_stats.sjaOpen} åpne',
        onTap: () => context.push(AppPaths.hmsSja),
      ));
    }
    if (a?.canHmsSafetyRound == true) {
      modules.add(_buildModuleCard(
        context,
        icon: AppIcons.safetyRound,
        title: AppStrings.safetyRound,
        subtitle: 'Vernerunder med sjekklister fra mal',
        color: DriftProTheme.success,
        isDark: isDark,
        badge: _statsLoading ? null : '${_stats.safetyPlanned} planlagt',
        onTap: () => context.push(AppPaths.hmsVernerunde),
      ));
    }
    if (a?.canHmsEquipment == true) {
      modules.add(_buildModuleCard(
        context,
        icon: Icons.construction_rounded,
        title: 'Maskiner & utstyr',
        subtitle: 'Register, service og status',
        color: Colors.blueGrey,
        isDark: isDark,
        badge: _stats.equipmentNeedsService > 0
            ? '${_stats.equipmentNeedsService} service'
            : null,
        badgeColor: DriftProTheme.warning,
        onTap: () => context.push(AppPaths.hmsUtstyr),
      ));
    }
    if (a?.canHmsCompetence == true) {
      modules.add(_buildModuleCard(
        context,
        icon: Icons.card_membership_rounded,
        title: 'Kompetanse & kurs',
        subtitle: 'Kurs, bevis, PDF og kompetansematrise',
        color: Colors.indigo,
        isDark: isDark,
        badge: _stats.expiringCertificates > 0
            ? '${_stats.expiringCertificates} utløper'
            : null,
        badgeColor: DriftProTheme.warning,
        onTap: () => context.push(AppPaths.hmsKompetanse),
      ));
    }
    if (a?.canHms == true) {
      modules.add(_buildModuleCard(
        context,
        icon: Icons.school_rounded,
        title: 'Opplæring',
        subtitle: 'Søk i Hub Driftsrutiner — SOP-HUB-001',
        color: const Color(0xFF00695C),
        isDark: isDark,
        badge: 'SOP',
        onTap: () => context.push(AppPaths.hmsOpplaering),
      ));
    }
    if (a?.canHmsDocuments == true) {
      modules.add(_buildModuleCard(
        context,
        icon: AppIcons.document,
        title: AppStrings.documents,
        subtitle: 'HMS-håndbok og styrende dokumenter (DMS)',
        color: DriftProTheme.info,
        isDark: isDark,
        onTap: () => context.push(AppPaths.hmsDms),
      ));
    }

    return PermissionGuard(
      profile: _profile,
      accessKey: AccessKeys.hms,
      child: MobileShellScaffold(
        title: AppStrings.navHMS,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        backgroundColor:
            isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
        body: _profile == null
            ? const DriftProLoadingCenter()
            : modules.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Du har ikke tilgang til HMS-moduler.\n'
                        'Kontakt superadmin.',
                        textAlign: TextAlign.center,
                        style: DriftProTheme.bodyMd
                            .copyWith(color: Colors.grey),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      children: [
                        _buildVersionBanner(isDark),
                        const SizedBox(height: 12),
                        _buildKpiRow(isDark),
                        const SizedBox(height: 20),
                        Text('Moduler', style: DriftProTheme.headingSm),
                        const SizedBox(height: 12),
                        for (var i = 0; i < modules.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          modules[i],
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'Maler er tilgjengelig når du oppretter risiko, SJA eller vernerunde — velg «Ny» og «Start fra mal».',
                          style: DriftProTheme.caption,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildVersionBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DriftProTheme.primaryGreen.withValues(alpha: 0.9),
            DriftProTheme.accentBlue.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HMS Plattform v2',
                  style: DriftProTheme.labelMd.copyWith(color: Colors.white),
                ),
                Text(
                  'KPI · maler · ROS · Supabase',
                  style: DriftProTheme.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(bool isDark) {
    if (MobileLayout.isCompact(context)) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _kpiTile(isDark, 'Risikoer', '${_stats.riskCount}',
                  Icons.warning_amber_rounded, DriftProTheme.riskHigh)),
              const SizedBox(width: 8),
              Expanded(child: _kpiTile(isDark, 'Høy risiko', '${_stats.highRiskCount}',
                  Icons.priority_high, DriftProTheme.error)),
            ],
          ),
          const SizedBox(height: 8),
          _kpiTile(isDark, 'SJA åpne', '${_stats.sjaOpen}', AppIcons.sja,
              DriftProTheme.accentBlue),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: _kpiTile(
            isDark,
            'Risikoer',
            '${_stats.riskCount}',
            Icons.warning_amber_rounded,
            DriftProTheme.riskHigh,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiTile(
            isDark,
            'Høy risiko',
            '${_stats.highRiskCount}',
            Icons.priority_high,
            DriftProTheme.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiTile(
            isDark,
            'SJA åpne',
            '${_stats.sjaOpen}',
            AppIcons.sja,
            DriftProTheme.accentBlue,
          ),
        ),
      ],
    );
  }

  Widget _kpiTile(
    bool isDark,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: DriftProTheme.headingSm),
          Text(label, style: DriftProTheme.caption),
        ],
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DriftProTheme.labelLg),
                    const SizedBox(height: 4),
                    Text(subtitle, style: DriftProTheme.caption),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor ?? color,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
