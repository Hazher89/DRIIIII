import 'package:flutter/material.dart';
import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../common/placeholder_screen.dart';
import 'risk_assessment/risk_assessment_list_screen.dart';
import 'sja/sja_list_screen.dart';
import 'safety_rounds/safety_round_list_screen.dart';
import 'documents/document_list_screen.dart';
import '../dms/dms_screen.dart';
import 'equipment/equipment_registry_screen.dart';
import 'competence/competence_matrix_screen.dart';

class HmsScreen extends StatelessWidget {
  const HmsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text(AppStrings.navHMS)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildModuleCard(
            context,
            icon: AppIcons.riskAssessment,
            title: AppStrings.riskAssessment,
            subtitle: 'Opprett og administrer risikoanalyser med 5×5 matrise',
            color: DriftProTheme.riskHigh,
            badge: '2 høyrisiko',
            badgeColor: DriftProTheme.error,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RiskAssessmentListScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildModuleCard(
            context,
            icon: AppIcons.sja,
            title: AppStrings.sjaTitle,
            subtitle: 'Fyll ut og signer SJA før risikofylt arbeid',
            color: DriftProTheme.accentBlue,
            badge: '4 ventende',
            badgeColor: DriftProTheme.warning,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SjaListScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildModuleCard(
            context,
            icon: AppIcons.safetyRound,
            title: AppStrings.safetyRound,
            subtitle: 'Planlegg og gjennomfør sikkerhetsrunder',
            color: DriftProTheme.success,
            badge: '1 planlagt',
            badgeColor: DriftProTheme.info,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SafetyRoundListScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildModuleCard(
            context,
            icon: AppIcons.riskMatrix,
            title: AppStrings.riskMatrix,
            subtitle: 'Visuell oversikt over alle risikoer',
            color: DriftProTheme.warning,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PlaceholderScreen(
                    title: 'Risiko-matrise',
                    description:
                        'Her kommer en interaktiv risiko-matrise '
                        'bygget på Supabase-data.',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildModuleCard(
            context,
            icon: Icons.construction_rounded,
            title: 'Maskiner & Utstyr',
            subtitle: 'Oversikt over verktøy, maskiner og vedlikehold',
            color: Colors.blueGrey,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EquipmentRegistryScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildModuleCard(
            context,
            icon: Icons.card_membership_rounded,
            title: 'Kompetanse & Kurs',
            subtitle: 'Sertifikater, kursbevis og kompetansematrise',
            color: Colors.indigo,
            badge: '3 utløper',
            badgeColor: Colors.red,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CompetenceMatrixScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildModuleCard(
            context,
            icon: AppIcons.document,
            title: AppStrings.documents,
            subtitle: 'HMS-håndbok og styrende dokumenter',
            color: DriftProTheme.info,
            isDark: isDark,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DmsScreen()),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildRiskMatrixPreview(isDark),
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
    String? badge,
    Color? badgeColor,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: DriftProTheme.headingSm.copyWith(
                        color: isDark ? Colors.white : Colors.grey[900],
                      )),
                      const SizedBox(height: 4),
                      Text(subtitle, style: DriftProTheme.bodySm.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      )),
                      if (badge != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? color).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(DriftProTheme.radiusRound),
                          ),
                          child: Text(badge, style: DriftProTheme.labelSm.copyWith(
                            color: badgeColor ?? color, fontSize: 10,
                          )),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16,
                  color: isDark ? Colors.grey[600] : Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRiskMatrixPreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(DriftProTheme.radiusLg),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100,
        ),
        boxShadow: DriftProTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.riskMatrix, style: DriftProTheme.headingSm.copyWith(
            color: isDark ? Colors.white : Colors.grey[900],
          )),
          const SizedBox(height: 4),
          Text('${AppStrings.probability} × ${AppStrings.consequence}',
            style: DriftProTheme.bodySm.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            )),
          const SizedBox(height: 16),
          _buildMatrix(isDark),
        ],
      ),
    );
  }

  Widget _buildMatrix(bool isDark) {
    Color getCellColor(int p, int c) {
      final score = p * c;
      if (score <= 4) return DriftProTheme.riskLow;
      if (score <= 9) return DriftProTheme.riskMedium;
      if (score <= 14) return DriftProTheme.riskHigh;
      if (score <= 19) return DriftProTheme.riskCritical;
      return DriftProTheme.riskExtreme;
    }

    return Column(
      children: List.generate(5, (row) {
        final prob = 5 - row;
        return Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('$prob', textAlign: TextAlign.center,
                style: DriftProTheme.labelSm.copyWith(
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                )),
            ),
            ...List.generate(5, (col) {
              final cons = col + 1;
              final score = prob * cons;
              final color = getCellColor(prob, cons);
              return Expanded(
                child: Container(
                  height: 36,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.4), width: 1),
                  ),
                  child: Center(
                    child: Text('$score', style: DriftProTheme.labelSm.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    )),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }
}
