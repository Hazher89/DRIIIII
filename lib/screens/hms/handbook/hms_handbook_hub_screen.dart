import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/hms/mavi_hms_handbook.dart';
import '../../../core/permissions/access_session_cache.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';

/// Profesjonell oversikt over MAVI IK-system og vedlegg.
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
        HmsHandbookCategory.risiko => const Color(0xFFB45309),
        HmsHandbookCategory.revisjon => const Color(0xFF475569),
        HmsHandbookCategory.avvik => const Color(0xFF9A3412),
        HmsHandbookCategory.sja => DriftProTheme.accentBlue,
        HmsHandbookCategory.beredskap => const Color(0xFF991B1B),
        HmsHandbookCategory.partnere => const Color(0xFF0F766E),
        HmsHandbookCategory.instrukser => const Color(0xFF3F6212),
        HmsHandbookCategory.signatur => const Color(0xFF4338CA),
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF5F6F4);
    final ink = isDark ? Colors.white : const Color(0xFF142018);
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF5C6B60);
    final canAvvik = AccessSessionCache.access?.canAvvik == true;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'HMS-håndbok',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            letterSpacing: -0.2,
            color: ink,
          ),
        ),
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _HeroBanner(isDark: isDark),
          const SizedBox(height: 28),
          for (final cat in MaviHmsHandbook.categories) ...[
            _CategoryBlock(
              category: cat,
              icon: _iconFor(cat),
              color: _colorFor(cat),
              isDark: isDark,
              ink: ink,
              muted: muted,
              docs: MaviHmsHandbook.docsIn(cat),
            ),
            const SizedBox(height: 26),
          ],
          Text(
            'RELATERTE MODULER',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: muted,
            ),
          ),
          const SizedBox(height: 12),
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
              if (canAvvik)
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

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1A12) : const Color(0xFF14301A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MAVI LOGISTIKK AS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'HMS & QHSE',
            style: GoogleFonts.sourceSerif4(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              height: 1.15,
              letterSpacing: -0.4,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Internkontroll, miljø, risiko, beredskap og partnerrutiner — '
            'samlet og strukturert. Åpne et dokument for full tekst.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.88),
            ),
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
    required this.ink,
    required this.muted,
    required this.docs,
  });

  final HmsHandbookCategory category;
  final IconData icon;
  final Color color;
  final bool isDark;
  final Color ink;
  final Color muted;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.22 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      letterSpacing: -0.2,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    category.subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.4,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: isDark ? DriftProTheme.cardDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE6EBE7),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < docs.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 66,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFEEF2EF),
                  ),
                _DocRow(
                  doc: docs[i],
                  color: color,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                  badge: _badgeShort(docs[i].vedleggNr),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.doc,
    required this.color,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.badge,
  });

  final HmsHandbookDoc doc;
  final Color color;
  final bool isDark;
  final Color ink;
  final Color muted;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppPaths.hmsHandbokDoc(doc.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
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
                      doc.title,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        letterSpacing: -0.15,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doc.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        height: 1.4,
                        color: muted,
                      ),
                    ),
                    if (doc.moduleLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        doc.moduleLabel!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DriftProTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: muted.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onTap,
      backgroundColor: isDark ? DriftProTheme.cardDark : Colors.white,
      side: BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : const Color(0xFFDCE3DD),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
