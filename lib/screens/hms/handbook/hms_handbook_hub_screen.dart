import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/hms/mavi_hms_handbook.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';

/// Ryddig oversikt over MAVI IK-system og vedlegg — med lenker til riktig modul.
class HmsHandbookHubScreen extends StatelessWidget {
  const HmsHandbookHubScreen({super.key});

  IconData _iconFor(HmsHandbookCategory c) => switch (c) {
        HmsHandbookCategory.styring => Icons.account_balance_outlined,
        HmsHandbookCategory.risiko => Icons.warning_amber_rounded,
        HmsHandbookCategory.avvik => Icons.report_problem_outlined,
        HmsHandbookCategory.sja => Icons.assignment_outlined,
        HmsHandbookCategory.beredskap => Icons.emergency_outlined,
        HmsHandbookCategory.instrukser => Icons.menu_book_outlined,
        HmsHandbookCategory.signatur => Icons.draw_outlined,
      };

  Color _colorFor(HmsHandbookCategory c) => switch (c) {
        HmsHandbookCategory.styring => DriftProTheme.primaryGreen,
        HmsHandbookCategory.risiko => DriftProTheme.riskHigh,
        HmsHandbookCategory.avvik => DriftProTheme.error,
        HmsHandbookCategory.sja => DriftProTheme.accentBlue,
        HmsHandbookCategory.beredskap => const Color(0xFFC62828),
        HmsHandbookCategory.instrukser => const Color(0xFF2E7D32),
        HmsHandbookCategory.signatur => Colors.indigo,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF7F8F6);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('HMS-håndbok'),
        backgroundColor: bg,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  DriftProTheme.primaryGreen,
                  DriftProTheme.primaryGreen.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MAVI Logistikk — IK-system',
                  style: DriftProTheme.headingSm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Alle styrende dokumenter og vedlegg på ett sted. '
                  'Hvert dokument peker til riktig sted i DriftPro når du skal jobbe videre.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final cat in MaviHmsHandbook.categories) ...[
            _CategoryBlock(
              category: cat,
              icon: _iconFor(cat),
              color: _colorFor(cat),
              isDark: isDark,
              docs: MaviHmsHandbook.docsIn(cat),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            'Hurtigvalg',
            style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickChip(
                label: 'Risiko',
                onTap: () => context.push(AppPaths.hmsRisiko),
              ),
              _QuickChip(
                label: 'Vernerunde',
                onTap: () => context.push(AppPaths.hmsVernerunde),
              ),
              _QuickChip(
                label: 'Tungløft',
                onTap: () => context.push(AppPaths.hmsTungloft),
              ),
              _QuickChip(
                label: 'SJA',
                onTap: () => context.push(AppPaths.hmsSja),
              ),
              _QuickChip(
                label: 'Avvik',
                onTap: () => context.push(AppPaths.hmsAvvik),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.category,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.docs,
  });

  final HmsHandbookCategory category;
  final IconData icon;
  final Color color;
  final bool isDark;
  final List<HmsHandbookDoc> docs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: DriftProTheme.labelLg.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    category.subtitle,
                    style: DriftProTheme.caption.copyWith(
                      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final d in docs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push(AppPaths.hmsHandbokDoc(d.id)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          d.vedleggNr ?? '•',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                              ),
                            ),
                            if (d.moduleLabel != null)
                              Text(
                                '→ ${d.moduleLabel}',
                                style: DriftProTheme.caption.copyWith(
                                  color: DriftProTheme.primaryGreen,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
    );
  }
}
