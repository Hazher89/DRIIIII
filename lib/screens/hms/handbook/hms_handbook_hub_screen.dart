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
        HmsHandbookCategory.miljo => Icons.eco_outlined,
        HmsHandbookCategory.risiko => Icons.warning_amber_rounded,
        HmsHandbookCategory.revisjon => Icons.fact_check_outlined,
        HmsHandbookCategory.avvik => Icons.report_problem_outlined,
        HmsHandbookCategory.sja => Icons.assignment_outlined,
        HmsHandbookCategory.beredskap => Icons.emergency_outlined,
        HmsHandbookCategory.partnere => Icons.handshake_outlined,
        HmsHandbookCategory.instrukser => Icons.menu_book_outlined,
        HmsHandbookCategory.signatur => Icons.draw_outlined,
      };

  Color _colorFor(HmsHandbookCategory c) => switch (c) {
        HmsHandbookCategory.styring => DriftProTheme.primaryGreen,
        HmsHandbookCategory.miljo => const Color(0xFF2E7D32),
        HmsHandbookCategory.risiko => DriftProTheme.riskHigh,
        HmsHandbookCategory.revisjon => const Color(0xFF546E7A),
        HmsHandbookCategory.avvik => DriftProTheme.error,
        HmsHandbookCategory.sja => DriftProTheme.accentBlue,
        HmsHandbookCategory.beredskap => const Color(0xFFC62828),
        HmsHandbookCategory.partnere => const Color(0xFF00695C),
        HmsHandbookCategory.instrukser => const Color(0xFF558B2F),
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
                  'MAVI Logistikk — HMS & QHSE',
                  style: DriftProTheme.headingSm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'IK-system, miljø, risiko, beredskap, revisjon og partnerrutiner — '
                  'fra Landax og MAVI, ryddig fordelt. Hvert dokument peker til riktig modul når du skal jobbe videre.',
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
                label: 'ISO 14000',
                onTap: () => context.push(AppPaths.hmsIso14000),
              ),
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
              _QuickChip(
                label: 'Opplæring',
                onTap: () => context.push(AppPaths.hmsOpplaering),
              ),
              _QuickChip(
                label: 'Utstyr',
                onTap: () => context.push(AppPaths.hmsUtstyr),
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

  static String _badgeShort(String? raw) {
    if (raw == null || raw.isEmpty) return '•';
    final r = raw.trim();
    if (r.toLowerCase() == 'landax') return 'LX';
    if (r.toLowerCase() == 'export') return 'EX';
    if (r.toLowerCase().startsWith('hoved')) return 'HK';
    if (r.toLowerCase() == 'plan') return 'P';
    if (r.length <= 3) return r;
    return r.length <= 4 ? r : r.substring(0, 2);
  }

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
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              elevation: isDark ? 0 : 0.4,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push(AppPaths.hmsHandbokDoc(d.id)),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(
                          _badgeShort(d.vedleggNr),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: color,
                            letterSpacing: 0.2,
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
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                                height: 1.25,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.92)
                                    : const Color(0xFF152018),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              d.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DriftProTheme.caption.copyWith(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.48)
                                    : const Color(0xFF6A7A6E),
                                height: 1.35,
                              ),
                            ),
                            if (d.moduleLabel != null) ...[
                              const SizedBox(height: 5),
                              Text(
                                '→ ${d.moduleLabel}',
                                style: DriftProTheme.caption.copyWith(
                                  color: DriftProTheme.primaryGreen,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.28),
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
