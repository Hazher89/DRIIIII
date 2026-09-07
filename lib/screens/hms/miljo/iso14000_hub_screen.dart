import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/hms/iso14000_guide.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/theme/app_theme.dart';

/// Smart oversikt over ISO 14000-serien — koblet til MAVI miljø i DriftPro.
class Iso14000HubScreen extends StatefulWidget {
  const Iso14000HubScreen({super.key});

  @override
  State<Iso14000HubScreen> createState() => _Iso14000HubScreenState();
}

class _Iso14000HubScreenState extends State<Iso14000HubScreen> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF4F7F4);

    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 168,
            backgroundColor: const Color(0xFF1B5E20),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1B5E20),
                      Color(0xFF2E7D32),
                      Color(0xFF1565C0),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          Iso14000Guide.seriesTitle,
                          style: DriftProTheme.headingMd.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${Iso14000Guide.seriesSubtitle} · praktisk guide for MAVI',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.35,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _InfoBanner(isDark: isDark),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'PDCA-hjulet',
                style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: _PdcaStrip(isDark: isDark),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Standardene i samlingen',
                style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList.separated(
              itemCount: Iso14000Guide.standards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = Iso14000Guide.standards[i];
                final open = _expandedId == s.id;
                return _StandardTile(
                  standard: s,
                  isDark: isDark,
                  expanded: open,
                  onToggle: () => setState(() {
                    _expandedId = open ? null : s.id;
                  }),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverToBoxAdapter(
              child: _QuickLinks(isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: const Color(0xFF2E7D32).withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Iso14000Guide.disclaimer,
              style: TextStyle(
                height: 1.4,
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF3A4A3A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdcaStrip extends StatelessWidget {
  const _PdcaStrip({required this.isDark});
  final bool isDark;

  static const _colors = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFFF9A825),
    Color(0xFFC62828),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Iso14000Guide.pdca.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final step = Iso14000Guide.pdca[i];
          final c = _colors[i % _colors.length];
          return Container(
            width: 168,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? DriftProTheme.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: c,
                      child: Text(
                        step.letter,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.subtitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: c,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final p in step.points.take(3))
                  Text(
                    '• $p',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: isDark ? Colors.white70 : const Color(0xFF445544),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StandardTile extends StatelessWidget {
  const _StandardTile({
    required this.standard,
    required this.isDark,
    required this.expanded,
    required this.onToggle,
  });

  final IsoStandardCard standard;
  final bool isDark;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      standard.shortTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1B5E20),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          standard.code,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          standard.title,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      standard.role,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black45,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 12),
                Text(
                  standard.summary,
                  style: TextStyle(
                    height: 1.45,
                    fontSize: 13.5,
                    color: isDark ? Colors.white70 : const Color(0xFF2A3A2A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Relevant for MAVI',
                  style: DriftProTheme.labelMd.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final line in standard.forMavi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(fontWeight: FontWeight.w700)),
                        Expanded(child: Text(line, style: const TextStyle(height: 1.35))),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (standard.handbookDocId != null)
                      FilledButton.tonalIcon(
                        onPressed: () => context.push(
                          AppPaths.hmsHandbokDoc(standard.handbookDocId!),
                        ),
                        icon: const Icon(Icons.menu_book_outlined, size: 18),
                        label: const Text('Åpne i håndbok'),
                      ),
                    if (standard.modulePath != null && standard.moduleLabel != null)
                      OutlinedButton.icon(
                        onPressed: () => context.push(standard.modulePath!),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(standard.moduleLabel!),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickLinks extends StatelessWidget {
  const _QuickLinks({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final links = <({String label, String path, IconData icon})>[
      (
        label: 'MAVI miljøhåndbok (14001)',
        path: AppPaths.hmsHandbokDoc('handbok_miljo_14001'),
        icon: Icons.eco_outlined,
      ),
      (
        label: 'Miljøaspekter & samsvar',
        path: AppPaths.hmsHandbokDoc('miljoaspekter_samsvar'),
        icon: Icons.checklist_outlined,
      ),
      (
        label: 'Risikokartlegging miljø',
        path: AppPaths.hmsHandbokDoc('risikokartlegging_miljo'),
        icon: Icons.warning_amber_outlined,
      ),
      (
        label: 'Revisjonsplan',
        path: AppPaths.hmsHandbokDoc('revisjonsplan_3_aar'),
        icon: Icons.event_note_outlined,
      ),
      (
        label: 'Avvik / RUH',
        path: AppPaths.hmsAvvik,
        icon: Icons.report_problem_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hurtigvalg i DriftPro',
          style: DriftProTheme.headingSm.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final l in links) ...[
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: isDark ? DriftProTheme.cardDark : Colors.white,
            leading: Icon(l.icon, color: const Color(0xFF2E7D32)),
            title: Text(l.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(l.path),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
